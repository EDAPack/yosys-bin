# yosys CLI cheatsheet

Top-level invocation flags only. Commands run *inside* yosys (after
`-p` or in a script) are listed in `SKILL.md` under "Flags you actually
need" and in full in the upstream manual (see `docs-index.md`).

## Invocation patterns
```
yosys                              # interactive shell
yosys script.ys                    # run script file
yosys -s script.ys                 # same, explicit
yosys -p 'cmd1; cmd2; cmd3'        # inline commands
yosys -p 'cmd' -p 'cmd' script.ys  # multiple -p, then a script
```

## Flags
| Flag | Effect |
|---|---|
| `-Q` | Suppress version banner. |
| `-q` | Quiet (errors + warnings only). |
| `-qq` | Very quiet (errors only). |
| `-v <N>` | Verbosity level (0–9). |
| `-t` | Print execution times. |
| `-l <file>` | Tee output to log file. |
| `-L <file>` | Log only (no stdout). |
| `-o <file>` | Append `write_verilog <file>` at the end of the script. |
| `-b <fmt>` | Use `<fmt>` as the backend for `-o` (e.g. `-b 'verilog -noattr'`). |
| `-f <fmt>` | Use `<fmt>` as the frontend for positional files. |
| `-H` | List built-in commands and exit. |
| `-h <cmd>` | Print help for command and exit. |
| `-T` | Print Tcl-style backtrace on error. |
| `-D <macro>[=val]` | Verilog define passed to `read_verilog`. |
| `-E <depfile>` | Emit make-style dependency file (frontend reads). |
| `-g` | Enable internal debug logging. |
| `-A` | Abort instead of exit on error (drops core for debugger). |
| `-X` | Track call stack for log messages. |

## Useful combinations
- `yosys -q -l build.log script.ys` — CI-friendly: quiet stdout, full
  log on disk.
- `yosys -p 'read_verilog -sv top.sv; synth_ice40 -top top -json o.json'`
  — single-shot, no script file needed.
- `yosys -p 'read_verilog top.v' -p 'hierarchy -top top' -p 'stat'` —
  build up the design across multiple `-p` (each ends with implicit `;`).
