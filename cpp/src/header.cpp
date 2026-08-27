#include "wfdb/header.hpp"

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <sstream>

namespace wfdb {
namespace {

// Removes a trailing carriage return so that CRLF files parse identically
// to LF files. MIT-BIH header files use CRLF endings.
void strip_carriage_return(std::string& line) {
  if (!line.empty() && line.back() == '\r') {
    line.pop_back();
  }
}

bool is_blank(const std::string& line) {
  for (char character : line) {
    if (std::isspace(static_cast<unsigned char>(character)) == 0) {
      return false;
    }
  }
  return true;
}

// Splits a line on whitespace into at most max_fields tokens. The final token
// keeps the remainder of the line, which preserves multi-word descriptions.
std::vector<std::string> split_fields(const std::string& line,
                                      std::size_t max_fields) {
  std::vector<std::string> fields;
  std::size_t position = 0;
  const std::size_t length = line.size();

  while (position < length) {
    while (position < length &&
           std::isspace(static_cast<unsigned char>(line[position])) != 0) {
      ++position;
    }
    if (position >= length) {
      break;
    }
    if (fields.size() + 1 == max_fields) {
      fields.push_back(line.substr(position));
      break;
    }
    const std::size_t start = position;
    while (position < length &&
           std::isspace(static_cast<unsigned char>(line[position])) == 0) {
      ++position;
    }
    fields.push_back(line.substr(start, position - start));
  }
  return fields;
}

// Parses a required integer field, reporting the field name on failure.
long long parse_integer(const std::string& token, const char* field_name) {
  if (token.empty()) {
    throw FormatError(std::string("missing integer field: ") + field_name);
  }
  std::size_t consumed = 0;
  long long value = 0;
  try {
    value = std::stoll(token, &consumed);
  } catch (const std::exception&) {
    throw FormatError(std::string("field '") + field_name +
                      "' is not an integer: " + token);
  }
  if (consumed != token.size()) {
    throw FormatError(std::string("field '") + field_name +
                      "' has trailing characters: " + token);
  }
  return value;
}

// Parses a leading number and reports how many characters it consumed. Used
// for compound header fields such as "360/1000" or "200(0)/mV".
double parse_leading_number(const std::string& token, std::size_t& consumed,
                           const char* field_name) {
  if (token.empty()) {
    throw FormatError(std::string("missing numeric field: ") + field_name);
  }
  double value = 0.0;
  try {
    value = std::stod(token, &consumed);
  } catch (const std::exception&) {
    throw FormatError(std::string("field '") + field_name +
                      "' is not numeric: " + token);
  }
  return value;
}

// Parses the sampling-frequency field, which may carry a counter frequency
// after a slash and a base counter value in parentheses. Only the sampling
// frequency itself is meaningful for this pipeline.
double parse_sampling_frequency(const std::string& token) {
  std::size_t consumed = 0;
  const double frequency =
      parse_leading_number(token, consumed, "sampling frequency");
  if (frequency <= 0.0) {
    throw FormatError("sampling frequency must be positive: " + token);
  }
  return frequency;
}

// Parses the format field. Sample-per-frame and skew modifiers are rejected
// rather than silently ignored, because misreading them would misalign every
// decoded sample.
int parse_format_field(const std::string& token) {
  std::size_t consumed = 0;
  const long long format = static_cast<long long>(
      parse_leading_number(token, consumed, "storage format"));
  if (consumed < token.size()) {
    throw FormatError(
        "unsupported format modifier (samples per frame, skew, or byte "
        "offset) in field: " +
        token);
  }
  return static_cast<int>(format);
}

// Parses the gain field, which has the general shape
// gain(baseline)/units. A gain of zero marks an uncalibrated signal, for
// which the WFDB specification directs readers to assume 200 ADC units
// per millivolt.
void parse_gain_field(const std::string& token, SignalSpec& spec,
                      bool& baseline_present) {
  std::size_t consumed = 0;
  double gain = parse_leading_number(token, consumed, "ADC gain");
  baseline_present = false;

  std::string remainder = token.substr(consumed);
  if (!remainder.empty() && remainder.front() == '(') {
    const std::size_t closing = remainder.find(')');
    if (closing == std::string::npos) {
      throw FormatError("unterminated baseline in gain field: " + token);
    }
    const std::string baseline_text = remainder.substr(1, closing - 1);
    spec.baseline =
        static_cast<int>(parse_integer(baseline_text, "signal baseline"));
    baseline_present = true;
    remainder = remainder.substr(closing + 1);
  }

  if (!remainder.empty() && remainder.front() == '/') {
    spec.units = remainder.substr(1);
    if (spec.units.empty()) {
      throw FormatError("empty units in gain field: " + token);
    }
  }

  if (gain == 0.0) {
    gain = 200.0;  // Uncalibrated signal; WFDB default gain.
  }
  if (gain < 0.0) {
    throw FormatError("ADC gain must not be negative: " + token);
  }
  spec.adc_gain = gain;
}

SignalSpec parse_signal_line(const std::string& line, int line_number) {
  // filename format gain resolution zero initial checksum blocksize description
  const std::vector<std::string> fields = split_fields(line, 9);
  if (fields.size() < 2) {
    throw FormatError("signal line " + std::to_string(line_number) +
                      " needs at least a file name and format");
  }

  SignalSpec spec;
  spec.file_name = fields[0];
  spec.format = parse_format_field(fields[1]);

  bool baseline_present = false;
  if (fields.size() > 2) {
    parse_gain_field(fields[2], spec, baseline_present);
  }
  if (fields.size() > 3) {
    spec.adc_resolution =
        static_cast<int>(parse_integer(fields[3], "ADC resolution"));
  }
  if (fields.size() > 4) {
    spec.adc_zero = static_cast<int>(parse_integer(fields[4], "ADC zero"));
  }
  if (fields.size() > 5) {
    spec.initial_value =
        static_cast<int>(parse_integer(fields[5], "initial value"));
  }
  if (fields.size() > 6) {
    spec.checksum = static_cast<int>(parse_integer(fields[6], "checksum"));
  }
  if (fields.size() > 7) {
    spec.block_size = static_cast<int>(parse_integer(fields[7], "block size"));
  }
  if (fields.size() > 8) {
    spec.description = fields[8];
  }

  // When no explicit baseline is given, the ADC zero level defines it.
  if (!baseline_present) {
    spec.baseline = spec.adc_zero;
  }
  return spec;
}

}  // namespace

double Header::duration_seconds() const {
  if (sampling_frequency <= 0.0) {
    return 0.0;
  }
  return static_cast<double>(num_samples_per_signal) / sampling_frequency;
}

const SignalSpec& Header::signal(std::size_t index) const {
  if (index >= signals.size()) {
    throw std::out_of_range("signal index " + std::to_string(index) +
                            " is out of range for " +
                            std::to_string(signals.size()) + " signals");
  }
  return signals[index];
}

Header parse_header_text(const std::string& text) {
  std::istringstream stream(text);
  std::string line;
  Header header;
  bool record_line_seen = false;
  int line_number = 0;

  while (std::getline(stream, line)) {
    ++line_number;
    strip_carriage_return(line);

    if (!line.empty() && line.front() == '#') {
      std::string comment = line.substr(1);
      if (!comment.empty() && comment.front() == ' ') {
        comment.erase(0, 1);
      }
      header.comments.push_back(comment);
      continue;
    }
    if (is_blank(line)) {
      continue;
    }

    if (!record_line_seen) {
      // record_name[/segments] num_signals [frequency [num_samples ...]]
      const std::vector<std::string> fields = split_fields(line, 8);
      if (fields.size() < 2) {
        throw FormatError(
            "record line must contain a record name and signal count");
      }
      const std::string& name_field = fields[0];
      const std::size_t slash = name_field.find('/');
      if (slash != std::string::npos) {
        throw FormatError(
            "multi-segment records are not supported by this reader: " +
            name_field);
      }
      header.record_name = name_field;
      header.num_signals =
          static_cast<int>(parse_integer(fields[1], "number of signals"));
      if (header.num_signals <= 0) {
        throw FormatError("number of signals must be positive");
      }
      if (fields.size() > 2) {
        header.sampling_frequency = parse_sampling_frequency(fields[2]);
      }
      if (fields.size() > 3) {
        header.num_samples_per_signal =
            parse_integer(fields[3], "samples per signal");
        if (header.num_samples_per_signal < 0) {
          throw FormatError("samples per signal must not be negative");
        }
      }
      record_line_seen = true;
      continue;
    }

    if (static_cast<int>(header.signals.size()) < header.num_signals) {
      header.signals.push_back(parse_signal_line(line, line_number));
    }
  }

  if (!record_line_seen) {
    throw FormatError("header contains no record line");
  }
  if (static_cast<int>(header.signals.size()) != header.num_signals) {
    throw FormatError("record declares " + std::to_string(header.num_signals) +
                      " signals but " + std::to_string(header.signals.size()) +
                      " signal lines were found");
  }
  return header;
}

Header parse_header_file(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    throw FormatError("cannot open header file: " + path);
  }
  std::ostringstream buffer;
  buffer << file.rdbuf();
  return parse_header_text(buffer.str());
}

}  // namespace wfdb
