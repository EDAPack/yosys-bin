# 02-ice40-synth

Intent: drive `synth_ice40` end-to-end and emit a JSON netlist that
`nextpnr-ice40` can place-and-route.

```
./run.sh
```

The resulting `counter.json` is the standard handoff format to
nextpnr; an agent chaining yosys → nextpnr-ice40 → icepack would call
this script first.
