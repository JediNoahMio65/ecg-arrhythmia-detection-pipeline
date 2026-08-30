// Tests for the WFDB annotation decoder.
//
// The suite has three layers:
//
//   1. Table tests over the annotation code and AAMI class mappings.
//   2. Synthetic byte-sequence tests that exercise each structural code in
//      isolation, including the malformed cases that must be rejected.
//   3. A field-by-field comparison of every annotation in MIT-BIH record 100
//      against output captured from the reference WFDB implementation.
//
// The reference fixture is produced by tests/data/generate_reference.py. Tests
// that need the MIT-BIH data or the fixture skip themselves when those files
// are absent, so the suite still runs on a fresh clone.

#include "wfdb/annotation.hpp"

#include <gtest/gtest.h>

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr double kMitBihSamplingFrequency = 360.0;

std::string record_path(const std::string& name) {
  return std::string(WFDB_TEST_DATA_DIR) + "/" + name;
}

std::string fixture_path(const std::string& name) {
  return std::string(WFDB_TEST_FIXTURE_DIR) + "/" + name;
}

bool file_exists(const std::string& path) {
  std::ifstream stream(path, std::ios::binary);
  return stream.good();
}

// Builds a little-endian annotation word from a type code and a ten-bit value.
void push_word(std::vector<std::uint8_t>& bytes, int code, int value) {
  const std::uint32_t word = (static_cast<std::uint32_t>(code) << 10) |
                             (static_cast<std::uint32_t>(value) & 0x3FFu);
  bytes.push_back(static_cast<std::uint8_t>(word & 0xFFu));
  bytes.push_back(static_cast<std::uint8_t>((word >> 8) & 0xFFu));
}

// Appends a raw little-endian word, for auxiliary payloads and SKIP intervals.
void push_raw_word(std::vector<std::uint8_t>& bytes, std::uint16_t word) {
  bytes.push_back(static_cast<std::uint8_t>(word & 0xFFu));
  bytes.push_back(static_cast<std::uint8_t>((word >> 8) & 0xFFu));
}

void push_terminator(std::vector<std::uint8_t>& bytes) {
  push_raw_word(bytes, 0);
}

// One row of the reference fixture.
struct ReferenceRow {
  std::int64_t sample = 0;
  int code = 0;
  int subtype = 0;
  int chan = 0;
  int num = 0;
  std::string aux;  // Decoded from the hex column.
};

std::string from_hex(const std::string& hex) {
  std::string out;
  for (std::size_t i = 0; i + 1 < hex.size(); i += 2) {
    const std::string byte_text = hex.substr(i, 2);
    const auto value = static_cast<unsigned long>(std::stoul(byte_text, nullptr, 16));
    out.push_back(static_cast<char>(value));
  }
  return out;
}

// Reads the CSV fixture. Tolerates CRLF line endings so that the file behaves
// identically whether it was generated on Windows or on Linux.
std::vector<ReferenceRow> read_reference(const std::string& path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) {
    return {};
  }

  std::vector<ReferenceRow> rows;
  std::string line;
  bool first = true;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (line.empty()) {
      continue;
    }
    if (first) {
      first = false;  // Skip the header row.
      continue;
    }

    std::istringstream fields(line);
    std::string sample, code, subtype, chan, num, aux_hex;
    std::getline(fields, sample, ',');
    std::getline(fields, code, ',');
    std::getline(fields, subtype, ',');
    std::getline(fields, chan, ',');
    std::getline(fields, num, ',');
    std::getline(fields, aux_hex, ',');

    ReferenceRow row;
    row.sample = std::stoll(sample);
    row.code = std::stoi(code);
    row.subtype = std::stoi(subtype);
    row.chan = std::stoi(chan);
    row.num = std::stoi(num);
    row.aux = from_hex(aux_hex);
    rows.push_back(row);
  }
  return rows;
}

}  // namespace

// ---------------------------------------------------------------------------
// Code table
// ---------------------------------------------------------------------------

TEST(AnnotationCodes, MapsRepresentativeSymbols) {
  EXPECT_EQ(wfdb::annotation_symbol(1), "N");
  EXPECT_EQ(wfdb::annotation_symbol(5), "V");
  EXPECT_EQ(wfdb::annotation_symbol(8), "A");
  EXPECT_EQ(wfdb::annotation_symbol(12), "/");
  EXPECT_EQ(wfdb::annotation_symbol(28), "+");
  EXPECT_EQ(wfdb::annotation_symbol(41), "r");
}

TEST(AnnotationCodes, MapsDescriptions) {
  EXPECT_EQ(wfdb::annotation_description(1), "Normal beat");
  EXPECT_EQ(wfdb::annotation_description(5), "Premature ventricular contraction");
  EXPECT_EQ(wfdb::annotation_description(28), "Rhythm change");
}

TEST(AnnotationCodes, UnassignedAndOutOfRangeCodesAreHandled) {
  // Codes 15 and 17 fall inside the table but carry no assigned meaning.
  EXPECT_EQ(wfdb::annotation_symbol(15), "");
  EXPECT_EQ(wfdb::annotation_symbol(17), "");
  // Code 0 is the terminator and is not a real annotation.
  EXPECT_EQ(wfdb::annotation_symbol(0), "");
  EXPECT_EQ(wfdb::annotation_description(0), "Not an actual annotation");
  // Out-of-range lookups must not read past the table.
  EXPECT_EQ(wfdb::annotation_symbol(-1), "");
  EXPECT_EQ(wfdb::annotation_symbol(999), "");
  EXPECT_EQ(wfdb::annotation_description(999), "Undefined annotation code");
}

TEST(AnnotationCodes, BeatCodesMatchTheWfdbQrsSet) {
  // The twenty codes WFDB reports as QRS annotations.
  const std::vector<int> beat_codes = {1,  2,  3,  4,  5,  6,  7,  8,  9,  10,
                                       11, 12, 13, 25, 30, 31, 34, 35, 38, 41};
  for (const int code : beat_codes) {
    EXPECT_TRUE(wfdb::is_beat_code(code))
        << "code " << code << " (" << wfdb::annotation_symbol(code)
        << ") should be a beat";
  }

  // Every other code in the table must not be counted as a beat.
  for (int code = 0; code <= wfdb::kMaxCode; ++code) {
    const bool expected =
        std::find(beat_codes.begin(), beat_codes.end(), code) != beat_codes.end();
    EXPECT_EQ(wfdb::is_beat_code(code), expected) << "code " << code;
  }
}

TEST(AnnotationCodes, NonBeatCodesAreNotBeats) {
  EXPECT_FALSE(wfdb::is_beat_code(14));  // ~ signal quality change
  EXPECT_FALSE(wfdb::is_beat_code(16));  // | isolated artifact
  EXPECT_FALSE(wfdb::is_beat_code(28));  // + rhythm change
  EXPECT_FALSE(wfdb::is_beat_code(32));  // [ start of flutter
}

// ---------------------------------------------------------------------------
// AAMI classes
// ---------------------------------------------------------------------------

TEST(AamiMapping, GroupsBeatCodesIntoFiveClasses) {
  const std::vector<int> normal = {1, 2, 3, 25, 34, 11};
  const std::vector<int> supraventricular = {8, 4, 7, 9, 35};
  const std::vector<int> ventricular = {5, 10, 41};
  const std::vector<int> fusion = {6};
  const std::vector<int> unknown = {12, 38, 13, 30, 31};

  for (const int code : normal) {
    EXPECT_EQ(wfdb::aami_class_of(code), wfdb::AamiClass::Normal) << "code " << code;
  }
  for (const int code : supraventricular) {
    EXPECT_EQ(wfdb::aami_class_of(code), wfdb::AamiClass::Supraventricular)
        << "code " << code;
  }
  for (const int code : ventricular) {
    EXPECT_EQ(wfdb::aami_class_of(code), wfdb::AamiClass::Ventricular)
        << "code " << code;
  }
  for (const int code : fusion) {
    EXPECT_EQ(wfdb::aami_class_of(code), wfdb::AamiClass::Fusion) << "code " << code;
  }
  for (const int code : unknown) {
    EXPECT_EQ(wfdb::aami_class_of(code), wfdb::AamiClass::Unknown) << "code " << code;
  }
}

TEST(AamiMapping, EveryBeatCodeReceivesAClass) {
  // No beat may fall through to NotABeat, and no non-beat may receive a class.
  for (int code = 0; code <= wfdb::kMaxCode; ++code) {
    if (wfdb::is_beat_code(code)) {
      EXPECT_NE(wfdb::aami_class_of(code), wfdb::AamiClass::NotABeat)
          << "beat code " << code << " has no AAMI class";
    } else {
      EXPECT_EQ(wfdb::aami_class_of(code), wfdb::AamiClass::NotABeat)
          << "non-beat code " << code << " was given an AAMI class";
    }
  }
}

TEST(AamiMapping, ReportsSymbolsAndNames) {
  EXPECT_STREQ(wfdb::aami_class_symbol(wfdb::AamiClass::Normal), "N");
  EXPECT_STREQ(wfdb::aami_class_symbol(wfdb::AamiClass::Supraventricular), "S");
  EXPECT_STREQ(wfdb::aami_class_symbol(wfdb::AamiClass::Ventricular), "V");
  EXPECT_STREQ(wfdb::aami_class_symbol(wfdb::AamiClass::Fusion), "F");
  EXPECT_STREQ(wfdb::aami_class_symbol(wfdb::AamiClass::Unknown), "Q");
  EXPECT_STREQ(wfdb::aami_class_symbol(wfdb::AamiClass::NotABeat), "-");
  EXPECT_STREQ(wfdb::aami_class_name(wfdb::AamiClass::Ventricular),
               "Ventricular ectopic");
}

// ---------------------------------------------------------------------------
// Decoder: well-formed synthetic input
// ---------------------------------------------------------------------------

TEST(AnnotationDecoder, AccumulatesIntervalsIntoAbsoluteSampleNumbers) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 100);  // N at sample 100
  push_word(bytes, 1, 250);  // N at sample 350
  push_word(bytes, 5, 300);  // V at sample 650
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 3u);
  EXPECT_EQ(annotations[0].sample, 100);
  EXPECT_EQ(annotations[1].sample, 350);
  EXPECT_EQ(annotations[2].sample, 650);
  EXPECT_EQ(annotations[2].symbol(), "V");
}

TEST(AnnotationDecoder, HandlesTheMaximumTenBitInterval) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 1023);  // The largest interval the field can hold.
  push_word(bytes, 1, 1023);
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 2u);
  EXPECT_EQ(annotations[0].sample, 1023);
  EXPECT_EQ(annotations[1].sample, 2046);
}

TEST(AnnotationDecoder, TreatsAnEmptyFileAsNoAnnotations) {
  EXPECT_TRUE(wfdb::decode_annotations({}).empty());
}

TEST(AnnotationDecoder, StopsAtTheTerminatorWord) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 10);
  push_terminator(bytes);
  push_word(bytes, 1, 10);  // Must never be reached.

  EXPECT_EQ(wfdb::decode_annotations(bytes).size(), 1u);
}

TEST(AnnotationDecoder, SubtypeAppliesToOneAnnotationOnly) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 5, 100);              // V
  push_word(bytes, wfdb::kSub, 1);       // subtype 1, attached to the V
  push_word(bytes, 1, 100);              // N, must fall back to subtype 0
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 2u);
  EXPECT_EQ(annotations[0].subtype, 1);
  EXPECT_EQ(annotations[1].subtype, 0);
}

TEST(AnnotationDecoder, SubtypeAndNumAreSigned) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 100);
  push_word(bytes, wfdb::kSub, 0xFF);  // -1 as a signed char
  push_word(bytes, wfdb::kNum, 0xFE);  // -2 as a signed char
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 1u);
  EXPECT_EQ(annotations[0].subtype, -1);
  EXPECT_EQ(annotations[0].num, -2);
}

TEST(AnnotationDecoder, ChannelAndNumCarryOverToLaterAnnotations) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 100);
  push_word(bytes, wfdb::kChn, 1);  // channel 1
  push_word(bytes, wfdb::kNum, 7);  // num 7
  push_word(bytes, 1, 100);         // inherits channel 1 and num 7
  push_word(bytes, 1, 100);
  push_word(bytes, wfdb::kChn, 0);  // back to channel 0
  push_word(bytes, 1, 100);         // inherits channel 0, still num 7
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 4u);
  EXPECT_EQ(annotations[0].channel, 1);
  EXPECT_EQ(annotations[1].channel, 1);
  EXPECT_EQ(annotations[2].channel, 0);
  EXPECT_EQ(annotations[3].channel, 0);
  for (const wfdb::Annotation& annotation : annotations) {
    EXPECT_EQ(annotation.num, 7);
  }
}

TEST(AnnotationDecoder, ChannelIsUnsignedAndReachesTwoFiftyFive) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 100);
  push_word(bytes, wfdb::kChn, 0xFF);
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 1u);
  EXPECT_EQ(annotations[0].channel, 255);
}

TEST(AnnotationDecoder, ReadsAnEvenLengthAuxiliaryString) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 28, 18);          // + rhythm change
  push_word(bytes, wfdb::kAux, 4);   // four bytes of payload
  push_raw_word(bytes, 0x4241);      // "AB"
  push_raw_word(bytes, 0x4443);      // "CD"
  push_word(bytes, 1, 50);
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 2u);
  EXPECT_EQ(annotations[0].aux, "ABCD");
  EXPECT_EQ(annotations[1].sample, 68);  // Alignment survived the payload.
  EXPECT_TRUE(annotations[1].aux.empty());
}

TEST(AnnotationDecoder, DropsThePadByteOfAnOddLengthAuxiliaryString) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 28, 18);
  push_word(bytes, wfdb::kAux, 3);  // three bytes, padded to four
  push_raw_word(bytes, 0x4241);     // "AB"
  push_raw_word(bytes, 0x0043);     // "C" plus a NUL pad byte
  push_word(bytes, 1, 50);
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 2u);
  EXPECT_EQ(annotations[0].aux, "ABC");  // The pad byte is not part of the string.
  EXPECT_EQ(annotations[1].sample, 68);
}

// This is the trap that a naive decoder falls into. Record 100 opens with a
// rhythm-change annotation whose auxiliary string is "(N" followed by a NUL,
// which is padded to four bytes. The second payload word is therefore 0x0000 --
// bit for bit identical to the end-of-file marker. A decoder that scans for a
// zero word instead of consuming the payload by its declared byte count stops
// after the very first annotation.
TEST(AnnotationDecoder, AuxiliaryPayloadMayContainAZeroWord) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 28, 18);         // + at sample 18
  push_word(bytes, wfdb::kAux, 3);  // "(N" and a NUL
  push_raw_word(bytes, 0x4E28);     // "(N"
  push_raw_word(bytes, 0x0000);     // NUL plus pad: looks exactly like EOF
  push_word(bytes, 1, 59);          // N at sample 77
  push_word(bytes, 1, 293);         // N at sample 370
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 3u) << "the zero word inside the auxiliary "
                                      "payload was mistaken for end of file";
  EXPECT_EQ(annotations[0].sample, 18);
  EXPECT_EQ(annotations[0].aux, std::string("(N\0", 3));
  EXPECT_EQ(wfdb::aux_text(annotations[0]), "(N");  // Trailing NUL trimmed.
  EXPECT_EQ(annotations[1].sample, 77);
  EXPECT_EQ(annotations[2].sample, 370);
}

TEST(AnnotationDecoder, SkipCarriesALargePositiveInterval) {
  // SKIP stores a signed 32-bit interval, most significant word first.
  const std::int64_t interval = 100000;
  std::vector<std::uint8_t> bytes;
  push_word(bytes, wfdb::kSkip, 0);
  push_raw_word(bytes, static_cast<std::uint16_t>((interval >> 16) & 0xFFFF));
  push_raw_word(bytes, static_cast<std::uint16_t>(interval & 0xFFFF));
  push_word(bytes, 1, 0);  // The annotation the SKIP belongs to.
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 1u);
  EXPECT_EQ(annotations[0].sample, interval);
  EXPECT_EQ(annotations[0].symbol(), "N");
}

TEST(AnnotationDecoder, SkipIntervalIsAddedToTheTenBitField) {
  const std::int64_t interval = 70000;
  std::vector<std::uint8_t> bytes;
  push_word(bytes, wfdb::kSkip, 0);
  push_raw_word(bytes, static_cast<std::uint16_t>((interval >> 16) & 0xFFFF));
  push_raw_word(bytes, static_cast<std::uint16_t>(interval & 0xFFFF));
  push_word(bytes, 1, 500);  // Both contributions count.
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 1u);
  EXPECT_EQ(annotations[0].sample, interval + 500);
}

TEST(AnnotationDecoder, SkipIntervalIsSigned) {
  // A negative SKIP moves the annotation time backwards, which is how the
  // format supports annotators that emit out-of-order events.
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 1000);  // N at sample 1000
  push_word(bytes, wfdb::kSkip, 0);
  const std::uint32_t negative = static_cast<std::uint32_t>(-500);
  push_raw_word(bytes, static_cast<std::uint16_t>((negative >> 16) & 0xFFFF));
  push_raw_word(bytes, static_cast<std::uint16_t>(negative & 0xFFFF));
  push_word(bytes, 1, 0);  // N at sample 500
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 2u);
  EXPECT_EQ(annotations[0].sample, 1000);
  EXPECT_EQ(annotations[1].sample, 500);
}

TEST(AnnotationDecoder, ConsecutiveSkipsAccumulate) {
  std::vector<std::uint8_t> bytes;
  for (int i = 0; i < 2; ++i) {
    push_word(bytes, wfdb::kSkip, 0);
    push_raw_word(bytes, 0x0001);  // high word: 1 << 16 = 65536
    push_raw_word(bytes, 0x0000);
  }
  push_word(bytes, 1, 0);
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 1u);
  EXPECT_EQ(annotations[0].sample, 131072);
}

TEST(AnnotationDecoder, AllModifiersMayAttachToASingleAnnotation) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 5, 200);
  push_word(bytes, wfdb::kSub, 2);
  push_word(bytes, wfdb::kChn, 1);
  push_word(bytes, wfdb::kNum, 3);
  push_word(bytes, wfdb::kAux, 2);
  push_raw_word(bytes, 0x4241);  // "AB"
  push_terminator(bytes);

  const std::vector<wfdb::Annotation> annotations = wfdb::decode_annotations(bytes);
  ASSERT_EQ(annotations.size(), 1u);
  EXPECT_EQ(annotations[0].sample, 200);
  EXPECT_EQ(annotations[0].subtype, 2);
  EXPECT_EQ(annotations[0].channel, 1);
  EXPECT_EQ(annotations[0].num, 3);
  EXPECT_EQ(annotations[0].aux, "AB");
}

// ---------------------------------------------------------------------------
// Decoder: malformed input
// ---------------------------------------------------------------------------

TEST(AnnotationDecoder, RejectsAnOddNumberOfBytes) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 1, 100);
  bytes.push_back(0x00);  // Stray byte.
  EXPECT_THROW(wfdb::decode_annotations(bytes), wfdb::FormatError);
}

TEST(AnnotationDecoder, RejectsATruncatedSkipInterval) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, wfdb::kSkip, 0);
  push_raw_word(bytes, 0x0000);  // Only one of the two interval words.
  EXPECT_THROW(wfdb::decode_annotations(bytes), wfdb::FormatError);
}

TEST(AnnotationDecoder, RejectsASkipWithNoAnnotationAfterIt) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, wfdb::kSkip, 0);
  push_raw_word(bytes, 0x0000);
  push_raw_word(bytes, 0x0064);
  // File ends here: the SKIP has no annotation to modify.
  EXPECT_THROW(wfdb::decode_annotations(bytes), wfdb::FormatError);
}

TEST(AnnotationDecoder, RejectsAnAuxiliaryStringRunningPastEndOfFile) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, 28, 10);
  push_word(bytes, wfdb::kAux, 40);  // Claims forty bytes.
  push_raw_word(bytes, 0x4241);      // Supplies two.
  EXPECT_THROW(wfdb::decode_annotations(bytes), wfdb::FormatError);
}

TEST(AnnotationDecoder, RejectsAModifierWhereAnAnnotationWasExpected) {
  std::vector<std::uint8_t> bytes;
  push_word(bytes, wfdb::kSub, 1);  // A modifier with nothing to modify.
  push_terminator(bytes);
  EXPECT_THROW(wfdb::decode_annotations(bytes), wfdb::FormatError);
}

TEST(AnnotationReader, ThrowsWhenTheFileIsMissing) {
  EXPECT_THROW(wfdb::read_annotation_file(record_path("no_such_record.atr")),
               wfdb::FormatError);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TEST(AnnotationHelpers, ConvertsSampleNumbersToSeconds) {
  wfdb::Annotation annotation;
  annotation.sample = 360;
  EXPECT_DOUBLE_EQ(annotation.time_seconds(kMitBihSamplingFrequency), 1.0);
  annotation.sample = 180;
  EXPECT_DOUBLE_EQ(annotation.time_seconds(kMitBihSamplingFrequency), 0.5);
  EXPECT_THROW(annotation.time_seconds(0.0), wfdb::FormatError);
}

TEST(AnnotationHelpers, RrIntervalsUseBeatsOnly) {
  std::vector<wfdb::Annotation> annotations(4);
  annotations[0].code = 28;  // + rhythm change, must be ignored
  annotations[0].sample = 10;
  annotations[1].code = 1;  // N
  annotations[1].sample = 100;
  annotations[2].code = 1;  // N
  annotations[2].sample = 400;
  annotations[3].code = 1;  // N
  annotations[3].sample = 700;

  EXPECT_EQ(wfdb::beat_samples(annotations).size(), 3u);
  const std::vector<std::int64_t> intervals = wfdb::rr_intervals(annotations);
  ASSERT_EQ(intervals.size(), 2u);
  EXPECT_EQ(intervals[0], 300);
  EXPECT_EQ(intervals[1], 300);
  // 300 samples at 360 Hz is 0.8333 s, which is 72 bpm.
  EXPECT_NEAR(wfdb::mean_heart_rate_bpm(annotations, kMitBihSamplingFrequency),
              72.0, 1e-9);
}

TEST(AnnotationHelpers, RrIntervalsAreEmptyBelowTwoBeats) {
  std::vector<wfdb::Annotation> annotations(1);
  annotations[0].code = 1;
  annotations[0].sample = 100;
  EXPECT_TRUE(wfdb::rr_intervals(annotations).empty());
  EXPECT_DOUBLE_EQ(wfdb::mean_heart_rate_bpm(annotations, kMitBihSamplingFrequency),
                   0.0);
  EXPECT_TRUE(wfdb::rr_intervals({}).empty());
}

// ---------------------------------------------------------------------------
// MIT-BIH record 100
// ---------------------------------------------------------------------------

class Record100Annotations : public ::testing::Test {
 protected:
  void SetUp() override {
    const std::string path = record_path("100.atr");
    if (!file_exists(path)) {
      GTEST_SKIP() << "MIT-BIH record 100 is not present at " << path;
    }
    annotations_ = wfdb::read_annotation_file(path);
  }

  std::vector<wfdb::Annotation> annotations_;
};

TEST_F(Record100Annotations, ReadsEveryAnnotation) {
  // The full reference annotation set for record 100.
  EXPECT_EQ(annotations_.size(), 2274u);
}

TEST_F(Record100Annotations, OpensWithTheRhythmChangeAnnotation) {
  ASSERT_FALSE(annotations_.empty());
  EXPECT_EQ(annotations_[0].sample, 18);
  EXPECT_EQ(annotations_[0].symbol(), "+");
  EXPECT_FALSE(annotations_[0].is_beat());
  // Normal sinus rhythm, stored with a trailing NUL.
  EXPECT_EQ(wfdb::aux_text(annotations_[0]), "(N");
  EXPECT_EQ(annotations_[0].aux.size(), 3u);
}

TEST_F(Record100Annotations, MatchesTheKnownBeatCounts) {
  const wfdb::AnnotationSummary summary = wfdb::summarize(annotations_);
  EXPECT_EQ(summary.total, 2274u);
  EXPECT_EQ(summary.beats, 2273u);
  EXPECT_EQ(summary.count_of_code(1), 2239u);  // N
  EXPECT_EQ(summary.count_of_code(8), 33u);    // A
  EXPECT_EQ(summary.count_of_code(5), 1u);     // V
  EXPECT_EQ(summary.count_of_code(28), 1u);    // +
  EXPECT_EQ(summary.code_counts.size(), 4u);   // No other codes appear.
  EXPECT_EQ(summary.count_of_code(2), 0u);     // Absent codes report zero.
  EXPECT_EQ(summary.last_sample, 649991);
}

TEST_F(Record100Annotations, GroupsBeatsIntoAamiClasses) {
  const wfdb::AnnotationSummary summary = wfdb::summarize(annotations_);
  EXPECT_EQ(summary.count_of_class(wfdb::AamiClass::Normal), 2239u);
  EXPECT_EQ(summary.count_of_class(wfdb::AamiClass::Supraventricular), 33u);
  EXPECT_EQ(summary.count_of_class(wfdb::AamiClass::Ventricular), 1u);
  EXPECT_EQ(summary.count_of_class(wfdb::AamiClass::Fusion), 0u);
  EXPECT_EQ(summary.count_of_class(wfdb::AamiClass::Unknown), 0u);
  EXPECT_EQ(summary.count_of_class(wfdb::AamiClass::NotABeat), 1u);
}

TEST_F(Record100Annotations, LocatesTheSingleVentricularBeat) {
  int found = 0;
  for (const wfdb::Annotation& annotation : annotations_) {
    if (annotation.code == 5) {
      ++found;
      EXPECT_EQ(annotation.sample, 546792);
      EXPECT_EQ(annotation.subtype, 1);  // The only nonzero subtype in the file.
      EXPECT_EQ(annotation.aami_class(), wfdb::AamiClass::Ventricular);
    }
  }
  EXPECT_EQ(found, 1);
}

TEST_F(Record100Annotations, CarriesChannelAndNumAsZeroThroughout) {
  for (const wfdb::Annotation& annotation : annotations_) {
    EXPECT_EQ(annotation.channel, 0);
    EXPECT_EQ(annotation.num, 0);
  }
}

TEST_F(Record100Annotations, SubtypeIsZeroExceptOnTheVentricularBeat) {
  std::size_t nonzero = 0;
  for (const wfdb::Annotation& annotation : annotations_) {
    if (annotation.subtype != 0) {
      ++nonzero;
    }
  }
  EXPECT_EQ(nonzero, 1u);
}

TEST_F(Record100Annotations, SampleNumbersIncreaseMonotonically) {
  for (std::size_t i = 1; i < annotations_.size(); ++i) {
    EXPECT_GT(annotations_[i].sample, annotations_[i - 1].sample)
        << "annotation " << i << " is not after its predecessor";
  }
}

TEST_F(Record100Annotations, AnnotationsStayInsideTheRecord) {
  // Record 100 declares 650000 samples per signal in its header.
  for (const wfdb::Annotation& annotation : annotations_) {
    EXPECT_GE(annotation.sample, 0);
    EXPECT_LT(annotation.sample, 650000);
  }
}

TEST_F(Record100Annotations, ReportsAPhysiologicallyPlausibleHeartRate) {
  const std::vector<std::int64_t> intervals = wfdb::rr_intervals(annotations_);
  ASSERT_EQ(intervals.size(), 2272u);
  EXPECT_EQ(*std::min_element(intervals.begin(), intervals.end()), 188);
  EXPECT_EQ(*std::max_element(intervals.begin(), intervals.end()), 407);
  // 2272 intervals spanning samples 77 to 649991 at 360 Hz.
  EXPECT_NEAR(wfdb::mean_heart_rate_bpm(annotations_, kMitBihSamplingFrequency),
              75.5103, 1e-4);
}

// The decisive test: every field of every annotation, compared against output
// captured from the reference WFDB implementation.
TEST_F(Record100Annotations, MatchesTheReferenceImplementationFieldByField) {
  const std::string path = fixture_path("100.atr.reference.csv");
  const std::vector<ReferenceRow> reference = read_reference(path);
  if (reference.empty()) {
    GTEST_SKIP() << "reference fixture is missing or empty: " << path;
  }

  ASSERT_EQ(annotations_.size(), reference.size())
      << "decoded a different number of annotations than the reference";

  for (std::size_t i = 0; i < reference.size(); ++i) {
    const wfdb::Annotation& mine = annotations_[i];
    const ReferenceRow& theirs = reference[i];
    ASSERT_EQ(mine.sample, theirs.sample) << "sample mismatch at index " << i;
    ASSERT_EQ(mine.code, theirs.code) << "code mismatch at index " << i;
    ASSERT_EQ(mine.subtype, theirs.subtype) << "subtype mismatch at index " << i;
    ASSERT_EQ(mine.channel, theirs.chan) << "channel mismatch at index " << i;
    ASSERT_EQ(mine.num, theirs.num) << "num mismatch at index " << i;
    ASSERT_EQ(mine.aux, theirs.aux) << "aux mismatch at index " << i;
  }
}
