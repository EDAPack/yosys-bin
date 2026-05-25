# sby failure recipes

## `FAIL` with VCD
Symptom: task ends `FAIL` and `<task>/engine_0/trace.vcd` exists.
Cause: counterexample to an `assert`/`assume`. The `summary` section
of `logfile.txt` lists the failing property and cycle.
Fix: open the VCD, examine values at the failing cycle, decide
whether the RTL or the property is wrong.

## `UNKNOWN` in `prove` mode
Symptom: status `UNKNOWN`, log says `INDUCTION STEP: ...` failed.
Cause: k-induction needs strong enough invariants; current `assume`
set is too weak.
Fix: add `assume property` constraints near the unreachable states,
or raise `depth` (k) in `[options]`.

## "Module ... not found" inside the yosys log
Symptom: log shows yosys exiting with module-not-found.
Cause: `[script]` did not `read` all needed files, or `[files]` is
missing entries.
Fix: list every dependency under `[files]`; ensure `read -formal` (or
`read_verilog -sv`) covers them.

## Solver missing
Symptom:
```
ERROR: smtbmc: 'boolector' command failed: No such file or directory
```
Cause: the named SMT solver isn't on PATH inside the work dir.
Fix: this edapack release bundles `boolector` next to `yosys`; verify
`${pkg}/bin` is on PATH. Or change `[engines]` to a solver you have
(e.g. `smtbmc z3`).

## "ERROR: Time limit reached"
Symptom: engine exits with timeout.
Cause: `[options] timeout` (or default) too low for design complexity.
Fix: raise `timeout`, reduce `depth`, or simplify the design (e.g.
`flatten` less aggressively, abstract subblocks with `chformal`).
