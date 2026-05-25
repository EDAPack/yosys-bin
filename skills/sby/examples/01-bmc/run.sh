#!/bin/sh
# Bounded model check of counter.sv to depth 10.  Expected outcome:
# FAIL at step 5 — the asserted invariant (q != 5) is violated when the
# counter reaches 5.  The VCD lands at counter/engine_0/trace.vcd.
set -e
cd "$(dirname "$0")"
sby -f counter.sby || true
echo
echo "--- summary ---"
grep -E "DONE|SUMMARY|FAIL|PASS|Assert" counter/logfile.txt || true
