# sby CLI cheatsheet

```
sby [options] <sbyfile> [<task> ...]
```

If no tasks are listed, all tasks in `[tasks]` run.

| Flag | Effect |
|---|---|
| `-f` | Delete pre-existing work directory before running. |
| `-d <dir>` | Place the work directory at `<dir>` (default: alongside the `.sby`). |
| `-t` | Print per-step timing. |
| `-T <task>` | Restrict to a task (repeatable). |
| `--prefix <s>` | Prefix output lines (useful when several sby runs share a terminal). |
| `--yosys <path>` | Path to yosys binary (default: PATH lookup). |
| `--smtbmc <path>` | Path to yosys-smtbmc (default: alongside yosys). |
| `--dump-cfg` | Print parsed config and exit. |
| `--dump-tasks` | List tasks defined in the file and exit. |
| `--init-config-file` | Write a starter `.sby` to stdout. |

## Status output
Each task prints one of:
- `PASS` — assertions hold to the configured depth (BMC) or proven
  inductively (prove).
- `FAIL` — counterexample found; VCD at `<task>/engine_0/trace.vcd`.
- `UNKNOWN` — solver gave up (timeout, undecided induction step).
- `ERROR` — config or tool error; check `<task>/logfile.txt`.
