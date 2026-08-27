// WFDB header (.hea) parsing for the MIT-BIH Arrhythmia Database.
//
// Part of the ecg-arrhythmia-detection-pipeline portfolio project.
// Implements the subset of the WFDB header specification required by this
// pipeline: single-segment records with one shared signal file.

#ifndef WFDB_HEADER_HPP
#define WFDB_HEADER_HPP

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace wfdb {

// Thrown when a header or signal file does not conform to the expected format.
class FormatError : public std::runtime_error {
 public:
  explicit FormatError(const std::string& message)
      : std::runtime_error(message) {}
};

// Description of a single signal (channel) declared in a header file.
struct SignalSpec {
  std::string file_name;        // Signal file holding the samples.
  int format = 0;               // WFDB storage format code (212 here).
  double adc_gain = 200.0;      // ADC units per physical unit.
  std::string units = "mV";     // Physical units of the calibrated signal.
  int baseline = 0;             // Raw value corresponding to zero physical.
  int adc_resolution = 12;      // Significant bits per sample.
  int adc_zero = 0;             // Raw value at midrange of the ADC.
  int initial_value = 0;        // Declared value of the first sample.
  int checksum = 0;             // Declared 16-bit checksum of all samples.
  int block_size = 0;           // 0 means the file is not block-structured.
  std::string description;      // Free-text lead name, for example "MLII".

  // Converts a raw ADC value to physical units (millivolts for MIT-BIH).
  double to_physical(int raw_value) const {
    return (static_cast<double>(raw_value) - static_cast<double>(baseline)) /
           adc_gain;
  }
};

// Contents of a parsed single-segment WFDB header file.
struct Header {
  std::string record_name;
  int num_signals = 0;
  double sampling_frequency = 250.0;  // WFDB default when unspecified.
  std::int64_t num_samples_per_signal = 0;
  std::vector<SignalSpec> signals;
  std::vector<std::string> comments;

  double duration_seconds() const;
  const SignalSpec& signal(std::size_t index) const;
};

// Parses header text that has already been loaded into memory.
// Accepts both LF and CRLF line endings.
Header parse_header_text(const std::string& text);

// Reads and parses a .hea file from disk.
Header parse_header_file(const std::string& path);

}  // namespace wfdb

#endif  // WFDB_HEADER_HPP
