---
name: sv2v
description: SystemVerilog → Verilog-2005 transpiler. Reads modern SV (interfaces, packages, structs, enums, always_ff, parameterized types) and emits portable Verilog-2005 that any synthesizer or simulator can consume — including yosys, iverilog, and old commercial tools.
license: BSD-3-Clause
version: "0.0.13"
---

# sv2v — Agent Skill

## When to use this skill
- A downstream tool (older yosys frontend, `iverilog -g2005`, vendor
  simulator) chokes on a SystemVerilog construct.
- The user has SV source and wants to feed `yosys` (without the slang
  plugin) or `iverilog`.
- An error like "unexpected TOK_INTERFACE" or "syntax error" in a tool
  that only fully supports Verilog-2005.

Prefer `read_slang` (the slang plugin in `yosys-bin`) when the goal is
synthesis and slang accepts the source — slang is closer to a real SV
compiler. Reach for sv2v when you need a *file*, not just a yosys
import.

## Core mental model
sv2v is a **batch translator**: in → SV files; out → one combined
Verilog-2005 file (or `-` for stdout). It does not run any simulator
or synthesizer. The output is meant to be **lossless for synthesis
semantics**, not human-pretty — expect long signal names and
flattened types.

Two principles to remember:
1. `sv2v` processes the *entire compilation unit* at once. Pass every
   file your design depends on (packages, interfaces) in a single
   invocation, otherwise references won't resolve.
2. Macros, includes, and `+define+`s must be handed to sv2v
   explicitly (`-D`, `-I`) — sv2v does not pick them up from
   environment variables or filelists by default.

## Quick start
```sh
# Translate one or more SV files to a single Verilog-2005 file.
sv2v top.sv pkg.sv > out.v
```

## Common tasks
- **Translate to stdout →** `sv2v top.sv`
- **Translate to a file →** `sv2v -w out.v top.sv pkg.sv`
- **Use an `+define+` →** `sv2v -DSYNTHESIS top.sv > out.v`
- **Add an include path →** `sv2v -Iincludes top.sv > out.v`
- **Read a filelist (`.f`) →** `sv2v -f files.f > out.v`
- **Translate then feed yosys →**
  `sv2v top.sv > top.v && yosys -p 'read_verilog top.v; synth_ice40 -top top -json out.json'`
- **Keep top-level only (drop unused modules) →** `sv2v --top top top.sv > out.v`

## Flags you actually need
| Flag | Effect | When |
|---|---|---|
| `-D <macro>[=val]` | Define a macro. | Match the same defines your simulator uses. |
| `-I <dir>` | Add include search path. | Resolve `` `include `` directives. |
| `-w <file>` | Write to file instead of stdout. | Multi-output flows. |
| `-f <filelist>` | Read file list. | Large designs. |
| `--top <name>` | Discard modules not reachable from `<name>`. | Smaller output for tools that complain about extras. |
| `--exclude=<feature>` | Skip a conversion pass (e.g. `--exclude=Always`). | Workarounds when a conversion is buggy or unwanted. |
| `--verbose` | Print conversion passes as they run. | Debug. |
| `--write=adjacent` | Write each input `foo.sv` to `foo.v` beside it. | Per-file workflow. |
| `--bsv` | Accept Bluespec SystemVerilog dialect quirks. | BSV input. |

## Failure recipes
| Symptom | Likely cause | Fix |
|---|---|---|
| `Lexical error at line N` / `Parse error` | Real SV syntax error in source. | Compile with a real SV simulator first to find the bug. |
| Output is empty | All modules pruned by `--top` or input file empty. | Drop `--top` to confirm; re-check filename typos. |
| Undefined identifier in downstream tool, but it's defined in another SV file | Sv2v wasn't given that file. | Pass all related files in a single sv2v invocation. |
| `unsupported …` warning | sv2v hit a construct it can't translate. | Rewrite the source, or `--exclude` if the warning is benign. |
| Yosys downstream still complains | sv2v emits Verilog-2005, but yosys defaults to that already. Re-run with `read_verilog` (no `-sv`). | Drop `-sv` from `read_verilog`. |

## Interop with edapack
- **Upstream of yosys** when the slang plugin can't parse the source
  or you want a portable `.v` artifact.
- **Upstream of iverilog** for older simulators that lack SV support.
- **Standalone**: useful even outside edapack, e.g. to feed commercial
  tools restricted to Verilog-2005.

## References
See `references/docs-index.md`.

## Examples
- `examples/01-hello/` — interface + always_ff → Verilog-2005.
