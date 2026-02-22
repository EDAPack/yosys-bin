# Yosys Pass and Target Reference

## Supported FPGA Synthesis Targets

| Command | Vendor/Family | Devices |
|---|---|---|
| `synth_ice40` | Lattice | iCE40HX, iCE40LP, iCE40UP (UltraPlus) |
| `synth_xilinx` | AMD/Xilinx | xc7 (7-series), xcup (UltraScale+), xcus (UltraScale), xcu |
| `synth_lattice` | Lattice | ECP5, MachXO2 (xo2), MachXO3 (xo3/xo3d), CrossLink-NX (lifcl), Certus-NX (lfd2nx) |
| `synth_gowin` | Gowin | GW1N, GW2A series (experimental) |
| `synth_intel` | Intel/Altera | Cyclone IV, Arria II (older families) |
| `synth_intel_alm` | Intel/Altera | Cyclone 10 GX, Arria 10, Stratix 10 (ALM-based) |
| `synth_anlogic` | Anlogic | EG4, AL3 families |
| `synth_achronix` | Achronix | speedster7t |
| `synth_efinix` | Efinix | Trion, Titanium |
| `synth_fabulous` | FaBulous | Open-source eFPGA framework |
| `synth_gatemate` | Cologne Chip | GateMate A1 |
| `synth_nanoxplore` | NanoXplore | NG-Medium, NG-Large, NG-Ultra |
| `synth_quicklogic` | QuickLogic | EOS S3, ArcticPro |

## Common Pass Sequences

### Coarse-grain only (no tech mapping, useful for equivalence checking)

```yoscrypt
read_verilog -sv design.sv
hierarchy -check -top my_top
proc; opt; memory; opt; fsm; opt
techmap; opt_clean
stat
write_rtlil coarse.rtlil
```

### ASIC cell-library flow

```yoscrypt
read_verilog design.v
read_liberty -lib tech/cells.lib
hierarchy -check -top my_top
synth -top my_top
dfflibmap -liberty tech/cells.lib
abc -D 10000 -liberty tech/cells.lib   # -D sets max delay in ps
opt_clean -purge
stat -liberty tech/cells.lib
write_verilog netlist.v
write_edif netlist.edif
```

### Formal equivalence check between two designs

```yoscrypt
read_verilog original.v
hierarchy -top original
copy original orig_copy
rename original mapped
techmap -map my_techmap.v mapped
miter -equiv -make_assert -make_outputs orig_copy mapped miter
flatten miter
sat -verify -prove-asserts miter
```

### Formal property checking preparation (for smtbmc)

```yoscrypt
read_verilog -formal -sv my_module.sv
hierarchy -check -top my_module
proc; opt
memory -nordff -nomap; opt -fast
write_smt2 -bv -mem -wires my_module.smt2
```

Then run:
```bash
yosys-smtbmc --depth 20 my_module.smt2
```

## Optimization Pass Details

### `opt` macro — sub-passes called in order

1. `opt_expr` — constant folding, simple expression rewriting
2. `opt_merge` — merge equivalent cells (common subexpression elimination)
3. `opt_muxtree` — prune unreachable branches in mux trees
4. `opt_reduce` — simplify logic reductions
5. `opt_share` — merge shareable resources
6. `opt_clean` — remove dangling wires and unused cells

Run `opt -fast` to skip the more expensive passes.  Run `opt_clean -purge` at
the end to aggressively clean before writing output.

### `proc` macro — sub-passes called in order

1. `proc_clean` — remove empty processes
2. `proc_rmdead` — remove dead branches
3. `proc_prune` — prune unreachable statements
4. `proc_init` — handle `initial` blocks
5. `proc_arst` — handle asynchronous resets
6. `proc_rom` — detect ROMs
7. `proc_mux` — convert `if`/`case` to `$mux` cells
8. `proc_dlatch` — detect level-sensitive latches
9. `proc_dff` — detect flip-flops
10. `proc_memwr` — handle memory writes
11. `proc_clean` — final cleanup

### `memory` macro — sub-passes called in order

1. `memory_dff` — merge registers into memory read/write ports
2. `memory_collect` — merge all ports of a memory into one multi-port cell
3. `memory_bram` — infer BRAMs (when `-bram` map file provided)
4. `memory_map` — convert multi-port memories to address-decoder + register logic

Use `memory -nordff -nomap` for formal verification (keeps memories as cells).

## ABC Integration

### `abc` vs `abc9`

- `abc` — unit delay model, simpler, faster, good for iCE40 HX/LP
- `abc9` — generalised delay model with box timing, better quality for
  complex designs; requires `specify` blocks in cell models

### Useful `abc` options

```yoscrypt
abc -liberty cells.lib              # ASIC cell mapping
abc -lut 4                          # 4-input LUT mapping
abc -lut 6                          # 6-input LUT (Xilinx/Intel)
abc -D 10000                        # set max delay target (ps)
abc -dff                            # include FF retiming
abc -g cla                          # use carry-lookahead adder
```

## Output Format Notes

| Format | Command | Use |
|---|---|---|
| JSON | `write_json out.json` | nextpnr, design inspection |
| Verilog netlist | `write_verilog out.v` | simulation, downstream tools |
| BLIF | `write_blif out.blif` | ABC, other academic tools |
| EDIF | `write_edif out.edif` | legacy FPGA tools, ISE/Vivado import |
| RTLIL | `write_rtlil out.rtlil` | checkpoint, re-read with `read_rtlil` |
| SMT2 | `write_smt2 out.smt2` | smtbmc formal verification |
| SPICE | `write_spice out.sp` | analog/mixed-signal simulation |

## Selection Language Quick Reference

Used with `select`, `show`, `clean`, and many other commands:

```
t:<type>      match cells by type, e.g. t:$dff, t:SB_LUT4, t:*mux*
w:<wire>      match wires by name
i:*           all module inputs
o:*           all module outputs
m:<module>    restrict scope to module
%ci           cone of cells driving current selection
%co           cone of cells driven by current selection
%d            add driver cells of current selection
@<name>       use named selection
%%            select all cells in result of last binary op
```

Example:
```yoscrypt
select -set state_ffs t:$dff   # select all DFFs
show @state_ffs                # display them
```

## Environment Variables

| Variable | Effect |
|---|---|
| `YOSYS_NOFORK` | Disable fork-based parallelism |
| `YOSYS_TMPDIR` | Override temporary directory |
| `ABC` | Path to external ABC binary |
| `YOSYS_ABC` | Alternative ABC path |
