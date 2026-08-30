// Command-line utility that summarizes the annotations of a WFDB record:
// beat counts by type, the AAMI class breakdown, RR-interval statistics, and
// the rhythm and comment annotations carried in auxiliary strings.
//
// Usage: wfdb_ann <data-directory> <record-name> [annotations-to-print]
//
// The record's header is read to obtain the sampling frequency so that sample
// numbers can be reported as elapsed time.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "wfdb/annotation.hpp"
#include "wfdb/header.hpp"

namespace {

// Renders a sample number as hh:mm:ss.mmm elapsed time.
std::string format_time(std::int64_t sample, double sampling_frequency) {
  const double seconds = static_cast<double>(sample) / sampling_frequency;
  const auto total_ms = static_cast<std::int64_t>(seconds * 1000.0 + 0.5);
  const std::int64_t ms = total_ms % 1000;
  const std::int64_t total_seconds = total_ms / 1000;
  const std::int64_t s = total_seconds % 60;
  const std::int64_t m = (total_seconds / 60) % 60;
  const std::int64_t h = total_seconds / 3600;

  std::ostringstream out;
  out << std::setfill('0') << std::setw(2) << h << ':' << std::setw(2) << m << ':'
      << std::setw(2) << s << '.' << std::setw(3) << ms;
  return out.str();
}

// Escapes control characters so that auxiliary strings print safely.
std::string printable(const std::string& text) {
  std::string out;
  for (const char ch : text) {
    const auto value = static_cast<unsigned char>(ch);
    if (value >= 0x20 && value < 0x7F) {
      out.push_back(ch);
    } else {
      out += "\\x";
      const char* digits = "0123456789abcdef";
      out.push_back(digits[(value >> 4) & 0x0F]);
      out.push_back(digits[value & 0x0F]);
    }
  }
  return out;
}

double percentage(std::size_t part, std::size_t whole) {
  if (whole == 0) {
    return 0.0;
  }
  return 100.0 * static_cast<double>(part) / static_cast<double>(whole);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    std::cerr << "usage: " << argv[0]
              << " <data-directory> <record-name> [annotations-to-print]\n";
    return 2;
  }

  const std::string directory = argv[1];
  const std::string record_name = argv[2];
  std::size_t annotations_to_print = 10;
  if (argc > 3) {
    try {
      annotations_to_print = static_cast<std::size_t>(std::stoul(argv[3]));
    } catch (const std::exception&) {
      std::cerr << "annotations-to-print must be a non-negative integer\n";
      return 2;
    }
  }

  try {
    const wfdb::Header header =
        wfdb::parse_header_file(directory + "/" + record_name + ".hea");
    const std::vector<wfdb::Annotation> annotations =
        wfdb::read_annotation_file(directory + "/" + record_name + ".atr");
    const wfdb::AnnotationSummary summary = wfdb::summarize(annotations);
    const double fs = header.sampling_frequency;

    std::cout << "record             " << header.record_name << "\n"
              << "sampling frequency " << fs << " Hz\n"
              << "record length      " << header.num_samples_per_signal
              << " samples (" << std::fixed << std::setprecision(2)
              << header.duration_seconds() << " s)\n"
              << "annotations        " << summary.total << "\n"
              << "beat annotations   " << summary.beats << "\n"
              << "last annotation    " << summary.last_sample << " ("
              << format_time(summary.last_sample, fs) << ")\n";

    // ---------------------------------------------------------------------
    // Annotation types present
    // ---------------------------------------------------------------------
    std::cout << "\nannotation types\n"
              << "  code  sym  aami  count   share  description\n";
    for (const auto& entry : summary.code_counts) {
      const int code = entry.first;
      const std::size_t count = entry.second;
      const wfdb::AamiClass cls = wfdb::aami_class_of(code);
      std::string symbol = wfdb::annotation_symbol(code);
      if (symbol.empty()) {
        symbol = "?";
      }
      std::cout << "  " << std::setw(4) << code << "  " << std::setw(3) << symbol
                << "  " << std::setw(4) << wfdb::aami_class_symbol(cls) << "  "
                << std::setw(5) << count << "  " << std::setw(5) << std::fixed
                << std::setprecision(1) << percentage(count, summary.total)
                << "%  " << wfdb::annotation_description(code) << "\n";
    }

    // ---------------------------------------------------------------------
    // AAMI breakdown, over beats only
    // ---------------------------------------------------------------------
    const wfdb::AamiClass classes[] = {
        wfdb::AamiClass::Normal, wfdb::AamiClass::Supraventricular,
        wfdb::AamiClass::Ventricular, wfdb::AamiClass::Fusion,
        wfdb::AamiClass::Unknown};

    std::cout << "\naami beat classes\n"
              << "  cls  count   share  description\n";
    for (const wfdb::AamiClass cls : classes) {
      const std::size_t count = summary.count_of_class(cls);
      std::cout << "  " << std::setw(3) << wfdb::aami_class_symbol(cls) << "  "
                << std::setw(5) << count << "  " << std::setw(5) << std::fixed
                << std::setprecision(1) << percentage(count, summary.beats)
                << "%  " << wfdb::aami_class_name(cls) << "\n";
    }

    // ---------------------------------------------------------------------
    // RR-interval statistics
    // ---------------------------------------------------------------------
    const std::vector<std::int64_t> intervals = wfdb::rr_intervals(annotations);
    if (!intervals.empty()) {
      const std::int64_t shortest =
          *std::min_element(intervals.begin(), intervals.end());
      const std::int64_t longest =
          *std::max_element(intervals.begin(), intervals.end());
      std::int64_t total = 0;
      for (const std::int64_t interval : intervals) {
        total += interval;
      }
      const double mean =
          static_cast<double>(total) / static_cast<double>(intervals.size());

      std::cout << "\nrr intervals\n"
                << "  count            " << intervals.size() << "\n"
                << "  mean             " << std::fixed << std::setprecision(1)
                << mean << " samples (" << std::setprecision(3) << mean / fs
                << " s)\n"
                << "  shortest         " << shortest << " samples ("
                << std::setprecision(3) << static_cast<double>(shortest) / fs
                << " s)\n"
                << "  longest          " << longest << " samples ("
                << std::setprecision(3) << static_cast<double>(longest) / fs
                << " s)\n"
                << "  mean heart rate  " << std::setprecision(1)
                << wfdb::mean_heart_rate_bpm(annotations, fs) << " bpm\n";
    }

    // ---------------------------------------------------------------------
    // Auxiliary strings, which carry rhythm labels and comments
    // ---------------------------------------------------------------------
    std::size_t aux_count = 0;
    for (const wfdb::Annotation& annotation : annotations) {
      if (!annotation.aux.empty()) {
        ++aux_count;
      }
    }
    if (aux_count > 0) {
      std::cout << "\nauxiliary strings (" << aux_count << ")\n";
      for (const wfdb::Annotation& annotation : annotations) {
        if (annotation.aux.empty()) {
          continue;
        }
        std::cout << "  " << std::setw(9) << annotation.sample << "  "
                  << format_time(annotation.sample, fs) << "  " << std::setw(2)
                  << annotation.symbol() << "  \""
                  << printable(wfdb::aux_text(annotation)) << "\"\n";
      }
    }

    // ---------------------------------------------------------------------
    // Leading annotations
    // ---------------------------------------------------------------------
    const std::size_t to_print = std::min(annotations_to_print, annotations.size());
    if (to_print > 0) {
      std::cout << "\nfirst " << to_print << " annotations\n"
                << "     sample          time  sym  aami  sub  chan  num\n";
      for (std::size_t i = 0; i < to_print; ++i) {
        const wfdb::Annotation& annotation = annotations[i];
        std::cout << "  " << std::setw(9) << annotation.sample << "  "
                  << format_time(annotation.sample, fs) << "  " << std::setw(3)
                  << annotation.symbol() << "  " << std::setw(4)
                  << wfdb::aami_class_symbol(annotation.aami_class()) << "  "
                  << std::setw(3) << annotation.subtype << "  " << std::setw(4)
                  << annotation.channel << "  " << std::setw(3) << annotation.num
                  << "\n";
      }
    }

    return 0;
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << "\n";
    return 1;
  }
}
