// WFDB annotation (.atr) reading for the MIT-BIH Arrhythmia Database.
//
// Part of the ecg-arrhythmia-detection-pipeline portfolio project.
//
// The MIT annotation format stores each annotation as one or more 16-bit
// little-endian words. In the leading word of every annotation the six most
// significant bits hold the annotation type code and the remaining ten bits
// hold the time interval, in sample intervals, since the previous annotation.
// Codes above 59 are not annotations at all; they are modifier words that
// attach extra fields to the annotation that precedes them, and code 59
// (SKIP) carries a full 32-bit interval in the two words that follow it.
//
// Format reference:
//   https://physionet.org/physiotools/wag/annot-5.htm
//   https://archive.physionet.org/physiotools/wpg/wpg_32.htm

#ifndef WFDB_ANNOTATION_HPP
#define WFDB_ANNOTATION_HPP

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "wfdb/header.hpp"  // for wfdb::FormatError

namespace wfdb {

// ---------------------------------------------------------------------------
// Annotation type codes
// ---------------------------------------------------------------------------

// Largest ordinary annotation type code. Codes 1..kMaxCode may appear as the
// type of a real annotation; codes above kSkip are structural.
constexpr int kMaxCode = 49;

// Structural codes. These never describe a cardiac event.
constexpr int kSkip = 59;  // Followed by a 32-bit interval in two words.
constexpr int kNum = 60;   // Sets the `num` field.
constexpr int kSub = 61;   // Sets the `subtype` field.
constexpr int kChn = 62;   // Sets the `channel` field.
constexpr int kAux = 63;   // Attaches a counted auxiliary string.

// Returns the WFDB mnemonic for a type code, for example "N" for code 1.
// Returns an empty string for code 0 and for codes with no assigned meaning.
std::string annotation_symbol(int code);

// Returns the human-readable description of a type code, for example
// "Normal beat" for code 1.
std::string annotation_description(int code);

// True when the code denotes a heartbeat, and therefore marks a QRS complex.
// This is the set WFDB exposes through its isqrs() macro:
//   N L R a V F J A S E j / Q B ? ! e n f r
// Non-beat codes such as "+" (rhythm change) and "~" (signal quality change)
// carry timing information but do not mark a beat.
bool is_beat_code(int code);

// ---------------------------------------------------------------------------
// AAMI beat classes
// ---------------------------------------------------------------------------

// The five heartbeat classes of ANSI/AAMI EC57, plus a sentinel for
// annotations that do not mark a beat at all.
enum class AamiClass {
  NotABeat,           // Not a heartbeat annotation.
  Normal,             // N: normal or bundle branch block beat.
  Supraventricular,   // S: supraventricular ectopic beat.
  Ventricular,        // V: ventricular ectopic beat.
  Fusion,             // F: fusion of a ventricular and a normal beat.
  Unknown,            // Q: paced, paced fusion, or unclassifiable beat.
};

// Maps a WFDB type code onto its AAMI class. Non-beat codes map to NotABeat.
//
// The grouping follows the convention established by de Chazal et al. and used
// throughout the MIT-BIH classification literature:
//
//   N  <-  N  L  R  B  e  j
//   S  <-  A  a  J  S  n
//   V  <-  V  E  r
//   F  <-  F
//   Q  <-  /  f  Q  ?  !
//
// Two of those assignments are conventions rather than direct quotations of
// the standard, and are worth stating plainly:
//
//   * EC57 describes class S as covering "an atrial or nodal (junctional)
//     premature or escape beat", which read literally would place the escape
//     beats "e" and "j" in S. The classification literature places them in N
//     instead, and this implementation follows the literature so that its
//     results are comparable with published work.
//   * EC57 assigns no class to the ventricular flutter wave "!" or to the
//     learning marker "?". Both are grouped into Q here.
AamiClass aami_class_of(int code);

// One-character AAMI mnemonic: "N", "S", "V", "F", "Q", or "-".
const char* aami_class_symbol(AamiClass cls);

// Descriptive AAMI class name, for example "Ventricular ectopic".
const char* aami_class_name(AamiClass cls);

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

// A single decoded annotation.
struct Annotation {
  std::int64_t sample = 0;  // Absolute sample number from the record start.
  int code = 0;             // WFDB annotation type code.
  int subtype = 0;          // Type-specific qualifier; resets to 0 per record.
  int channel = 0;          // Signal the annotation refers to; carries over.
  int num = 0;              // Free-use small integer field; carries over.
  std::string aux;          // Auxiliary string, exactly as stored.

  std::string symbol() const { return annotation_symbol(code); }
  std::string description() const { return annotation_description(code); }
  bool is_beat() const { return is_beat_code(code); }
  AamiClass aami_class() const { return aami_class_of(code); }

  // Elapsed time of the annotation, in seconds, at the given sampling rate.
  double time_seconds(double sampling_frequency) const;
};

// The auxiliary field is stored with an explicit byte count and is padded to an
// even length, so it frequently carries a trailing NUL. This returns the field
// with trailing NUL bytes removed, which is what a reader wants to display.
std::string aux_text(const Annotation& annotation);

// Decodes annotations from a buffer holding the entire contents of an
// annotation file. Exposed separately from the file reader so that the decoder
// can be tested against synthetic byte sequences.
//
// Throws FormatError if the buffer has an odd length or ends in the middle of
// a SKIP interval or an auxiliary string.
std::vector<Annotation> decode_annotations(const std::vector<std::uint8_t>& bytes);

// Reads and decodes an annotation file from disk, for example "100.atr".
std::vector<Annotation> read_annotation_file(const std::string& path);

// ---------------------------------------------------------------------------
// Summaries
// ---------------------------------------------------------------------------

// Aggregate counts over a decoded annotation list.
struct AnnotationSummary {
  std::size_t total = 0;                       // All annotations.
  std::size_t beats = 0;                       // Those marking a heartbeat.
  std::int64_t last_sample = 0;                // Sample of the final annotation.
  std::map<int, std::size_t> code_counts;      // Count per type code.
  std::map<AamiClass, std::size_t> class_counts;  // Count per AAMI class.

  // Count lookups that return 0 for absent keys. Preferred over indexing the
  // maps directly, which is not available on a const summary.
  std::size_t count_of_code(int code) const;
  std::size_t count_of_class(AamiClass cls) const;
};

AnnotationSummary summarize(const std::vector<Annotation>& annotations);

// Sample numbers of the beat annotations only, in order.
std::vector<std::int64_t> beat_samples(const std::vector<Annotation>& annotations);

// Intervals between successive beats, in samples. Returns one fewer element
// than there are beats, and an empty vector when there are fewer than two.
std::vector<std::int64_t> rr_intervals(const std::vector<Annotation>& annotations);

// Mean heart rate in beats per minute, derived from the RR intervals.
// Returns 0.0 when there are fewer than two beats.
double mean_heart_rate_bpm(const std::vector<Annotation>& annotations,
                           double sampling_frequency);

}  // namespace wfdb

#endif  // WFDB_ANNOTATION_HPP
