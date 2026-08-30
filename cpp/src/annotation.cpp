#include "wfdb/annotation.hpp"

#include <array>
#include <fstream>
#include <ios>
#include <utility>

namespace wfdb {
namespace {

// ---------------------------------------------------------------------------
// Annotation code table
// ---------------------------------------------------------------------------

struct CodeEntry {
  const char* symbol;
  const char* description;
};

// Indexed by annotation type code. Entries with an empty symbol have no
// assigned meaning; they are legal but carry no predefined interpretation.
constexpr std::array<CodeEntry, 50> kCodeTable = {{
    /*  0 */ {"", "Not an actual annotation"},
    /*  1 */ {"N", "Normal beat"},
    /*  2 */ {"L", "Left bundle branch block beat"},
    /*  3 */ {"R", "Right bundle branch block beat"},
    /*  4 */ {"a", "Aberrated atrial premature beat"},
    /*  5 */ {"V", "Premature ventricular contraction"},
    /*  6 */ {"F", "Fusion of ventricular and normal beat"},
    /*  7 */ {"J", "Nodal (junctional) premature beat"},
    /*  8 */ {"A", "Atrial premature contraction"},
    /*  9 */ {"S", "Premature or ectopic supraventricular beat"},
    /* 10 */ {"E", "Ventricular escape beat"},
    /* 11 */ {"j", "Nodal (junctional) escape beat"},
    /* 12 */ {"/", "Paced beat"},
    /* 13 */ {"Q", "Unclassifiable beat"},
    /* 14 */ {"~", "Signal quality change"},
    /* 15 */ {"", "Undefined annotation code"},
    /* 16 */ {"|", "Isolated QRS-like artifact"},
    /* 17 */ {"", "Undefined annotation code"},
    /* 18 */ {"s", "ST change"},
    /* 19 */ {"T", "T-wave change"},
    /* 20 */ {"*", "Systole"},
    /* 21 */ {"D", "Diastole"},
    /* 22 */ {"\"", "Comment annotation"},
    /* 23 */ {"=", "Measurement annotation"},
    /* 24 */ {"p", "P-wave peak"},
    /* 25 */ {"B", "Left or right bundle branch block"},
    /* 26 */ {"^", "Non-conducted pacer spike"},
    /* 27 */ {"t", "T-wave peak"},
    /* 28 */ {"+", "Rhythm change"},
    /* 29 */ {"u", "U-wave peak"},
    /* 30 */ {"?", "Learning"},
    /* 31 */ {"!", "Ventricular flutter wave"},
    /* 32 */ {"[", "Start of ventricular flutter/fibrillation"},
    /* 33 */ {"]", "End of ventricular flutter/fibrillation"},
    /* 34 */ {"e", "Atrial escape beat"},
    /* 35 */ {"n", "Supraventricular escape beat"},
    /* 36 */ {"@", "Link to external data"},
    /* 37 */ {"x", "Non-conducted P-wave (blocked APB)"},
    /* 38 */ {"f", "Fusion of paced and normal beat"},
    /* 39 */ {"(", "Waveform onset"},
    /* 40 */ {")", "Waveform end"},
    /* 41 */ {"r", "R-on-T premature ventricular contraction"},
    /* 42 */ {"", "Undefined annotation code"},
    /* 43 */ {"", "Undefined annotation code"},
    /* 44 */ {"", "Undefined annotation code"},
    /* 45 */ {"", "Undefined annotation code"},
    /* 46 */ {"", "Undefined annotation code"},
    /* 47 */ {"", "Undefined annotation code"},
    /* 48 */ {"", "Undefined annotation code"},
    /* 49 */ {"", "Undefined annotation code"},
}};

bool in_table(int code) {
  return code >= 0 && static_cast<std::size_t>(code) < kCodeTable.size();
}

// Little-endian 16-bit word at the given word index.
std::uint32_t word_at(const std::vector<std::uint8_t>& bytes, std::size_t index) {
  const std::size_t offset = index * 2;
  return static_cast<std::uint32_t>(bytes[offset]) |
         (static_cast<std::uint32_t>(bytes[offset + 1]) << 8);
}

// Six most significant bits of the word: the annotation type code.
int code_at(const std::vector<std::uint8_t>& bytes, std::size_t index) {
  return static_cast<int>(bytes[index * 2 + 1] >> 2);
}

// Ten least significant bits of the word: the sample interval, or, for a
// modifier word, the field value or byte count.
int interval_at(const std::vector<std::uint8_t>& bytes, std::size_t index) {
  const std::size_t offset = index * 2;
  return static_cast<int>(bytes[offset]) +
         256 * static_cast<int>(bytes[offset + 1] & 0x03);
}

// Low byte of the word, reinterpreted as a signed char. SUB and NUM both store
// signed values there.
int signed_low_byte(const std::vector<std::uint8_t>& bytes, std::size_t index) {
  return static_cast<int>(static_cast<std::int8_t>(bytes[index * 2]));
}

}  // namespace

// ---------------------------------------------------------------------------
// Code queries
// ---------------------------------------------------------------------------

std::string annotation_symbol(int code) {
  if (!in_table(code)) {
    return std::string();
  }
  return std::string(kCodeTable[static_cast<std::size_t>(code)].symbol);
}

std::string annotation_description(int code) {
  if (!in_table(code)) {
    return std::string("Undefined annotation code");
  }
  return std::string(kCodeTable[static_cast<std::size_t>(code)].description);
}

bool is_beat_code(int code) {
  switch (code) {
    case 1:   // N
    case 2:   // L
    case 3:   // R
    case 4:   // a
    case 5:   // V
    case 6:   // F
    case 7:   // J
    case 8:   // A
    case 9:   // S
    case 10:  // E
    case 11:  // j
    case 12:  // /
    case 13:  // Q
    case 25:  // B
    case 30:  // ?
    case 31:  // !
    case 34:  // e
    case 35:  // n
    case 38:  // f
    case 41:  // r
      return true;
    default:
      return false;
  }
}

AamiClass aami_class_of(int code) {
  switch (code) {
    // N: normal and bundle branch block beats, plus the escape beats, which
    // the classification literature groups here.
    case 1:   // N
    case 2:   // L
    case 3:   // R
    case 25:  // B
    case 34:  // e
    case 11:  // j
      return AamiClass::Normal;

    // S: supraventricular ectopic beats.
    case 8:   // A
    case 4:   // a
    case 7:   // J
    case 9:   // S
    case 35:  // n
      return AamiClass::Supraventricular;

    // V: ventricular ectopic beats, including R-on-T.
    case 5:   // V
    case 10:  // E
    case 41:  // r
      return AamiClass::Ventricular;

    // F: fusion of a ventricular and a normal beat.
    case 6:  // F
      return AamiClass::Fusion;

    // Q: paced, paced fusion, unclassifiable, and the two beat codes EC57
    // leaves unassigned.
    case 12:  // /
    case 38:  // f
    case 13:  // Q
    case 30:  // ?
    case 31:  // !
      return AamiClass::Unknown;

    default:
      return AamiClass::NotABeat;
  }
}

const char* aami_class_symbol(AamiClass cls) {
  switch (cls) {
    case AamiClass::Normal:
      return "N";
    case AamiClass::Supraventricular:
      return "S";
    case AamiClass::Ventricular:
      return "V";
    case AamiClass::Fusion:
      return "F";
    case AamiClass::Unknown:
      return "Q";
    case AamiClass::NotABeat:
      break;
  }
  return "-";
}

const char* aami_class_name(AamiClass cls) {
  switch (cls) {
    case AamiClass::Normal:
      return "Normal";
    case AamiClass::Supraventricular:
      return "Supraventricular ectopic";
    case AamiClass::Ventricular:
      return "Ventricular ectopic";
    case AamiClass::Fusion:
      return "Fusion";
    case AamiClass::Unknown:
      return "Unknown or paced";
    case AamiClass::NotABeat:
      break;
  }
  return "Not a beat";
}

double Annotation::time_seconds(double sampling_frequency) const {
  if (sampling_frequency <= 0.0) {
    throw FormatError("sampling frequency must be positive");
  }
  return static_cast<double>(sample) / sampling_frequency;
}

std::string aux_text(const Annotation& annotation) {
  std::string text = annotation.aux;
  while (!text.empty() && text.back() == '\0') {
    text.pop_back();
  }
  return text;
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

std::vector<Annotation> decode_annotations(const std::vector<std::uint8_t>& bytes) {
  if (bytes.size() % 2 != 0) {
    throw FormatError(
        "annotation file length is not a multiple of two bytes; every "
        "annotation word occupies exactly two bytes");
  }

  const std::size_t num_words = bytes.size() / 2;
  std::vector<Annotation> annotations;

  std::int64_t sample = 0;  // Running absolute sample number.
  int channel = 0;          // CHN persists until changed.
  int num = 0;              // NUM persists until changed.
  std::size_t w = 0;        // Current word index.

  while (w < num_words) {
    // A zero word terminates the file. Note that this test must happen only
    // here, at the start of an annotation: a zero word can legitimately occur
    // inside an auxiliary string, which is why the auxiliary payload has to be
    // consumed by byte count rather than scanned for a terminator.
    if (word_at(bytes, w) == 0) {
      break;
    }

    // SKIP carries an interval too large for the ten-bit field. The two words
    // that follow hold a signed 32-bit interval, most significant word first.
    // Several SKIPs may accumulate before the annotation itself.
    std::int64_t interval = 0;
    while (w < num_words && code_at(bytes, w) == kSkip) {
      if (w + 2 >= num_words) {
        throw FormatError(
            "annotation file ends inside a SKIP interval; expected two words "
            "of interval data after the SKIP marker");
      }
      const std::uint32_t high = word_at(bytes, w + 1);
      const std::uint32_t low = word_at(bytes, w + 2);
      const std::uint32_t raw = (high << 16) | low;
      interval += static_cast<std::int64_t>(static_cast<std::int32_t>(raw));
      w += 3;
    }

    if (w >= num_words) {
      throw FormatError(
          "annotation file ends after a SKIP interval with no annotation "
          "following it");
    }

    const int code = code_at(bytes, w);
    if (code == 0) {
      break;  // Terminator reached after one or more SKIPs.
    }
    if (code > kMaxCode) {
      throw FormatError(
          "found a modifier word where an annotation was expected; modifier "
          "words may only follow an annotation");
    }

    interval += interval_at(bytes, w);
    ++w;

    sample += interval;

    Annotation annotation;
    annotation.sample = sample;
    annotation.code = code;
    annotation.subtype = 0;    // SUB is per-annotation and defaults to zero.
    annotation.channel = channel;  // CHN and NUM carry over.
    annotation.num = num;

    // Consume any modifier words attached to this annotation.
    while (w < num_words && code_at(bytes, w) > kSkip) {
      switch (code_at(bytes, w)) {
        case kNum:
          num = signed_low_byte(bytes, w);
          annotation.num = num;
          ++w;
          break;
        case kSub:
          annotation.subtype = signed_low_byte(bytes, w);
          ++w;
          break;
        case kChn:
          channel = static_cast<int>(bytes[w * 2]);
          annotation.channel = channel;
          ++w;
          break;
        case kAux: {
          // The low ten bits hold the byte count. The payload is padded with a
          // NUL to an even number of bytes so that the next annotation stays
          // word-aligned.
          const std::size_t length = static_cast<std::size_t>(interval_at(bytes, w));
          const std::size_t payload_words = (length + 1) / 2;
          if (w + 1 + payload_words > num_words) {
            throw FormatError(
                "annotation file ends inside an auxiliary string; the declared "
                "byte count runs past the end of the file");
          }
          annotation.aux.assign(
              reinterpret_cast<const char*>(bytes.data() + (w + 1) * 2), length);
          w += 1 + payload_words;
          break;
        }
        default:
          // Unreachable: the loop condition admits only 60 through 63.
          throw FormatError("unrecognised annotation modifier word");
      }
    }

    annotations.push_back(std::move(annotation));
  }

  return annotations;
}

std::vector<Annotation> read_annotation_file(const std::string& path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) {
    throw FormatError("cannot open annotation file: " + path);
  }

  std::vector<std::uint8_t> bytes;
  stream.seekg(0, std::ios::end);
  const std::streamoff size = stream.tellg();
  if (size < 0) {
    throw FormatError("cannot determine the size of: " + path);
  }
  stream.seekg(0, std::ios::beg);

  bytes.resize(static_cast<std::size_t>(size));
  if (!bytes.empty()) {
    stream.read(reinterpret_cast<char*>(bytes.data()),
                static_cast<std::streamsize>(bytes.size()));
    if (!stream) {
      throw FormatError("failed while reading annotation file: " + path);
    }
  }

  return decode_annotations(bytes);
}

// ---------------------------------------------------------------------------
// Summaries
// ---------------------------------------------------------------------------

std::size_t AnnotationSummary::count_of_code(int code) const {
  const auto found = code_counts.find(code);
  return found == code_counts.end() ? 0u : found->second;
}

std::size_t AnnotationSummary::count_of_class(AamiClass cls) const {
  const auto found = class_counts.find(cls);
  return found == class_counts.end() ? 0u : found->second;
}

AnnotationSummary summarize(const std::vector<Annotation>& annotations) {
  AnnotationSummary summary;
  summary.total = annotations.size();
  for (const Annotation& annotation : annotations) {
    ++summary.code_counts[annotation.code];
    const AamiClass cls = annotation.aami_class();
    ++summary.class_counts[cls];
    if (annotation.is_beat()) {
      ++summary.beats;
    }
  }
  if (!annotations.empty()) {
    summary.last_sample = annotations.back().sample;
  }
  return summary;
}

std::vector<std::int64_t> beat_samples(const std::vector<Annotation>& annotations) {
  std::vector<std::int64_t> samples;
  for (const Annotation& annotation : annotations) {
    if (annotation.is_beat()) {
      samples.push_back(annotation.sample);
    }
  }
  return samples;
}

std::vector<std::int64_t> rr_intervals(const std::vector<Annotation>& annotations) {
  const std::vector<std::int64_t> samples = beat_samples(annotations);
  std::vector<std::int64_t> intervals;
  if (samples.size() < 2) {
    return intervals;
  }
  intervals.reserve(samples.size() - 1);
  for (std::size_t i = 1; i < samples.size(); ++i) {
    intervals.push_back(samples[i] - samples[i - 1]);
  }
  return intervals;
}

double mean_heart_rate_bpm(const std::vector<Annotation>& annotations,
                           double sampling_frequency) {
  if (sampling_frequency <= 0.0) {
    throw FormatError("sampling frequency must be positive");
  }
  const std::vector<std::int64_t> intervals = rr_intervals(annotations);
  if (intervals.empty()) {
    return 0.0;
  }
  std::int64_t total = 0;
  for (const std::int64_t interval : intervals) {
    total += interval;
  }
  const double mean_samples =
      static_cast<double>(total) / static_cast<double>(intervals.size());
  if (mean_samples <= 0.0) {
    return 0.0;
  }
  return 60.0 * sampling_frequency / mean_samples;
}

}  // namespace wfdb
