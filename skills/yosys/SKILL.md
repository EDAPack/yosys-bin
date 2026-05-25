---
name: yosys
description: Open-source RTL synthesis framework — elaborate Verilog/SystemVerilog, run technology-independent and target-specific synthesis passes, emit netlists for FPGA (iCE40, ECP5, Nexus, Xilinx via prjxray) and ASIC flows.
license: ISC
version: "0.50"
---

# yosys — Agent Skill

## When to use this skill
- The user has Verilog/SystemVerilog and needs a gate-level netlist
  (`.json`, `.blif`, `.edif`, structural `.v`) — usually as input to
  `nextpnr-*`, `vpr`, OpenROAD, or for formal analysis.
- The user asks for "synthesis", "elaboration to gates", "tech mapping",
  "flatten", "show me the gates for this design", "generate a netlist".
- A tool downstream of yosys (nextpnr, sby, OpenSTA) failed and the
  netlist needs regenerating.
- The user wants to inspect a design's structure (`show`, `stat`) or
  apply formal-friendly transforms (`prep -top`, `flatten`).

Do **not** use yosys for simulation — reach for `iverilog` + `vvp` or
`verilator` instead. Yosys can simulate via `sim`, but that's a niche.

## Core mental model
Yosys is a **script-driven shell**. Every action is a *command*; commands
operate on the in-memory design database (RTLIL). You either:

1. Pass commands inline: `yosys -p 'read_verilog foo.v; synth_ice40; write_json out.json'`
2. Run a script file: `yosys script.ys` (where `.ys` is a newline-
   separated list of the same commands).
3. Use an interactive shell: `yosys` then type commands.

The canonical pipeline is **read → elaborate (`hierarchy -top`) →
high-level passes (`proc`, `opt`, `fsm`, `memory`) → tech mapping
(`synth_<arch>` macro) → write_<format>**. Most users invoke a
target-specific macro like `synth_ice40` / `synth_ecp5` / `synth_xilinx`
that wraps the whole pipeline; reach for individual passes only when
debugging or customizing.

Yosys is *not* tolerant of every Verilog dialect. The built-in frontend
covers most Verilog-2005 and a useful SystemVerilog subset. For richer
SV (interfaces, full assertions, complex generate), prefer
`read_slang -f` (built into this release via the **yosys-slang** plugin
— invoke `plugin -i slang` first if not auto-loaded) or pre-process
with **sv2v** (separate skill).

## Quick start
```sh
# Elaborate one file and dump a JSON netlist suitable for nextpnr-ice40.
yosys -p 'read_verilog top.v; synth_ice40 -top top -json top.json'
```

## Common tasks
- **iCE40 synthesis →** `yosys -p 'read_verilog *.v; synth_ice40 -top <top> -json out.json'`
- **ECP5 synthesis →** `yosys -p 'read_verilog *.v; synth_ecp5 -top <top> -json out.json'`
- **Generic (no target) synth, useful for inspection →** `yosys -p 'read_verilog *.v; synth -top <top>; write_verilog out.v'`
- **SystemVerilog via slang →** `yosys -p 'plugin -i slang; read_slang -f top.sv; synth_ice40 -top top -json out.json'`
- **Run a script file →** `yosys flow.ys`
- **Print design statistics →** `yosys -p 'read_verilog *.v; hierarchy -top <top>; proc; opt; stat'`
- **Visualize a module (GraphViz) →** `yosys -p 'read_verilog foo.v; hierarchy -top foo; proc; show foo'`
- **Equivalence-check before/after a transform →** `yosys -p 'read_verilog ref.v; prep -top top; design -stash gold; read_verilog mod.v; prep -top top; design -stash gate; design -copy-from gold -as gold top; design -copy-from gate -as gate top; equiv_make gold gate equiv; equiv_simple; equiv_status'`

## Flags you actually need
| Flag | Effect | When |
|---|---|---|
| `-p '<cmd; cmd>'` | Run inline commands. Multiple `-p` allowed; they run in order. | Most invocations. |
| `-s <script.ys>` | Run a script file (same as positional arg in newer releases). | Long flows. |
| `-q` / `-qq` | Quiet / very quiet. | CI logs. |
| `-l <log>` | Tee output to log file. | CI / debugging. |
| `-T` | Print backtrace on error. | Debugging crashes. |
| `-D <macro>[=val]` | Verilog `define` for the frontend. | Conditional RTL. |
| `-E <depfile>` | Write make-style dependency file. | Build-system integration. |

Common *commands* (not flags) an agent should know:
- `read_verilog [-sv] [-defer] file.v` — read Verilog/SV.
- `hierarchy -top <name>` — set top, elaborate parameter overrides, prune.
- `proc` / `opt` / `fsm` / `memory` — high-level passes (`synth` runs these).
- `synth -top <name>` — generic synthesis, no tech mapping.
- `synth_ice40 -top <name> [-dsp] [-json out.json]` — full iCE40 flow.
- `synth_ecp5 -top <name> [-json out.json]` — full ECP5 flow.
- `flatten` — collapse hierarchy.
- `write_json` / `write_verilog` / `write_blif` / `write_aiger`.
- `stat` — area/cell counts. `show -prefix <p>` — GraphViz.

## Failure recipes
| Symptom (stderr fragment) | Likely cause | Fix |
|---|---|---|
| `ERROR: Module \`foo' not found!` | `-top` names a module yosys didn't read or that was renamed by parameters. | Verify `read_verilog` included the file; re-check the module name; if parameterized, set `-chparam`. |
| `ERROR: syntax error, unexpected ... at file.sv:NN` | SV construct unsupported by built-in frontend. | Use `read_slang` (plugin -i slang) or preprocess with `sv2v`. |
| `ERROR: Failed to import cell ...` after `synth_ice40` | Black-box / unsupported primitive for the target. | Provide a model, use `-noflatten` to inspect, or pick the right `synth_*`. |
| `Warning: Wire ... is used but has no driver.` | Missing file, typo, or unconnected port. | Re-check `read_verilog` file list; check port direction. |
| `read_verilog` succeeds then `hierarchy -check` fails on instantiation | Module read but parameters/ports mismatched at instance. | Add `-chparam`; check generate scope. |

## Interop with edapack
- **Downstream of yosys.** Output `-json` netlists feed `nextpnr-ice40`,
  `nextpnr-ecp5`, `nextpnr-nexus` (see `nextpnr-bin` skill). BLIF feeds
  `arachne-pnr`. Structural Verilog feeds OpenROAD / OpenSTA.
- **Upstream of yosys.** `sv2v` (this package) translates SV to
  Verilog-2005 when the slang plugin can't parse it. `verilator` only
  *lints/simulates* — it does not feed yosys.
- **Sibling.** `sby` (this package) wraps yosys for formal verification;
  its task files contain inline yosys command blocks. See the `sby`
  skill.

## References
See `references/docs-index.md` and `references/cli-cheatsheet.md`.

## Examples
- `examples/01-hello/` — single-module Verilog → JSON netlist.
- `examples/02-ice40-synth/` — small design through `synth_ice40` with
  stats and write_json.
- `examples/03-script-file/` — equivalent flow as a `.ys` script.
