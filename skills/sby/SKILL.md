---
name: sby
description: SymbiYosys — driver for yosys-based formal verification flows (bounded model check, k-induction, cover, equivalence). Reads a .sby task file describing engines, options, and the design, then runs the chosen engines and reports pass/fail with a counterexample trace.
license: ISC
version: "0.50"
---

# sby (SymbiYosys) — Agent Skill

## When to use this skill
- The user wants to **prove** something about RTL (assertion never
  fires, invariant always holds, two designs are equivalent) — not
  just simulate it.
- The user mentions "formal", "model check", "BMC", "k-induction",
  "cover", "assume/assert", or has SVA `assert property` statements.
- A bug evaded simulation and the user wants exhaustive coverage of a
  bounded depth.

For *simulation*, use `iverilog`/`verilator` instead. For *netlist*
equivalence checks where you already have two Verilog files, you can
use yosys's `equiv_*` commands directly without sby — but sby's
`mode prove` automates the same flow.

## Core mental model
sby is a **task-file runner** that orchestrates yosys + a backend
solver. You write a `.sby` file in an INI-like format with sections:

```
[tasks]
bmc cover prove

[options]
mode bmc
depth 20

[engines]
smtbmc boolector

[script]
read -formal top.sv
prep -top top

[files]
top.sv
```

sby invokes yosys with the `[script]` block to convert RTL → AIGER/
SMT, then runs the solver listed in `[engines]`. Results land in a
work directory `<task>/` containing `logfile.txt`, status,
and (if a property failed) a VCD counterexample under
`engine_0/trace.vcd`.

The three primary **modes**:
- `bmc` — bounded model check: explore all states reachable in
  ≤`depth` cycles; fast, finds shallow bugs.
- `prove` — k-induction: tries to *prove* assertions for unbounded
  time. Requires good `assume` statements about reachability.
- `cover` — find a trace that *reaches* each `cover` statement.

## Quick start
```sh
# Run all tasks defined in design.sby in a work directory next to it.
sby -f design.sby
```

`-f` forces deletion of any prior work directory. Drop it to refuse
overwriting prior results.

## Common tasks
- **Run a specific task →** `sby -f design.sby bmc`
- **Use a different work directory →** `sby -f -d /tmp/work design.sby`
- **Dump SMT2 instead of solving (for debugging) →** add
  `[engines]\nsmtbmc dump` to the task file.
- **Inspect counterexample VCD →** open
  `<task>/engine_0/trace.vcd` in GTKWave.
- **Equivalence check two RTL files →** mode `prove` with both files
  in `[files]` and a `miter` script — see upstream
  `sby/examples/equiv` (link in docs-index).
- **Cover-driven testbench generation →** mode `cover` produces
  traces that hit every `cover()` — useful as seeds for sim.

## Flags you actually need
| Flag | Effect | When |
|---|---|---|
| `-f` | Force: delete existing work directory first. | Most iterative runs. |
| `-d <dir>` | Override the default work-dir location. | Keep work dirs out of source tree. |
| `-t` | Time individual engine steps. | Performance debugging. |
| `-T <task>` | Run only the named task. (Or: pass task names as positional args.) | Multi-task `.sby` files. |
| `--yosys <path>` | Use a specific yosys binary. | Matched yosys version. |
| `--prefix <s>` | Prefix log lines with `<s>`. | Parallel-task logs. |
| `--dump-cfg` | Print the parsed config and exit. | Debugging `.sby` syntax. |

## .sby file sections (cheat sheet)
| Section | Purpose |
|---|---|
| `[tasks]` | Define task names (each line = task + optional groups). |
| `[options]` | Per-task: `mode`, `depth`, `multiclock on`, `wait on`. |
| `[engines]` | One per line: `smtbmc <solver>`, `abc bmc3`, `aiger suprove`, etc. |
| `[script]` | yosys commands to elaborate the design. Always end with `prep -top <top>` (or `prep -top <top> -flatten`). |
| `[file <name>]` | Inline file: contents go directly into work dir. |
| `[files]` | Paths to copy into work dir (resolved relative to `.sby`). |

Use `~~`-prefixed lines inside a section to mark task-specific
overrides (e.g. `~bmc: depth 50`).

## Failure recipes
| Symptom | Likely cause | Fix |
|---|---|---|
| `ERROR: No such mode '...'` | Typo in `[options] mode`. | Use `bmc`, `prove`, `cover`, `live`, `equiv`. |
| Task ends with `FAIL` and a VCD | Counterexample found. | Open the VCD; the cycle of failure equals the engine's reported step. |
| `ERROR: Module ... not found` (from yosys inside sby) | `[script]` missed a file. | Add to `[files]` and re-read in `[script]`. |
| `ERROR: Couldn't find solver 'boolector'` | Solver not on PATH. | This release bundles boolector; ensure `${pkg}/bin` is on PATH. Other solvers (z3, yices) may also work; try `smtbmc z3`. |
| `prove` mode says `UNKNOWN` | k-induction can't close: missing invariants. | Add `assume property` constraints to restrict the state space, or strengthen with auxiliary invariants. |

## Interop with edapack
- **Uses yosys** internally to elaborate the design — the same yosys
  binary shipped in this package. See the `yosys` skill for RTL/SV
  reading caveats.
- **Solvers** — this package bundles `boolector`. `z3` / `yices` /
  `cvc4` can be used if installed separately.
- **Output VCDs** view in GTKWave (not in this package).

## References
See `references/docs-index.md`.

## Examples
- `examples/01-bmc/` — minimal BMC on a 3-bit counter with an assertion.
