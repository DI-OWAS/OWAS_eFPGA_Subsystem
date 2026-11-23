# Integration constraints for efpga_subsystem_top, for use with its views/lib timing models.
#
# The liberty models alone are optimistic:
#  - output arcs have one table for min and max: min clock-to-out is too large (up to ~9 ns on
#    pmod_io_o/oe_o, efpga_usr_irq_o), so hold looks better than it is
#  - the input setup/hold constants lack the on-chip variation of the flat signoff
#  - the rst_efpga_npu_n_i setup constant is ~1-2 ns optimistic
# Values per corner from the flat top (netlist + SPEF, signoff SDC) vs. the lib, rounded up:
# pessimistic by up to ~0.9 ns (setup) and ~0.6 ns (hold).
#
# Usage, after the clocks and clock uncertainties are defined:
#   set OWAS_TOP_INSTANCE <hierarchical instance name>
#   set OWAS_TOP_CORNER   fast|typ|slow     ;# optional, default: worst case of all corners
#   set OWAS_CLK_UNCERTAINTY_SETUP 0.25     ;# optional, clock uncertainty of clk_i (default 0.25)
#   set OWAS_CLK_UNCERTAINTY_HOLD  0.25     ;# optional
#   source efpga_subsystem_top_integration.sdc
# The margins are set as clock uncertainty on the instance clk_i pin, which replaces the clock
# uncertainty there, so the base values are added.

if {![info exists OWAS_TOP_INSTANCE]} {error "Set OWAS_TOP_INSTANCE to the efpga_subsystem_top instance"}
if {![info exists OWAS_CLK_UNCERTAINTY_SETUP]} {set OWAS_CLK_UNCERTAINTY_SETUP 0.25}
if {![info exists OWAS_CLK_UNCERTAINTY_HOLD]} {set OWAS_CLK_UNCERTAINTY_HOLD 0.25}

#                   early_derate setup_margin hold_margin rst_setup
set _owas_values [dict create \
    fast  {0.10 0.40 0.15 1.0} \
    typ   {0.12 0.55 0.20 2.2} \
    slow  {0.16 0.85 0.35 4.2} \
    worst {0.10 0.85 0.35 4.2}]

if {[info exists OWAS_TOP_CORNER]} {
    if {![dict exists $_owas_values $OWAS_TOP_CORNER]} {error "OWAS_TOP_CORNER must be fast, typ or slow"}
    set _owas_corner $OWAS_TOP_CORNER
} else {
    puts "Warning: OWAS_TOP_CORNER not set, using the worst case of all corners for $OWAS_TOP_INSTANCE"
    set _owas_corner worst
}
lassign [dict get $_owas_values $_owas_corner] _owas_early _owas_setup _owas_hold _owas_rst_setup

set _owas_cell [get_cells $OWAS_TOP_INSTANCE]
if {[llength $_owas_cell] != 1} {error "Expected exactly one instance $OWAS_TOP_INSTANCE"}
set _owas_clk [get_pins $OWAS_TOP_INSTANCE/clk_i]
set _owas_rst [get_pins $OWAS_TOP_INSTANCE/rst_efpga_npu_n_i]

# Outputs: min clock-to-out. The max tables already include the late variation
set_timing_derate -early -data -cell_delay $_owas_early $_owas_cell
set_timing_derate -late -data -cell_delay 1.0 $_owas_cell

# Inputs: setup/hold margin on all checks of the instance
set_clock_uncertainty -setup [expr {$OWAS_CLK_UNCERTAINTY_SETUP + $_owas_setup}] $_owas_clk
set_clock_uncertainty -hold [expr {$OWAS_CLK_UNCERTAINTY_HOLD + $_owas_hold}] $_owas_clk

# rst_efpga_npu_n_i: setup to the next clk_i edge (data checks are zero-cycle by default), hold
# from the lib. OpenSTA warns "not a valid endpoint" but applies the check
set_data_check -rise_from $_owas_clk -to $_owas_rst -setup $_owas_rst_setup
set_multicycle_path 1 -setup -to $_owas_rst

unset _owas_values _owas_corner _owas_early _owas_setup _owas_hold _owas_rst_setup \
    _owas_cell _owas_clk _owas_rst
