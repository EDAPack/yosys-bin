# 01-bmc

Intent: smallest possible BMC run. Demonstrates the `.sby` file
structure and how to read sby's output when an assertion fails.

```
./run.sh
```

Expected: the assertion fails at cycle 5; status `FAIL`. The VCD
counterexample is at `counter/engine_0/trace.vcd`.

To make the property true, edit `counter.sv` and change `3'd5` to a
value the counter can't reach within 10 cycles (e.g. `3'd0` after the
first cycle — but note `q` starts at 0).
