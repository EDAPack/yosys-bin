#!/bin/sh
# Same flow as 02-ice40-synth but driven from a .ys script file —
# the form preferred for non-trivial flows so commands are version-
# controllable and re-runnable line by line.
set -e
cd "$(dirname "$0")"
yosys -q synth.ys
