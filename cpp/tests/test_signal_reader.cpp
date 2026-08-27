#include <gtest/gtest.h>

#include <cstdint>
#include <fstream>
#include <string>
#include <vector>

#include "wfdb/signal_reader.hpp"

namespace {

// Packs two 12-bit values into a format-212 byte triplet, mirroring the
// encoder used by the original WFDB tools. Used to build test fixtures whose
// expected output is known by construction.
void append_triplet(std::vector<std::uint8_t>& bytes, int first, int second) {
  const int a = first & 0x0FFF;
  const int b = second & 0x0FFF;
  bytes.push_back(static_cast<std::uint8_t>(a & 0xFF));
  bytes.push_back(static_cast<std::uint8_t>(((a >> 8) & 0x0F) |
                                            (((b >> 8) & 0x0F) << 4)));
  bytes.push_back(static_cast<std::uint8_t>(b & 0xFF));
}

bool file_exists(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  return static_cast<bool>(file);
}

const char* const kDataDirectory = WFDB_TEST_DATA_DIR;

TEST(Format212ByteCount, PadsOddSampleCountsToWholeTriplets) {
  EXPECT_EQ(wfdb::format212_byte_count(0), 0u);
  EXPECT_EQ(wfdb::format212_byte_count(1), 3u);
  EXPECT_EQ(wfdb::format212_byte_count(2), 3u);
  EXPECT_EQ(wfdb::format212_byte_count(3), 6u);
  EXPECT_EQ(wfdb::format212_byte_count(4), 6u);
  // Record 100: 650000 samples per signal across two signals.
  EXPECT_EQ(wfdb::format212_byte_count(1300000), 1950000u);
}

TEST(DecodeFormat212, DecodesTheFirstFrameOfRecord100) {
  std::vector<std::uint8_t> bytes;
  append_triplet(bytes, 995, 1011);

  const std::vector<int> samples =
      wfdb::decode_format212(bytes.data(), bytes.size(), 2);
  ASSERT_EQ(samples.size(), 2u);
  EXPECT_EQ(samples[0], 995);
  EXPECT_EQ(samples[1], 1011);
}

TEST(DecodeFormat212, SignExtendsNegativeAmplitudes) {
  std::vector<std::uint8_t> bytes;
  append_triplet(bytes, -1, -2048);   // 0xFFF and 0x800
  append_triplet(bytes, 2047, 0);     // largest positive and zero

  const std::vector<int> samples =
      wfdb::decode_format212(bytes.data(), bytes.size(), 4);
  ASSERT_EQ(samples.size(), 4u);
  EXPECT_EQ(samples[0], -1);
  EXPECT_EQ(samples[1], -2048);
  EXPECT_EQ(samples[2], 2047);
  EXPECT_EQ(samples[3], 0);
}

TEST(DecodeFormat212, CoversTheEntireTwelveBitRange) {
  std::vector<std::uint8_t> bytes;
  std::vector<int> expected;
  for (int value = -2048; value <= 2047; ++value) {
    expected.push_back(value);
  }
  for (std::size_t index = 0; index < expected.size(); index += 2) {
    append_triplet(bytes, expected[index], expected[index + 1]);
  }

  const std::vector<int> samples = wfdb::decode_format212(
      bytes.data(), bytes.size(),
      static_cast<std::int64_t>(expected.size()));
  EXPECT_EQ(samples, expected);
}

TEST(DecodeFormat212, IgnoresPaddingOfAnOddSampleCount) {
  std::vector<std::uint8_t> bytes;
  append_triplet(bytes, 42, 1234);  // second value is padding

  const std::vector<int> samples =
      wfdb::decode_format212(bytes.data(), bytes.size(), 1);
  ASSERT_EQ(samples.size(), 1u);
  EXPECT_EQ(samples[0], 42);
}

TEST(DecodeFormat212, ReturnsEmptyForZeroSamples) {
  const std::vector<std::uint8_t> bytes;
  EXPECT_TRUE(wfdb::decode_format212(bytes.data(), 0, 0).empty());
}

TEST(DecodeFormat212, RejectsATruncatedBuffer) {
  std::vector<std::uint8_t> bytes;
  append_triplet(bytes, 100, 200);
  bytes.pop_back();  // one byte short of a whole triplet
  EXPECT_THROW(wfdb::decode_format212(bytes.data(), bytes.size(), 2),
               wfdb::FormatError);
}

TEST(Deinterleave, SplitsFramesAcrossTwoChannels) {
  const std::vector<int> interleaved{1, 100, 2, 200, 3, 300};
  const std::vector<std::vector<int>> channels =
      wfdb::deinterleave(interleaved, 2);
  ASSERT_EQ(channels.size(), 2u);
  EXPECT_EQ(channels[0], std::vector<int>({1, 2, 3}));
  EXPECT_EQ(channels[1], std::vector<int>({100, 200, 300}));
}

TEST(Deinterleave, HandlesASingleChannel) {
  const std::vector<int> interleaved{5, 6, 7};
  const std::vector<std::vector<int>> channels =
      wfdb::deinterleave(interleaved, 1);
  ASSERT_EQ(channels.size(), 1u);
  EXPECT_EQ(channels[0], interleaved);
}

TEST(Deinterleave, RejectsAnIncompleteFinalFrame) {
  const std::vector<int> interleaved{1, 2, 3};
  EXPECT_THROW(wfdb::deinterleave(interleaved, 2), wfdb::FormatError);
}

TEST(Checksum16, SumsSamplesAndTruncatesToSignedSixteenBits) {
  EXPECT_EQ(wfdb::checksum16({}), 0);
  EXPECT_EQ(wfdb::checksum16({1, 2, 3}), 6);
  EXPECT_EQ(wfdb::checksum16({-5, 5}), 0);
  // 32768 wraps to the most negative 16-bit value.
  EXPECT_EQ(wfdb::checksum16({32767, 1}), -32768);
  EXPECT_EQ(wfdb::checksum16({32767, 2}), -32767);
}

TEST(ToPhysical, ConvertsAWholeChannelToMillivolts) {
  const wfdb::Header header = wfdb::parse_header_text(
      "100 1 360 2\n100.dat 212 200 11 1024 995 0 0 MLII\n");
  const std::vector<double> physical =
      wfdb::to_physical({1024, 1224, 824}, header.signal(0));
  ASSERT_EQ(physical.size(), 3u);
  EXPECT_NEAR(physical[0], 0.0, 1e-12);
  EXPECT_NEAR(physical[1], 1.0, 1e-12);
  EXPECT_NEAR(physical[2], -1.0, 1e-12);
}

// The tests below read the real MIT-BIH files. They are skipped rather than
// failed when the database has not been downloaded, so the suite still runs
// on a clean checkout.
class Record100Test : public ::testing::Test {
 protected:
  void SetUp() override {
    const std::string header_path =
        std::string(kDataDirectory) + "/100.hea";
    if (!file_exists(header_path)) {
      GTEST_SKIP() << "MIT-BIH record 100 not found in " << kDataDirectory
                   << "; see data/README.md for download instructions.";
    }
  }
};

TEST_F(Record100Test, DecodesTheDeclaredNumberOfSamples) {
  const wfdb::Record record = wfdb::read_record(kDataDirectory, "100");
  ASSERT_EQ(record.samples.size(), 2u);
  EXPECT_EQ(record.samples[0].size(), 650000u);
  EXPECT_EQ(record.samples[1].size(), 650000u);
}

TEST_F(Record100Test, FirstSampleOfEachChannelMatchesTheHeader) {
  const wfdb::Record record = wfdb::read_record(kDataDirectory, "100");
  EXPECT_EQ(record.samples[0].front(), 995);
  EXPECT_EQ(record.samples[1].front(), 1011);
  EXPECT_EQ(record.samples[0].front(), record.header.signal(0).initial_value);
  EXPECT_EQ(record.samples[1].front(), record.header.signal(1).initial_value);
}

// The strongest available check: the header's checksum depends on every one of
// the 650000 samples in a channel, so a match confirms the decoder reproduced
// the entire signal exactly.
TEST_F(Record100Test, ChecksumOfEveryChannelMatchesTheHeader) {
  const wfdb::Record record = wfdb::read_record(kDataDirectory, "100");
  EXPECT_EQ(wfdb::checksum16(record.samples[0]), -22131);
  EXPECT_EQ(wfdb::checksum16(record.samples[1]), 20052);
  for (std::size_t index = 0; index < record.samples.size(); ++index) {
    EXPECT_EQ(wfdb::checksum16(record.samples[index]),
              record.header.signal(index).checksum)
        << "channel " << index << " (" << record.header.signal(index).description
        << ")";
  }
}

TEST_F(Record100Test, VerifyRecordReportsSuccess) {
  const wfdb::Record record = wfdb::read_record(kDataDirectory, "100");
  std::string report;
  EXPECT_TRUE(wfdb::verify_record(record, &report)) << report;
  EXPECT_TRUE(report.empty()) << report;
}

TEST_F(Record100Test, AmplitudesStayWithinTheElevenBitAdcRange) {
  const wfdb::Record record = wfdb::read_record(kDataDirectory, "100");
  for (const std::vector<int>& channel : record.samples) {
    for (const int sample : channel) {
      ASSERT_GE(sample, 0);
      ASSERT_LE(sample, 2047);
    }
  }
}

TEST_F(Record100Test, ReportsPhysicalAmplitudesInAPlausibleEcgRange) {
  const wfdb::Record record = wfdb::read_record(kDataDirectory, "100");
  const std::vector<double> millivolts =
      wfdb::to_physical(record.samples[0], record.header.signal(0));
  double minimum = millivolts.front();
  double maximum = millivolts.front();
  for (const double value : millivolts) {
    minimum = value < minimum ? value : minimum;
    maximum = value > maximum ? value : maximum;
  }
  // A surface ECG lead stays well inside a few millivolts either way.
  EXPECT_GT(maximum, 0.5);
  EXPECT_LT(maximum, 5.0);
  EXPECT_LT(minimum, 0.0);
  EXPECT_GT(minimum, -5.0);
}

TEST_F(Record100Test, RejectsARequestForAMissingRecord) {
  EXPECT_THROW(wfdb::read_record(kDataDirectory, "999"), wfdb::FormatError);
}

}  // namespace
