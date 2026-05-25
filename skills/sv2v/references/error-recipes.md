# sv2v failure recipes

## Parse error from sv2v
Symptom: `Lexical error at line N` / `Parse error at line N`.
Cause: real SV syntax error, or a construct sv2v's parser doesn't
accept (rare for modern releases).
Fix: compile with a real SV simulator first (verilator --lint-only,
iverilog -g2012, or commercial). Fix the source, re-run sv2v.

## "unsupported …" warning, output still produced
Symptom: stderr says `unsupported <feature> at <loc>`.
Cause: a conversion pass declined to translate something — usually
because the construct has no Verilog-2005 equivalent (rare) or has a
known limitation.
Fix: rewrite the source. Or `--exclude=<Pass>` and accept the
unconverted construct in the output (downstream tool must handle it).

## Undefined identifier downstream
Symptom: yosys/iverilog complains `module ... not found` after sv2v.
Cause: sv2v wasn't told about the file containing that module.
Fix: pass every file in **one** sv2v invocation, or use a `-f`
filelist.

## Output explodes in size
Symptom: 100-line input becomes 5000-line output.
Cause: parameterized modules/types are duplicated per parameter set —
this is expected, since Verilog-2005 lacks SV's type system.
Fix: nothing to do; downstream tools handle the size fine.

## `read_verilog -sv` after sv2v re-errors
Symptom: passed sv2v output through `read_verilog -sv` and got a
syntax error.
Cause: stray SV-only construct sv2v emitted on purpose (rare bug) or
mixing of `-sv` mode with pure Verilog-2005 output.
Fix: drop `-sv`: `read_verilog out.v`.
