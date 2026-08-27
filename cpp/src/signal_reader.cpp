#include "wfdb/signal_reader.hpp"

#include <fstream>
#include <sstream>

namespace wfdb {
namespace {

// Sign-extends a 12-bit two's-complement value to a full signed integer.
// Values above 2047 represent negative amplitudes.
inline int sign_extend_12bit(int value) {
  return (value & 0x800) != 0 ? value - 0x1000 : value;
}

std::string join_path(const std::string& directory, const std::string& name) {
  if (directory.empty()) {
    return name;
  }
  const char last = directory.back();
  if (last == '/' || last == '\\') {
    return directory + name;
  }
  return directory + "/" + name;
}

}  // namespace

std::size_t format212_byte_count(std::int64_t sample_count) {
  if (sample_count <= 0) {
    return 0;
  }
  const std::int64_t triplets = (sample_count + 1) / 2;
  return static_cast<std::size_t>(triplets * 3);
}

std::vector<int> decode_format212(const std::uint8_t* data,
                                  std::size_t byte_count,
                                  std::int64_t sample_count) {
  if (sample_count < 0) {
    throw FormatError("sample count must not be negative");
  }
  if (sample_count == 0) {
    return {};
  }
  if (data == nullptr) {
    throw FormatError("format-212 buffer is null");
  }

  const std::size_t required = format212_byte_count(sample_count);
  if (byte_count < required) {
    throw FormatError("format-212 buffer holds " + std::to_string(byte_count) +
                      " bytes but " + std::to_string(required) +
                      " are required for " + std::to_string(sample_count) +
                      " samples");
  }

  std::vector<int> samples;
  samples.reserve(static_cast<std::size_t>(sample_count));

  std::size_t offset = 0;
  while (static_cast<std::int64_t>(samples.size()) < sample_count) {
    const int low_byte = data[offset];
    const int middle_byte = data[offset + 1];
    const int high_byte = data[offset + 2];
    offset += 3;

    const int first = low_byte | ((middle_byte & 0x0F) << 8);
    samples.push_back(sign_extend_12bit(first));

    if (static_cast<std::int64_t>(samples.size()) == sample_count) {
      break;  // Odd sample count: the triplet's second sample is padding.
    }

    const int second = high_byte | (((middle_byte >> 4) & 0x0F) << 8);
    samples.push_back(sign_extend_12bit(second));
  }

  return samples;
}

std::vector<std::vector<int>> deinterleave(const std::vector<int>& interleaved,
                                           int num_signals) {
  if (num_signals <= 0) {
    throw FormatError("number of signals must be positive");
  }
  if (interleaved.size() % static_cast<std::size_t>(num_signals) != 0) {
    throw FormatError("interleaved stream of " +
                      std::to_string(interleaved.size()) +
                      " samples does not divide evenly into " +
                      std::to_string(num_signals) + " signals");
  }

  const std::size_t frames =
      interleaved.size() / static_cast<std::size_t>(num_signals);
  std::vector<std::vector<int>> channels(
      static_cast<std::size_t>(num_signals));
  for (auto& channel : channels) {
    channel.reserve(frames);
  }

  for (std::size_t frame = 0; frame < frames; ++frame) {
    const std::size_t base = frame * static_cast<std::size_t>(num_signals);
    for (int signal = 0; signal < num_signals; ++signal) {
      channels[static_cast<std::size_t>(signal)].push_back(
          interleaved[base + static_cast<std::size_t>(signal)]);
    }
  }
  return channels;
}

std::vector<std::vector<int>> read_format212_file(
    const std::string& path, int num_signals,
    std::int64_t num_samples_per_signal) {
  if (num_signals <= 0) {
    throw FormatError("number of signals must be positive");
  }

  std::ifstream file(path, std::ios::binary);
  if (!file) {
    throw FormatError("cannot open signal file: " + path);
  }

  const std::int64_t total_samples =
      num_samples_per_signal * static_cast<std::int64_t>(num_signals);
  const std::size_t required = format212_byte_count(total_samples);

  std::vector<std::uint8_t> buffer(required);
  if (required > 0) {
    file.read(reinterpret_cast<char*>(buffer.data()),
              static_cast<std::streamsize>(required));
    if (static_cast<std::size_t>(file.gcount()) != required) {
      throw FormatError("signal file " + path + " is truncated: expected " +
                        std::to_string(required) + " bytes, read " +
                        std::to_string(file.gcount()));
    }
  }

  const std::vector<int> interleaved =
      decode_format212(buffer.data(), buffer.size(), total_samples);
  return deinterleave(interleaved, num_signals);
}

Record read_record(const std::string& directory,
                   const std::string& record_name) {
  Record record;
  record.header =
      parse_header_file(join_path(directory, record_name + ".hea"));

  if (record.header.signals.empty()) {
    throw FormatError("record " + record_name + " declares no signals");
  }

  const std::string& signal_file = record.header.signals.front().file_name;
  for (const SignalSpec& spec : record.header.signals) {
    if (spec.format != 212) {
      throw FormatError("only format 212 is supported; signal '" +
                        spec.description + "' uses format " +
                        std::to_string(spec.format));
    }
    if (spec.file_name != signal_file) {
      throw FormatError(
          "this reader requires all signals to share one signal file");
    }
  }

  record.samples =
      read_format212_file(join_path(directory, signal_file),
                          record.header.num_signals,
                          record.header.num_samples_per_signal);
  return record;
}

int checksum16(const std::vector<int>& samples) {
  // Accumulate in a 32-bit type, then reinterpret the low 16 bits as signed,
  // which is what the WFDB tools store in the header.
  std::int32_t total = 0;
  for (const int sample : samples) {
    total += sample;
  }
  const std::uint16_t truncated = static_cast<std::uint16_t>(total & 0xFFFF);
  return static_cast<int>(static_cast<std::int16_t>(truncated));
}

std::vector<double> to_physical(const std::vector<int>& raw_samples,
                               const SignalSpec& spec) {
  std::vector<double> physical;
  physical.reserve(raw_samples.size());
  for (const int sample : raw_samples) {
    physical.push_back(spec.to_physical(sample));
  }
  return physical;
}

bool verify_record(const Record& record, std::string* report) {
  std::ostringstream problems;
  bool ok = true;

  if (record.samples.size() != record.header.signals.size()) {
    problems << "decoded " << record.samples.size() << " channels but header "
             << "declares " << record.header.signals.size() << "\n";
    if (report != nullptr) {
      *report += problems.str();
    }
    return false;
  }

  for (std::size_t index = 0; index < record.samples.size(); ++index) {
    const SignalSpec& spec = record.header.signals[index];
    const std::vector<int>& channel = record.samples[index];

    if (static_cast<std::int64_t>(channel.size()) !=
        record.header.num_samples_per_signal) {
      ok = false;
      problems << "signal " << index << " (" << spec.description
               << "): decoded " << channel.size() << " samples, header declares "
               << record.header.num_samples_per_signal << "\n";
      continue;
    }
    if (!channel.empty() && channel.front() != spec.initial_value) {
      ok = false;
      problems << "signal " << index << " (" << spec.description
               << "): first sample " << channel.front()
               << " does not match declared initial value "
               << spec.initial_value << "\n";
    }
    const int computed = checksum16(channel);
    if (computed != spec.checksum) {
      ok = false;
      problems << "signal " << index << " (" << spec.description
               << "): checksum " << computed << " does not match declared "
               << spec.checksum << "\n";
    }
  }

  if (!ok && report != nullptr) {
    *report += problems.str();
  }
  return ok;
}

}  // namespace wfdb
