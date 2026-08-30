# MATLAB reference pipeline

This folder holds the MATLAB half of the project: an independent reader for the
raw MIT-BIH WFDB files and the reference ECG preprocessing chain that every
later stage is measured against.

## Why MATLAB reads the raw files again

The C++ library in [`../cpp`](../cpp) already parses WFDB headers, format-212
signal files and annotation files. The MATLAB code here does the same job from
scratch rather than importing a CSV that C++ produced.

That is deliberate. Two independent implementations of the same published
format, written in different languages and checked against the same external
ground truth, catch mistakes that a single implementation cannot. If both agree
field for field on 2,274 annotations, the probability that both misread the
format in the same way is small. If one of them had a bug, the comparison would
fail loudly instead of silently propagating.

The shared ground truth is `cpp/tests/data/100.atr.reference.csv`, generated
from the independent Python `wfdb` package. Neither the C++ nor the MATLAB
reader is validated against the other; both are validated against that file.

There is also a practical reason: the MATLAB code requires no WFDB Toolbox and
no MEX compilation. Only the Signal Processing Toolbox is needed, and only for
`butter` and `filtfilt`.

## Layout

```text
matlab/
├── ecgProjectRoot.m                    locate the repository root
├── addEcgPaths.m                       put io/, preprocess/, scripts/ on the path
├── io/
│   ├── wfdbCodeTable.m                 the 50 WFDB annotation codes
│   ├── wfdbAnnotationSymbol.m          code -> printable symbol
│   ├── wfdbAnnotationDescription.m     code -> human-readable description
│   ├── wfdbIsBeatCode.m               is this code a heartbeat?
│   ├── wfdbAamiClass.m                 beat code -> AAMI EC57 class N/S/V/F/Q
│   ├── wfdbChecksum16.m                signed 16-bit wrapping checksum
│   ├── readWfdbHeader.m                parse a .hea file
│   ├── readWfdbSignal.m                decode a format-212 .dat file
│   ├── readWfdbAnnotations.m           read a .atr file into a table
│   ├── decodeWfdbAnnotationBytes.m     the annotation byte-stream decoder
│   └── compareWfdbAnnotationFixture.m  field-by-field check against the CSV
├── preprocess/
│   ├── notchBiquad.m                   hand-designed powerline notch
│   ├── preprocessEcg.m                 the three-stage denoising chain
│   └── bandPowerFraction.m             share of power in a frequency band
├── scripts/
│   └── runSection3.m                   driver: verify, preprocess, report, plot
├── tests/
│   ├── tWfdbIo.m                       52 tests for the I/O layer
│   └── tPreprocess.m                   32 tests for the preprocessing chain
└── figures/
    └── section3_preprocessing.png      produced by runSection3.m
```

## The preprocessing chain

`preprocessEcg` applies three stages in order.

**1. Baseline wander removal — two cascaded moving medians, 200 ms then 600 ms.**
Baseline wander is slow drift from respiration and electrode movement. A median
is used instead of a high-pass filter because a median is insensitive to the QRS
complex, which is short and tall: the window slides past the R peak without
being pulled up by it. A steep high-pass filter with the same cutoff would
distort R peak amplitude and add ringing around each beat. The short window
spans roughly one QRS complex and the long window spans roughly one beat, so
neither can follow the beat itself.

`movmedian` is used rather than `medfilt1` because `movmedian` shrinks its
window at the signal edges instead of padding with zeros, which avoids a
spurious step at the first and last samples.

**2. Zero-phase Butterworth bandpass, 0.5 to 40 Hz, order 2 per edge.**
Applied with `filtfilt`, which runs the filter forwards and then backwards. That
squares the magnitude response but cancels the phase response exactly.

Zero phase is not a cosmetic choice here. Detector evaluation in later sections
compares detected peak positions against the sample numbers in the annotation
file. A filter with any group delay would shift every R peak away from its
annotation, and every sensitivity and positive-predictivity figure computed
afterwards would inherit that offset. `tPreprocess` asserts zero phase directly
by checking that the impulse response peaks on the impulse and is symmetric
about it.

**3. Powerline notch, 60 Hz, Q = 35.**
MIT-BIH was recorded in the United States, so the default is 60 Hz; pass
`'NotchFrequency', 50` elsewhere. The biquad is designed by hand in
`notchBiquad.m` using the standard RBJ cookbook form rather than calling
`iirnotch`, which would add a DSP System Toolbox dependency. At 60 Hz with a
360 Hz sampling rate the centre frequency lands on exactly one sixth of the
sampling rate, so \(\cos\omega_0\) is exactly 0.5 and the numerator taps come
out as an exact \([1, -1, 1]\) scaled by the normalisation constant.

## Measured effect on record 100

Computed over the interior of the record, excluding a two-second guard at each
end so that filter edge transients are not counted. Values are the share of
total signal power in each band.

| Band | Raw | Cleaned |
|---|---:|---:|
| below 0.5 Hz (baseline wander) | 0.072667 | 0.000046 |
| 0.5 to 40 Hz (diagnostic band) | 0.913421 | 0.998089 |
| 59 to 61 Hz (powerline) | 0.001270 | 0.000001 |
| above 40 Hz | 0.013912 | 0.001865 |

Baseline wander drops by a factor of roughly 1,600 and powerline interference by
roughly 1,800, while the share of power inside the diagnostic band rises from
91.3 to 99.8 percent.

The waveform itself is preserved:

| Measure | Value |
|---|---:|
| RMS, raw | 0.3621 mV |
| RMS, cleaned | 0.1777 mV |
| Correlation, raw against cleaned | 0.9450 |
| Mean of cleaned signal | 6.1e-06 mV |

The drop in RMS is the removed wander and noise, not lost signal; the
correlation of 0.945 confirms the underlying ECG is intact.

Most importantly, filtering does not move the beats. Searching a 50 ms window
around each of the 2,267 interior beat annotations:

| Measure | Value |
|---|---:|
| Median offset from the annotation | 0 samples |
| Beats with peak within 5 samples | 99.96 % |
| Mean R peak amplitude after filtering | 1.214 mV |
| Beats with peak amplitude above 0.3 mV | 99.96 % |

## Running it

From the repository root in MATLAB:

```matlab
addpath('matlab'); addEcgPaths();
run('matlab/scripts/runSection3.m');
```

The driver verifies every channel's initial value and checksum against the
header, cross-checks the decoded annotations against the C++ test fixture,
prints the AAMI class breakdown and the band-power table above, and writes
`matlab/figures/section3_preprocessing.png`.

## Tests

```matlab
runtests('matlab/tests')
```

84 tests in two classes. They fall into three groups:

- **Format tests** drive the decoders with hand-built byte sequences whose
  correct interpretation is known from the WFDB specification. These cover the
  awkward corners: the SKIP word and its 32-bit jump, consecutive SKIP words,
  sticky `chan` and `num` versus per-annotation `subtype`, sign extension of
  negative subtypes, odd-length auxiliary payloads, sign extension of 12-bit
  samples, and truncated files being reported rather than silently padded.

- **Response tests** drive the preprocessing chain with signals whose correct
  treatment is known in advance: a constant, a linear ramp, and sine waves at
  0.1, 5, 10, 20, 30, 60 and 80 Hz. Together these pin down the frequency
  response without needing any data file.

- **Record tests** run against MIT-BIH record 100 and assert the ground-truth
  figures above, including the field-by-field comparison with the C++ fixture.

The record tests use `assumeTrue`, so if `data/mitdb/` is absent they report as
*incomplete* rather than failing. The format and response tests always run.

One documented outlier: a single beat out of 2,267 has its filtered peak more
than 5 samples from its annotation. Annotation sample numbers mark the beat as
a cardiologist placed it, not the arithmetic maximum of a filtered trace, so
exact agreement on every beat is not expected. The thresholds in the tests are
set at 99 percent, comfortably below the measured 99.96 percent, so they detect
a regression without being brittle.

## Requirements

- MATLAB R2020a or newer (`exportgraphics`, `movmedian`, `arguments` blocks)
- Signal Processing Toolbox, for `butter` and `filtfilt`
- No DSP System Toolbox, no WFDB Toolbox, no MEX compilation

## Data

`data/mitdb/` is not tracked in this repository. Download `100.hea`, `100.dat`
and `100.atr` from the
[MIT-BIH Arrhythmia Database](https://physionet.org/content/mitdb/1.0.0/) and
place them there.

## Format references

- [WFDB annotation file format](https://physionet.org/physiotools/wag/annot-5.htm)
- [WFDB header file format](https://physionet.org/physiotools/wag/header-5.htm)
- [WFDB signal file formats](https://physionet.org/physiotools/wag/signal-5.htm)
- [ANSI/AAMI EC57](https://mdcpp.com/doc/standard/ANSIAAMIEC57-1998(R)2003.pdf),
  for the N/S/V/F/Q beat grouping
