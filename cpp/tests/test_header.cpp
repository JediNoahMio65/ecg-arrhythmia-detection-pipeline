#include <gtest/gtest.h>

#include <string>

#include "wfdb/header.hpp"

namespace {

// The header of MIT-BIH record 100, reproduced verbatim with the CRLF line
// endings used by the published database files.
const char* const kRecord100Header =
    "100 2 360 650000\r\n"
    "100.dat 212 200 11 1024 995 -22131 0 MLII\r\n"
    "100.dat 212 200 11 1024 1011 20052 0 V5\r\n"
    "# 69 M 1085 1629 x1\r\n"
    "# Aldomet, Inderal\r\n";

TEST(HeaderParse, ReadsRecordLineOfRecord100) {
  const wfdb::Header header = wfdb::parse_header_text(kRecord100Header);

  EXPECT_EQ(header.record_name, "100");
  EXPECT_EQ(header.num_signals, 2);
  EXPECT_DOUBLE_EQ(header.sampling_frequency, 360.0);
  EXPECT_EQ(header.num_samples_per_signal, 650000);
  ASSERT_EQ(header.signals.size(), 2u);
}

TEST(HeaderParse, ReadsBothSignalSpecificationsOfRecord100) {
  const wfdb::Header header = wfdb::parse_header_text(kRecord100Header);

  const wfdb::SignalSpec& mlii = header.signal(0);
  EXPECT_EQ(mlii.file_name, "100.dat");
  EXPECT_EQ(mlii.format, 212);
  EXPECT_DOUBLE_EQ(mlii.adc_gain, 200.0);
  EXPECT_EQ(mlii.adc_resolution, 11);
  EXPECT_EQ(mlii.adc_zero, 1024);
  EXPECT_EQ(mlii.initial_value, 995);
  EXPECT_EQ(mlii.checksum, -22131);
  EXPECT_EQ(mlii.block_size, 0);
  EXPECT_EQ(mlii.description, "MLII");

  const wfdb::SignalSpec& v5 = header.signal(1);
  EXPECT_EQ(v5.format, 212);
  EXPECT_EQ(v5.initial_value, 1011);
  EXPECT_EQ(v5.checksum, 20052);
  EXPECT_EQ(v5.description, "V5");
}

TEST(HeaderParse, DefaultsBaselineToAdcZeroWhenNotSpecified) {
  const wfdb::Header header = wfdb::parse_header_text(kRecord100Header);
  EXPECT_EQ(header.signal(0).baseline, 1024);
  EXPECT_EQ(header.signal(0).units, "mV");
}

TEST(HeaderParse, CollectsCommentLines) {
  const wfdb::Header header = wfdb::parse_header_text(kRecord100Header);
  ASSERT_EQ(header.comments.size(), 2u);
  EXPECT_EQ(header.comments[0], "69 M 1085 1629 x1");
  EXPECT_EQ(header.comments[1], "Aldomet, Inderal");
}

TEST(HeaderParse, ComputesRecordDuration) {
  const wfdb::Header header = wfdb::parse_header_text(kRecord100Header);
  // 650000 samples at 360 Hz is just over 30 minutes.
  EXPECT_NEAR(header.duration_seconds(), 1805.5555, 1e-3);
}

TEST(HeaderParse, HandlesLineFeedOnlyEndings) {
  const std::string unix_style =
      "100 2 360 650000\n100.dat 212 200 11 1024 995 -22131 0 MLII\n"
      "100.dat 212 200 11 1024 1011 20052 0 V5\n";
  const wfdb::Header header = wfdb::parse_header_text(unix_style);
  EXPECT_EQ(header.signal(0).description, "MLII");
  EXPECT_EQ(header.signal(1).description, "V5");
}

TEST(HeaderParse, ParsesExplicitBaselineAndUnits) {
  const std::string text =
      "test 1 250 100\ntest.dat 212 200(100)/mV 12 2048 5 5 0 I\n";
  const wfdb::Header header = wfdb::parse_header_text(text);
  EXPECT_DOUBLE_EQ(header.signal(0).adc_gain, 200.0);
  EXPECT_EQ(header.signal(0).baseline, 100);
  EXPECT_EQ(header.signal(0).units, "mV");
}

TEST(HeaderParse, TreatsZeroGainAsWfdbDefault) {
  const std::string text = "test 1 250 100\ntest.dat 212 0 12 2048 5 5 0 I\n";
  const wfdb::Header header = wfdb::parse_header_text(text);
  EXPECT_DOUBLE_EQ(header.signal(0).adc_gain, 200.0);
}

TEST(HeaderParse, KeepsMultiWordDescriptions) {
  const std::string text =
      "test 1 250 100\ntest.dat 212 200 12 2048 5 5 0 chest lead V2\n";
  const wfdb::Header header = wfdb::parse_header_text(text);
  EXPECT_EQ(header.signal(0).description, "chest lead V2");
}

TEST(HeaderParse, UsesWfdbDefaultFrequencyWhenOmitted) {
  const std::string text = "test 1\ntest.dat 212\n";
  const wfdb::Header header = wfdb::parse_header_text(text);
  EXPECT_DOUBLE_EQ(header.sampling_frequency, 250.0);
  EXPECT_EQ(header.num_samples_per_signal, 0);
}

TEST(HeaderParse, RejectsSignalCountMismatch) {
  const std::string text =
      "test 2 250 100\ntest.dat 212 200 12 2048 5 5 0 I\n";
  EXPECT_THROW(wfdb::parse_header_text(text), wfdb::FormatError);
}

TEST(HeaderParse, RejectsNonNumericSignalCount) {
  EXPECT_THROW(wfdb::parse_header_text("test two 250 100\n"),
               wfdb::FormatError);
}

TEST(HeaderParse, RejectsMultiSegmentRecords) {
  EXPECT_THROW(wfdb::parse_header_text("multi/3 2 360 650000\n"),
               wfdb::FormatError);
}

TEST(HeaderParse, RejectsUnsupportedFormatModifiers) {
  const std::string text =
      "test 1 250 100\ntest.dat 212x2 200 12 2048 5 5 0 I\n";
  EXPECT_THROW(wfdb::parse_header_text(text), wfdb::FormatError);
}

TEST(HeaderParse, RejectsEmptyHeader) {
  EXPECT_THROW(wfdb::parse_header_text(""), wfdb::FormatError);
}

TEST(HeaderParse, RejectsOutOfRangeSignalIndex) {
  const wfdb::Header header = wfdb::parse_header_text(kRecord100Header);
  EXPECT_THROW(header.signal(2), std::out_of_range);
}

TEST(SignalSpec, ConvertsRawValuesToMillivolts) {
  const wfdb::Header header = wfdb::parse_header_text(kRecord100Header);
  const wfdb::SignalSpec& mlii = header.signal(0);
  // (995 - 1024) / 200 = -0.145 mV
  EXPECT_NEAR(mlii.to_physical(995), -0.145, 1e-9);
  EXPECT_NEAR(mlii.to_physical(1024), 0.0, 1e-12);
  EXPECT_NEAR(mlii.to_physical(1224), 1.0, 1e-12);
}

}  // namespace
