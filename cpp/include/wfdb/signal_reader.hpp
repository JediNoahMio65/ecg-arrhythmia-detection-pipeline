// WFDB format-212 signal decoding for the MIT-BIH Arrhythmia Database.
//
// Format 212 packs two 12-bit two's-complement samples into every three
// consecutive bytes. Given bytes b0, b1, b2:
//
//   sample A = b0 | ((b1 & 0x0F) << 8)     low nibble of the middle byte
//   sample B = b2 | ((b1 >> 4)   << 8)     high nibble of the middle byte
//
// Both 12-bit results are then sign-extended to a full integer. Samples are
// stored interleaved across channels: for a two-channel record, sample A of
// each triplet belongs to channel 0 and sample B to channel 1.

#ifndef WFDB_SIGNAL_READER_HPP
#define WFDB_SIGNAL_READER_HPP

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "wfdb/header.hpp"

namespace wfdb {

// A fully decoded record: its header plus one raw sample vector per signal.
struct Record {
  Header header;
  std::vector<std::vector<int>> samples;  // samples[channel][index], raw ADU.
};

// Number of bytes required to store sample_count format-212 samples.
// Two samples occupy three bytes, so an odd count is padded to a whole triplet.
std::size_t format212_byte_count(std::int64_t sample_count);

// Decodes sample_count interleaved samples from a format-212 byte buffer.
// Throws FormatError if the buffer is too small.
std::vector<int> decode_format212(const std::uint8_t* data,
                                  std::size_t byte_count,
                                  std::int64_t sample_count);

// Splits an interleaved sample stream into one vector per channel.
std::vector<std::vector<int>> deinterleave(const std::vector<int>& interleaved,
                                           int num_signals);

// Reads a format-212 signal file and returns one raw sample vector per signal.
std::vector<std::vector<int>> read_format212_file(
    const std::string& path, int num_signals,
    std::int64_t num_samples_per_signal);

// Reads record_name.hea and its signal file from the given directory.
Record read_record(const std::string& directory,
                   const std::string& record_name);

// The WFDB signal checksum: the sum of every sample, truncated to a signed
// 16-bit value. Each header line declares the expected checksum, which makes
// it a complete end-to-end verification of the decoder.
int checksum16(const std::vector<int>& samples);

// Converts raw ADC values to physical units using a signal's calibration.
std::vector<double> to_physical(const std::vector<int>& raw_samples,
                               const SignalSpec& spec);

// Confirms that every channel's first sample and checksum match the values
// declared in the header. Returns true on success; on failure, appends a
// human-readable explanation to report when report is not null.
bool verify_record(const Record& record, std::string* report);

}  // namespace wfdb

#endif  // WFDB_SIGNAL_READER_HPP
