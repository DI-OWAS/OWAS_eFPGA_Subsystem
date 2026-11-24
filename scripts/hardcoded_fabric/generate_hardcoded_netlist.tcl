# Vivado netlist of the OWAS_Fabric eFPGA with one soft-logic design's bitstream hard-coded.
#
# Synthesises the fabric in FABulous EMULATION mode (bitstream hard-coded at compile
# time from the design's .vh) into a flat, loop-free gate-level `eFPGA_top` that replaces the
# fabric RTL in an FPGA build.
#
# Pass 1 folds each tile on its own (KEEP_HIERARCHY), pass 2 re-synthesises the result
# flat with behavioural primitive models. Why two passes: see README.md.
#
# Usage (from the repository root):
#   vivado -mode batch -nojournal -source scripts/hardcoded_fabric/generate_hardcoded_netlist.tcl \
#     -tclargs -vh SOFT_LOGIC/build/flex/flex.vh -o SOFT_LOGIC/build/flex/flex_hardcoded_fabric.v
#
# Options:
#   -vh <file>      design configuration header (generate_bitstream.py output), required
#   -o <file>       output netlist (module eFPGA_top), required
#   -part <part>    FPGA part (default xc7a200tsbg484-1, Nexys Video)
#   -f <file>       flat Vivado file list (default FILE_LISTS/vivado/efpga_subsystem_vivado.f);
#                   only its OWAS_Fabric/ entries are read
#   -work <dir>     directory for pass-1 netlist and reports (default: <output dir>/hardcoded_fabric)
#   -keep_primitives "<cells>"
#                   primitives without a model that pass 2 keeps as fixed cells, e.g.
#                   "RAM32M" for fabric memories (default: none)
#
# Fails (non-zero exit) when a tile with configuration bits gets no Emulate_Bitstream
# define, when pass 1 emits a primitive or attribute without a behavioural model, or when the
# final netlist contains combinational loops.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]

proc read_file {path} {
  set fp [open $path r]
  set text [read $fp]
  close $fp
  return $text
}

proc usage_error {msg} {
  puts "ERROR: $msg"
  puts "usage: vivado -mode batch -source [info script] -tclargs -vh <design.vh> -o <out.v> \[-part <part>\] \[-f <filelist>\] \[-work <dir>\] \[-keep_primitives <cells>\]"
  exit 1
}

array set opt [list -part xc7a200tsbg484-1 \
  -f [file join $repo_root FILE_LISTS vivado efpga_subsystem_vivado.f] -vh "" -o "" -work "" \
  -keep_primitives ""]
if {[llength $argv] % 2 != 0} { usage_error "options need a value: $argv" }
foreach {key value} $argv {
  if {![info exists opt($key)]} { usage_error "unknown option $key" }
  set opt($key) $value
}
if {$opt(-vh) eq "" || $opt(-o) eq ""} { usage_error "-vh and -o are required" }
set vh [file normalize $opt(-vh)]
set out [file normalize $opt(-o)]
set filelist [file normalize $opt(-f)]
set work [expr {$opt(-work) eq "" ? [file join [file dirname $out] hardcoded_fabric] : [file normalize $opt(-work)]}]
foreach f [list $vh $filelist] {
  if {![file isfile $f]} { usage_error "file not found: $f" }
}
file mkdir $work [file dirname $out]

# --- fabric sources: the OWAS_Fabric/ entries of the flat file list ---
set fabric_files {}
foreach line [split [read_file $filelist] "\n"] {
  set line [string trim $line]
  if {[string match "OWAS_Fabric/*" $line]} {
    lappend fabric_files [file join $repo_root $line]
  }
}
if {[llength $fabric_files] == 0} { usage_error "no OWAS_Fabric/ entries in $filelist" }
foreach f $fabric_files {
  if {![file isfile $f]} { usage_error "file from $filelist not found: $f" }
}

# --- configuration check: every instance of a tile that has configuration bits must
# get its `Tile_X<x>Y<y>_Emulate_Bitstream define, or it is silently synthesised
# unconfigured. FABulous before FABulous-OWAS #40 skipped the border rows. Tiles
# without configuration bits (plain N/S_term tiles) need no define.
set configured_tiles {}
set efpga_v ""
foreach f $fabric_files {
  set text [read_file $f]
  if {[file tail $f] eq "eFPGA.v"} { set efpga_v $text; continue }
  if {[regexp {module\s+(\w+)\s*#\s*\(([^;]*?)\)\s*\(} $text -> module params]
      && [string match "*Emulate_Bitstream*" $params]
      && [string match "*ConfigBits*" $text]} {
    lappend configured_tiles $module
  }
}
if {$efpga_v eq ""} { usage_error "no eFPGA.v among the fabric files" }
set missing {}
set checked 0
foreach {match instance x y tile} [regexp -all -inline {\m(Tile_X(\d+)Y(\d+)_(\w+))\s*\(} $efpga_v] {
  if {$tile ni $configured_tiles} { continue }
  incr checked
  if {![string match "*`Tile_X${x}Y${y}_Emulate_Bitstream*" $efpga_v]} { lappend missing $instance }
}
if {[llength $missing] > 0} {
  puts "ERROR: [llength $missing] tile instance(s) in eFPGA.v get no Emulate_Bitstream, e.g. [lrange $missing 0 4]."
  puts "ERROR: regenerate eFPGA.v with a FABulous that passes Emulate_Bitstream to every tile with"
  puts "ERROR: configuration bits (e.g. the border rows need FABulous-OWAS #40 or newer)."
  exit 1
}
puts "INFO: all $checked tile instances with configuration bits get their Emulate_Bitstream define"

# --- pass 1: per-tile fold ---
create_project -in_memory -part $opt(-part)
read_verilog -sv $fabric_files
read_verilog $vh
set_property file_type {Verilog Header} [get_files $vh]
set_property is_global_include true [get_files $vh]
read_xdc -unmanaged [file join $script_dir keep_tiles.xdc]
synth_design -top eFPGA_top -part $opt(-part) -mode out_of_context -verilog_define EMULATION=1

set kept [get_cells -hierarchical -filter {KEEP_HIERARCHY != ""}]
if {[llength $kept] == 0} { puts "ERROR: keep_tiles.xdc matched no tile instance"; exit 1 }
puts "INFO: pass 1 kept [llength $kept] tile instances"
reset_property KEEP_HIERARCHY $kept

# Only primitives with a behavioural model, constants, or ones the caller keeps on
# purpose may stay; anything else would be a fixed cell that quietly limits pass 2.
set modelled {LUT1 LUT2 LUT3 LUT4 LUT5 LUT6 MUXF7 CARRY4 FDRE GND VCC}
set unmodelled {}
set primitives [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != INTERNAL}]
foreach ref [lsort -unique [get_property REF_NAME $primitives]] {
  if {$ref ni $modelled && $ref ni $opt(-keep_primitives)} { lappend unmodelled $ref }
}
if {[llength $unmodelled] > 0} {
  puts "ERROR: pass 1 produced primitives without a behavioural model: $unmodelled"
  puts "ERROR: add a model to primitive_models.v, or keep them as fixed cells with -keep_primitives"
  exit 1
}
# The models implement INIT only. LUTs, MUXF7 and CARRY4 have no other functional
# attributes (UG953); FDRE also has inverted-pin attributes, which must stay unset.
set inverted {}
set fdre [filter -quiet $primitives {REF_NAME == FDRE}]
if {[llength $fdre] > 0} {
  foreach prop {IS_C_INVERTED IS_D_INVERTED IS_R_INVERTED} {
    foreach cell $fdre value [get_property $prop $fdre] {
      if {[string index $value end] eq "1"} { lappend inverted "$cell ($prop)" }
    }
  }
}
if {[llength $inverted] > 0} {
  puts "ERROR: [llength $inverted] FDRE pin(s) inverted, which the FDRE model does not implement, e.g. [lrange $inverted 0 4]"
  puts "ERROR: extend the FDRE model in primitive_models.v"
  exit 1
}
set pass1 [file join $work eFPGA_top_pass1.v]
write_verilog -force -mode design $pass1
close_project

# --- pass 2: flat re-synthesis across tile borders ---
create_project -in_memory -part $opt(-part)
# The models intentionally redefine unisim cells (Synth 8-9873).
read_verilog [file join $script_dir primitive_models.v] $pass1
synth_design -top eFPGA_top -part $opt(-part) -mode out_of_context -flatten_hierarchy full

report_utilization -file [file join $work utilization.rpt]
check_timing -override_defaults {loops} -file [file join $work loops.rpt]
report_drc -name lutlp -checks {LUTLP-1} -file [file join $work drc_lutlp.rpt]
set loop_violations [llength [get_drc_violations -quiet -name lutlp]]
set loops_text [read_file [file join $work loops.rpt]]
if {$loop_violations > 0 || ![regexp {There are 0 combinational loops} $loops_text]} {
  puts "ERROR: netlist has combinational loops (LUTLP-1: $loop_violations), see $work/loops.rpt"
  exit 1
}
write_verilog -force -mode design $out
puts "INFO: wrote $out (loop-free, reports in $work)"
