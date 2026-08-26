# Data Source: MIT-BIH Arrhythmia Database

This project uses the MIT-BIH Arrhythmia Database, obtained from PhysioNet. **Raw signal and annotation files are not committed to this repository.** Download them locally using the instructions below.

## Dataset Summary

| Property | Value |
|---|---|
| Records | 48 half-hour excerpts |
| Subjects | 47 (25 men aged 32–89, 22 women aged 23–89) |
| Recording period | 1975–1979, BIH Arrhythmia Laboratory |
| Channels | 2 |
| Sampling rate | 360 Hz per channel |
| ADC resolution | 11-bit |
| ADC range | ±5 mV, sample values 0–2047, zero at 1024 |
| Signal storage format | WFDB format 212: pairs of 12-bit amplitudes packed into triplets of bytes |
| Annotations | Beat-by-beat cardiologist labels for all 48 records |
| Records containing paced beats | 102, 104, 107, 217 |
| License | Open Data Commons Attribution License v1.0 |

## Download

Download the archive from the MIT-BIH Arrhythmia Database page[1] and extract it into a `data/mitdb/` directory.

Alternatively, from a terminal:

```bash
wget -r -N -c -np https://physionet.org/files/mitdb/1.0.0/
```

Or using AWS command line tools:

```bash
aws s3 sync --no-sign-request s3://physionet-open/mitdb/1.0.0/ data/mitdb/
```

## Expected Local Layout

```text
data/
├── README.md
├── .gitignore
└── mitdb/
    ├── 100.atr
    ├── 100.dat
    ├── 100.hea
    ├── 101.atr
    └── ...
```

## Required Citations

This database is distributed under the Open Data Commons Attribution License v1.0, which requires attribution. Both citations below are required by PhysioNet.

Moody GB, Mark RG. The impact of the MIT-BIH Arrhythmia Database. *IEEE Engineering in Medicine and Biology* 20(3):45-50 (May-June 2001). PMID: 11446209.

Pollard, T., Moody, B. E., Lehman, L., Gow, B., Fernandes, C., Xie, C., Johnson, A., Mark, R. G., & Heldt, T. (2026). PhysioNet as a global platform for biomedical research. *Nature Health*. https://doi.org/10.1038/s44360-026-00096-z

## Ethical Note

These are recordings from real human subjects, de-identified and released for research and education. This project uses them solely for algorithm development and evaluation. No output of this project constitutes a clinical diagnosis, and nothing here is validated for patient care.
