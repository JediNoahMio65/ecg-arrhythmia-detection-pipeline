#!/usr/bin/env python3
"""Generate the annotation reference fixture used by the C++ test suite.

The C++ decoder in src/annotation.cpp is verified field by field against the
output of the reference WFDB implementation maintained by the PhysioNet team
(the `wfdb` package on PyPI). This script writes that reference output to a CSV
file so the C++ tests can compare against it without a Python dependency at
test time.

Usage, from the repository root:

    pip install wfdb
    python cpp/tests/data/generate_reference.py data/mitdb/100 \
        cpp/tests/data/100.atr.reference.csv

Columns:
    sample   absolute sample number of the annotation
    code     WFDB annotation type code (the `label_store` value)
    subtype  annotation subtype field
    chan     annotation channel field
    num      annotation num field
    aux_hex  auxiliary string as lowercase hex, exactly as stored, or empty
"""

import argparse
import csv
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("record", help="record path without extension, e.g. data/mitdb/100")
    parser.add_argument("output", help="destination CSV path")
    parser.add_argument("--extension", default="atr", help="annotator name (default: atr)")
    args = parser.parse_args()

    try:
        import wfdb
    except ImportError:
        print("error: the 'wfdb' package is required (pip install wfdb)", file=sys.stderr)
        return 1

    ann = wfdb.rdann(
        args.record,
        args.extension,
        return_label_elements=["label_store"],
    )

    with open(args.output, "w", newline="", encoding="ascii") as handle:
        writer = csv.writer(handle)
        writer.writerow(["sample", "code", "subtype", "chan", "num", "aux_hex"])
        for i in range(len(ann.sample)):
            aux = ann.aux_note[i] or ""
            aux_hex = "".join(f"{ord(ch):02x}" for ch in aux)
            writer.writerow(
                [
                    int(ann.sample[i]),
                    int(ann.label_store[i]),
                    int(ann.subtype[i]),
                    int(ann.chan[i]),
                    int(ann.num[i]),
                    aux_hex,
                ]
            )

    print(f"wrote {len(ann.sample)} reference annotations to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
