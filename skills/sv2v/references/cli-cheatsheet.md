# sv2v CLI cheatsheet

```
sv2v [flags] file1.sv [file2.sv ...]
```

| Flag | Effect |
|---|---|
| `-D <m>[=v]` / `--define=<m>[=v]` | Verilog define. |
| `-I <d>` / `--incdir=<d>` | Include search path. |
| `-f <file>` | Read a filelist. |
| `-y <d>` / `--libdir=<d>` | Library dir for `-y`-style lookup. |
| `-E <ext>` | Treat files with `<ext>` as input. |
| `-w <file>` / `--write=<file>` | Write to a single file. |
| `--write=adjacent` | Write each `foo.sv` to `foo.v` next to it. |
| `--write=stdout` | (Default) emit to stdout. |
| `--top <name>` | Prune modules not reachable from `<name>`. |
| `--exclude=<X>` | Skip a conversion pass (`Always`, `Assert`, `Interface`, ...). |
| `--siloed` | Compile each file in isolation. (Loses cross-file refs.) |
| `--bsv` | Bluespec SystemVerilog quirks. |
| `--oversized-numbers` | Allow numbers larger than 32 bits without an explicit size. |
| `--pass-through` | Pass through unconverted SV (debug). |
| `--verbose` | Trace passes. |
| `--version`, `--help` | Self-explanatory. |

## Outputs
A single Verilog-2005 stream containing every module from the inputs
that is needed. Module ordering is preserved; comments are dropped.
