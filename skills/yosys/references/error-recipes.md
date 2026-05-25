# yosys failure recipes

Pattern-match real stderr fragments to a diagnosis and fix. Add new
entries as you encounter them; keep the symptom verbatim so an agent
can grep for it.

## "Module not found"
Symptom:
```
ERROR: Module `\foo' not found!
```
Cause: `hierarchy -top foo` (or `synth_* -top foo`) was called but
`read_verilog` did not parse a module by that name — or the module's
name was changed by parameter elaboration (e.g. `foo$paramX=...`).

Fix:
- Confirm the file list passed to `read_verilog` actually contains the
  module: `yosys -p 'read_verilog *.v; ls'` lists all loaded modules.
- For parameterized tops use `hierarchy -top foo -chparam WIDTH 8`.
- If the design uses package/interface from another file, read it
  *first*.

## "syntax error" in SystemVerilog
Symptom:
```
ERROR: syntax error, unexpected TOK_STRUCT, expecting TOK_ID at file.sv:NN
```
Cause: built-in `read_verilog -sv` does not implement the construct.

Fix (in this order):
1. Try the slang frontend: `plugin -i slang; read_slang -f file.sv`.
2. If slang also fails, preprocess with `sv2v`:
   `sv2v file.sv > file.v && yosys -p 'read_verilog file.v; ...'`.

## "Wire has no driver"
Symptom:
```
Warning: Wire top.\sig is used but has no driver.
```
Cause: typo, missing file in `read_verilog`, unconnected instance
port, or an `always` block that doesn't assign in every branch (latch).

Fix: search for `sig` in the source; if it's a register, ensure all
branches of the `always` assign it (or add a default at top).

## "Found logic loop" after `synth`
Symptom:
```
ERROR: Found 1 logic loop(s) in module top.
```
Cause: combinational feedback — most often an `assign` chain or an
`always @*` that reads what it writes.

Fix: `yosys -p '... ; scc -select'` selects the loop; `show -selected`
visualizes it. Add a register or break the chain.

## "synth_ice40: failed to import cell"
Symptom:
```
ERROR: Cell `top.\u_dsp' (type $mul) cannot be mapped to iCE40.
```
Cause: design uses a primitive (large multiplier, BRAM shape) that the
target macro doesn't handle by default.

Fix: pass `synth_ice40 -dsp` to use DSP blocks, or restructure the
RTL. For BRAM shape issues, set `(* ram_style = "block" *)` or
`"distributed"` on the array.

## Crash without backtrace
Run with `-T` to get a Tcl-style backtrace, and `-g` for verbose
internal logging. File issues at https://github.com/YosysHQ/yosys/issues
with the minimal `.ys` that reproduces.
