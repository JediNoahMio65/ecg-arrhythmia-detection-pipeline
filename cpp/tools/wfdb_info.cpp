// Command-line utility that summarizes a WFDB record and verifies that the
// decoded signals match the checksums declared in its header.
//
// Usage: wfdb_info <data-directory> <record-name> [samples-to-print]

#include <exception>
#include <iomanip>
#include <iostream>
#include <string>

#include "wfdb/signal_reader.hpp"

int main(int argc, char** argv) {
  if (argc < 3) {
    std::cerr << "usage: " << argv[0]
              << " <data-directory> <record-name> [samples-to-print]\n";
    return 2;
  }

  const std::string directory = argv[1];
  const std::string record_name = argv[2];
  std::size_t samples_to_print = 8;
  if (argc > 3) {
    try {
      samples_to_print = static_cast<std::size_t>(std::stoul(argv[3]));
    } catch (const std::exception&) {
      std::cerr << "samples-to-print must be a non-negative integer\n";
      return 2;
    }
  }

  try {
    const wfdb::Record record = wfdb::read_record(directory, record_name);
    const wfdb::Header& header = record.header;

    std::cout << "record             " << header.record_name << "\n"
              << "signals            " << header.num_signals << "\n"
              << "sampling frequency " << header.sampling_frequency << " Hz\n"
              << "samples per signal " << header.num_samples_per_signal << "\n"
              << "duration           " << std::fixed << std::setprecision(2)
              << header.duration_seconds() << " s\n";

    for (const std::string& comment : header.comments) {
      std::cout << "comment            " << comment << "\n";
    }

    for (std::size_t index = 0; index < record.samples.size(); ++index) {
      const wfdb::SignalSpec& spec = header.signal(index);
      std::cout << "\nsignal " << index << ": " << spec.description << "\n"
                << "  format           " << spec.format << "\n"
                << "  gain             " << spec.adc_gain << " ADU/"
                << spec.units << "\n"
                << "  baseline         " << spec.baseline << "\n"
                << "  declared first   " << spec.initial_value << "\n"
                << "  decoded first    " << record.samples[index].front()
                << "\n"
                << "  declared cksum   " << spec.checksum << "\n"
                << "  computed cksum   "
                << wfdb::checksum16(record.samples[index]) << "\n";

      std::cout << "  first samples   ";
      const std::size_t limit =
          samples_to_print < record.samples[index].size()
              ? samples_to_print
              : record.samples[index].size();
      for (std::size_t sample = 0; sample < limit; ++sample) {
        std::cout << " " << record.samples[index][sample];
      }
      std::cout << "\n";
    }

    std::string report;
    if (wfdb::verify_record(record, &report)) {
      std::cout << "\nverification       PASS (all first values and checksums "
                   "match the header)\n";
      return 0;
    }
    std::cout << "\nverification       FAIL\n" << report;
    return 1;
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << "\n";
    return 1;
  }
}
