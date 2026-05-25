# yosys documentation index

Annotated links to upstream documentation. Read these for depth beyond
the SKILL.md.

## Primary
- **Project site** — https://yosyshq.net/yosys/
- **Source repo** — https://github.com/YosysHQ/yosys
- **Online manual (HTML)** — https://yosyshq.readthedocs.io/projects/yosys/en/latest/
  - Read `cmd_ref/index.html` for the full command catalog. The
    in-shell `help` command prints the same content.
- **Manual PDF** — https://yosyshq.readthedocs.io/_/downloads/yosys/en/latest/pdf/

## Topic-specific
- **Writing synthesizable RTL for yosys** —
  https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/synth.html
- **`synth_ice40` / `synth_ecp5` / `synth_xilinx` reference** —
  https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/synth_ice40.html
  (swap arch in URL).
- **yosys-slang plugin** — https://github.com/povik/yosys-slang
  (loaded with `plugin -i slang`).
- **Formal flows (sby)** — https://yosyshq.readthedocs.io/projects/sby/en/latest/

## Worked examples in the wild
- **picorv32** — https://github.com/YosysHQ/picorv32 (canonical
  yosys+nextpnr+icestorm reference design).
- **VexRiscv on iCE40 / ECP5** — https://github.com/SpinalHDL/VexRiscv
  (use sv2v for the SV source).
- **F4PGA examples** — https://github.com/chipsalliance/f4pga-examples
  (full FOSS FPGA flows).

## In-shell help
```
yosys -p 'help'              # list all commands
yosys -p 'help synth_ice40'  # detailed help for one command
yosys -p 'help -all'         # dump everything (long)
```
