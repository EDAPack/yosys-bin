#!/bin/sh
# Translate a SystemVerilog module that uses a packed struct and
# always_ff into Verilog-2005, then feed it through yosys to prove the
# output is consumable by a Verilog-only frontend.
set -e
cd "$(dirname "$0")"
sv2v top.sv > top.v
echo "--- sv2v output (top.v) ---"
sed -n '1,40p' top.v
echo
echo "--- yosys reading the result ---"
yosys -q -p 'read_verilog top.v; hierarchy -top top; proc; opt; stat'
