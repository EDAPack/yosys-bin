#!/bin/sh
# Generic synth + stat: shows the agent the simplest possible yosys run
# and how to read the resulting cell counts.
set -e
cd "$(dirname "$0")"
yosys -q -p 'read_verilog blinky.v; hierarchy -top blinky; proc; opt; stat'
