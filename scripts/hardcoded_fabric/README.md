# Fabric netlist with hard-coded bitstream (`generate_hardcoded_netlist.tcl`)

Turns the fabric plus one soft-logic design (`<design>.vh` from `generate_bitstream.py`)
into a flat, loop-free gate-level `eFPGA_top` with that design's bitstream hard-coded
(FABulous `EMULATION` mode), for FPGA prototyping. Configuration logic and unused routing
are optimised away, so the netlist implements only that design, not the reconfigurable
fabric. The netlist replaces the `OWAS_Fabric/` sources in a Vivado build, e.g.
the chip-level Nexys Video flow.

```bash
vivado -mode batch -nojournal -source scripts/hardcoded_fabric/generate_hardcoded_netlist.tcl \
  -tclargs -vh SOFT_LOGIC/build/flex/flex.vh -o SOFT_LOGIC/build/flex/flex_hardcoded_fabric.v
```

| Flag | Description |
| :--- | :--- |
| `-vh <file>` | Design configuration header (required). |
| `-o <file>` | Output netlist, module `eFPGA_top` (required). |
| `-part <part>` | FPGA part (default `xc7a200tsbg484-1`, Nexys Video). |
| `-f <file>` | Flat Vivado file list (default `FILE_LISTS/vivado/efpga_subsystem_vivado.f`); only its `OWAS_Fabric/` entries are read. |
| `-work <dir>` | Pass-1 netlist and reports (default `<output dir>/hardcoded_fabric/`). |
| `-keep_primitives "<cells>"` | Primitives without a model that stay fixed cells, e.g. `"RAM32M"` for fabric memories (default: none). |

## Why two passes

Synthesising the raw `EMULATION` fabric in one go fails: Vivado 2025.1 aborts in
constant propagation (internal assert), and the unused routing muxes leave false
combinational loops.

1. **Pass 1** synthesises out of context with `KEEP_HIERARCHY` on every tile
   (`keep_tiles.xdc`). Each tile folds its own constant configuration, so the crash
   and the loops are gone, but the tile borders block LUT merging (OWAS: −0.9 ns at
   50 MHz in the full Nexys Video build).
2. **Pass 2** drops `KEEP_HIERARCHY` and synthesises the pass-1 netlist again, flat.
   `primitive_models.v` replaces `LUT1`–`LUT6`, `MUXF7`, `CARRY4` and `FDRE` with
   behavioural models (Vivado warns `Synth 8-9873`, intended), so Vivado
   re-optimises across tile borders instead of keeping each instantiated cell.

Results:

| Fabric / design | Time, peak RAM | Result |
| :--- | :--- | :--- |
| OWAS 9x16 + `flex` | ~5.5 min, 4.7 GB | Nexys Video full build at 50 MHz: WNS +0.906 ns, no loops, LUTLP-1 clean |
| FABulous demo fabric + `sequential_16bit_en` (`-keep_primitives RAM32M`) | ~2.5 min, 3.2 GB | FABulous testbench (`-d EMULATION`) matches the gold design |

## Checks (the script exits non-zero)

- An instance of a tile with configuration bits gets no
  `` `Tile_X<x>Y<y>_Emulate_Bitstream `` define in `Fabric/eFPGA.v`. FABulous without
  the border-row fix (FABulous-OWAS PR #40) skips the top and bottom rows, which
  would silently synthesise them unconfigured: regenerate the fabric with a fixed
  FABulous.
- Pass 1 produces a primitive without a behavioural model (e.g. `RAM32M` or
  `DSP48E1` after a fabric change): add a model to `primitive_models.v`, or keep the
  cell fixed with `-keep_primitives`.
- Pass 1 produces an `FDRE` with an inverted pin (`IS_C_INVERTED`, `IS_D_INVERTED`,
  `IS_R_INVERTED`), which the model does not implement: extend the `FDRE` model. The
  other modelled cells have no functional attributes besides `INIT`.
- The final netlist has combinational loops (`check_timing` loops or LUTLP-1).
  Do not run pass 2 again on its own output: re-synthesising the flat netlist can
  create new false loops.
