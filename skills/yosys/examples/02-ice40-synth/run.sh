#!/bin/sh
# Target-specific synthesis: produce a JSON netlist suitable for
# nextpnr-ice40 from a single Verilog module.
set -e
cd "$(dirname "$0")"
yosys -q -p 'read_verilog counter.v; synth_ice40 -top counter -json counter.json'
ls -l counter.json
