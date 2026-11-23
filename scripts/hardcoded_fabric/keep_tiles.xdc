# Pass 1 of generate_hardcoded_netlist.tcl: keep every fabric tile so synthesis folds each
# tile's constant EMULATION configuration on its own (Vivado's ConstProp aborts on
# the whole fabric, and the unused routing muxes would leave false loops).
set_property KEEP_HIERARCHY YES [get_cells -hierarchical -regexp {(.*/)?eFPGA_inst/Tile_X[0-9]+Y[0-9]+_[^/]+}]
