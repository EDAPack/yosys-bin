---
name: yosys-synthesis
description: >
  RTL synthesis and formal preparation using Yosys. Use when working with
  DV Flow yosys.* tasks, writing .ys synthesis scripts, interpreting Yosys
  logs and stat output, mapping designs to FPGA or ASIC cell libraries, or
  preparing designs for formal verification with sby/smtbmc.
license: Apache-2.0
metadata:
  author: dv-flow
  version: "1.0"
  package: dv-flow-libyosys
compatibility: >
  Requires yosys on PATH. DV Flow tasks (yosys.*) require dv-flow-mgr and
  the dv-flow-libyosys Python package installed.
---

# Yosys Synthesis Skill

Yosys is an open-source RTL synthesis framework. It reads Verilog or
SystemVerilog, performs a configurable sequence of optimisation passes, maps
the result to a target technology (FPGA or ASIC cell library), and writes
netlists in multiple formats (JSON, Verilog, BLIF, EDIF, RTLIL, SMT2).

This skill covers three entry points:

1. **DV Flow tasks** (`yosys.*`) – YAML-configured, data-flow-driven synthesis
2. **Raw Yosys scripts** (`.ys` files) – imperative command sequences
3. **Log and stat interpretation** – reading output, diagnosing errors

---

## 1. DV Flow Tasks (`yosys.*`)

All tasks live in the `yosys` DV Flow package.  Import it and connect tasks
with `needs` edges.  RTL sources flow via standard `std.FileSet` filetypes;
cell libraries flow via the `libertyLib` filetype.

### Import

```yaml
package:
  name: my_project
  imports:
    - name: yosys
```

### Core tasks

| Task | Description | Key parameters |
|---|---|---|
| `yosys.Synth` | Technology-independent synthesis | `top`, `output_format`, `flatten`, `nofsm`, `noabc`, `retime` |
| `yosys.SynthIce40` | Lattice iCE40 FPGA | `top`, `device` (hx/lp/u), `output_format`, `abc9`, `nobram`, `dsp` |
| `yosys.SynthXilinx` | Xilinx 7-series/UltraScale | `top`, `family` (xc7/xcup/xcus), `output_format`, `nobram`, `nodsp`, `noiopad` |
| `yosys.SynthLattice` | Lattice ECP5/MachXO2/3/CrossLink-NX | `top`, `family` (ecp5/xo2/xo3/xo3d/lifcl/lfd2nx), `output_format` |
| `yosys.SynthGowin` | Gowin FPGA (experimental) | `top`, `output_format` (json/verilog) |
| `yosys.FormalPrepare` | Prepare SMT2 model for formal | `top`, `bv`, `mem`, `wires` |
| `yosys.Script` | Run arbitrary `.ys` script | `script`, `read_rtl`, `output_format` |

### Output filetypes

| Filetype | Description |
|---|---|
| `yosysNetlist` | Synthesized netlist (JSON/Verilog/BLIF/EDIF) |
| `yosysSMT2` | SMT2 model for smtbmc/sby formal tools |

### Example: FPGA synthesis (iCE40)

```yaml
package:
  name: my_fpga
  imports:
    - name: yosys

  tasks:
    - name: rtl
      uses: std.FileSet
      with:
        type: verilogSource
        include: "src/**/*.v"

    - name: synth
      uses: yosys.SynthIce40
      needs: [rtl]
      with:
        top: blink
        device: hx
        output_format: json
```

### Example: ASIC synthesis with liberty cell library

```yaml
tasks:
  - name: rtl
    uses: std.FileSet
    with:
      type: verilogSource
      include: "src/**/*.v"

  - name: lib
    uses: std.FileSet
    with:
      type: libertyLib
      include: "tech/osu035_stdcells.lib"

  - name: synth
    uses: yosys.Synth
    needs: [rtl, lib]
    with:
      top: my_top
      output_format: verilog
      # dfflibmap + abc run automatically when a libertyLib is present
```

### Example: Formal verification preparation

```yaml
tasks:
  - name: rtl
    uses: std.FileSet
    with:
      type: systemVerilogSource
      include: "src/**/*.sv"

  - name: model
    uses: yosys.FormalPrepare
    needs: [rtl]
    with:
      top: my_module
      bv: true
      mem: true
      wires: true
      # Outputs a yosysSMT2 fileset consumed by smtbmc / sby
```

### Example: Arbitrary script with RTL auto-load

```yaml
tasks:
  - name: dump
    uses: yosys.Script
    needs: [rtl]
    with:
      read_rtl: true          # reads all upstream RTL sources first
      output_format: verilog  # collects netlist.verilog as output
      script: |
        synth -flatten -top my_top
        write_verilog netlist.verilog
```

---

## 2. Writing Yosys Scripts (`.ys`)

A Yosys script is a sequence of commands, one per line.  Comments start with
`#`.  Commands are separated by newlines or semicolons (semicolon **must** be
followed by a space).

### Canonical synthesis pipeline

```yoscrypt
# 1. Read sources
read_verilog -sv src/top.sv src/alu.sv
read_verilog -incdir src/inc

# 2. Elaborate
hierarchy -check -top top

# 3. Convert always-blocks to RTL cells
proc

# 4. Optimise
opt

# 5. Handle memories
memory; opt

# 6. Handle FSMs
fsm; opt

# 7. Map to generic gates
techmap; opt

# 8. Report area before mapping
stat

# 9. Technology mapping (ASIC: liberty, FPGA: LUT/abc)
# ASIC:
dfflibmap -liberty tech/cells.lib
abc -liberty tech/cells.lib
# FPGA (generic k-LUT):
# synth -lut 4

opt_clean -purge

# 10. Statistics with cell area
stat -liberty tech/cells.lib

# 11. Write output
write_verilog netlist.v
```

### Target-specific single-command synthesis

For FPGA targets, use the appropriate `synth_*` command, which internally
runs the full pipeline.

```yoscrypt
# iCE40
read_verilog -sv top.sv
synth_ice40 -top top -json top.json

# Xilinx 7-series
read_verilog -sv top.sv
synth_xilinx -family xc7 -top top -json top.json

# Lattice ECP5
read_verilog -sv top.sv
synth_lattice -family ecp5 -top top -json top.json
```

### Reading sources

| Command | Use case |
|---|---|
| `read_verilog file.v` | Verilog-2005 source |
| `read_verilog -sv file.sv` | SystemVerilog source |
| `read_verilog -formal file.sv` | SVA formal constructs enabled |
| `read_verilog -incdir path/` | Add include directory |
| `read_verilog -lib cells.v` | Read as black-box library |
| `read_liberty -lib tech.lib` | ASIC liberty cell library |
| `read_rtlil design.rtlil` | Load saved RTLIL design |

### Key passes reference

| Pass | Purpose |
|---|---|
| `hierarchy -check -top <mod>` | Elaborate hierarchy, check for missing modules |
| `proc` | Convert always-blocks to RTL MUX/FF cells |
| `opt` | Const folding, dead-code elimination, cleanup (run after major passes) |
| `memory` | Infer block RAMs, convert memories to logic |
| `fsm` | Detect, optimise, and re-encode state machines |
| `techmap` | Map RTL cells to gate-level primitives |
| `dfflibmap -liberty <lib>` | Map flip-flops to liberty cells |
| `abc -liberty <lib>` | Map combinational logic to liberty cells |
| `abc -lut <k>` | Map to k-input LUTs |
| `abc9` | Improved ABC flow (better quality, needed for iCE40 -abc9) |
| `opt_clean -purge` | Remove dangling wires and unused cells |
| `flatten` | Inline all submodule instances into one module |
| `stat` | Print cell and wire counts |
| `stat -liberty <lib>` | Include cell areas from liberty |
| `write_json out.json` | Write JSON netlist |
| `write_verilog out.v` | Write Verilog netlist |
| `write_blif out.blif` | Write BLIF netlist |
| `write_edif out.edif` | Write EDIF netlist |
| `write_smt2 out.smt2` | Write SMT2 model for formal tools |
| `write_rtlil out.rtlil` | Write RTLIL (Yosys internal format) |

### Partial synthesis with `-run`

All `synth_*` commands accept `-run <from>:<to>` to run a sub-range of their
internal script.  Use `yosys -h synth_ice40` (etc.) to see the label names.

```yoscrypt
# Run only up through coarse-grain synthesis (no tech mapping)
synth_ice40 -top fifo -run begin:map_ram
# Then continue from a checkpoint:
synth_ice40 -top fifo -run map_ram:
```

### Formal preparation

```yoscrypt
read_verilog -formal -sv my_module.sv
hierarchy -check -top my_module
proc; opt
memory -nordff -nomap; opt -fast
write_smt2 -bv -mem -wires my_module.smt2
```

For sby (Symbiyosys), write a `.sby` file and run `sby -f design.sby`.

---

## 3. Log and Stat Interpretation

### Typical log structure

Yosys numbers each executed pass.  Normal output looks like:

```
1. Executing VERILOG_FRONTEND.
...
2. Executing HIERARCHY pass (hierarchy check).
...
3. Executing PROC pass (convert processes to netlists).
...
```

### `stat` output

```
=== my_top ===

   Number of wires:               142
   Number of wire bits:           814
   Number of public wires:         18
   Number of public wire bits:    128
   Number of memories:              0
   Number of memory bits:           0
   Number of processes:             0
   Number of cells:               127
     SB_CARRY                       6
     SB_DFFE                        8
     SB_LUT4                      113
```

- **Cells count** — total gate count (LUTs, FFs, carry chains, DSPs, BRAMs)
- **Wire bits** — total signal width; useful for design-size tracking
- **After `-liberty`** — `Chip area for module`: area in library units

### Common errors and fixes

| Error message | Cause | Fix |
|---|---|---|
| `ERROR: Module \foo referenced in module \bar does not exist.` | Missing source file or submodule | Add `read_verilog` for the missing file; check hierarchy |
| `ERROR: Multiple modules with name \foo.` | Same module read twice | Remove duplicate `read_verilog` call |
| `ERROR: syntax error, unexpected ...` | Unsupported Verilog/SV construct | Use `-sv` flag for SV; check Yosys SV support limitations |
| `Warning: Yosys has only limited support for tri-state logic.` | `tri`/`inout` nets | Refactor to use enable + driver logic |
| `Warning: found wait statement ...` | `wait` in always block | Remove non-synthesizable `wait`; use clocked logic |
| `Warning: latch inferred for ...` | Combinational latch inferred | Add a default assignment in `if`/`case`; use `(* nolatches *)` |
| `Warning: Replacing memory \mem with list of registers.` | `mem2reg` conversion | Expected for small memories; use `-nordff` in `memory` for formal |
| `Warning: Module \foo is used but not defined.` | Missing black-box definition | Add `-lib` read for the module or define a stub |
| `ABC: Warning: No mapping was found.` | ABC failed to map logic | Check liberty file is valid; try `abc -lut 4` instead |

### Interpreting synthesis quality

- **High LUT count vs expected**: Check if FSMs are encoded one-hot unintentionally; run `fsm` before `techmap`.
- **Many latches inferred**: Add `(* nolatches *)` attribute or default values.
- **Design unchanged after `opt`**: Passes ran but made no changes — normal and expected.
- **`hierarchy -check` errors**: Always fix these before running synthesis; they indicate structural bugs.

---

## 4. Verilog Attributes for Synthesis Control

```verilog
(* fsm_encoding = "one-hot" *)  // or "binary", "auto", "none"
reg [2:0] state;

(* keep *)                       // prevent opt from removing this signal
wire debug_out;

(* mem2reg *)                    // force memory → registers
reg [7:0] my_mem [0:15];

(* blackbox *)                   // treat as black box (no internal logic)
module ip_core (...);

(* full_case, parallel_case *)   // case statement optimisation hints
case (sel) ...
```

---

## 5. Troubleshooting Checklist

1. **Run `hierarchy -check -top <top>` first** — fix all module-not-found errors before proceeding.
2. **Run `proc` before `opt`** — most passes cannot operate on designs with unprocessed always-blocks.
3. **Use `opt` liberally** — run after each major pass to keep the design clean.
4. **Check `stat` before and after mapping** — large cell-count increases after techmap suggest unintended logic.
5. **Inspect with `write_verilog -noattr`** — readable intermediate netlist for debugging.
6. **Use `-run begin:map_ram`** — stop at intermediate labels to inspect partial results.

See [references/REFERENCE.md](references/REFERENCE.md) for a complete pass reference and supported FPGA targets.
