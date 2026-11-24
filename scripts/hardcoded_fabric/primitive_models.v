// Behavioural models of the Xilinx primitives that pass 1 of generate_hardcoded_netlist.tcl
// emits for the fabric logic. Pass 2 reads them before the pass-1 netlist, so they
// redefine the unisim cells (Synth 8-9873, intended) and Vivado re-optimises the
// netlist across tile borders instead of keeping every instantiated cell.
// Each model is functionally identical to its primitive.
// Written from the documented primitive behaviour (UG953), not derived from the unisim
// sources.

module LUT1 #(
  parameter [1:0] INIT = 2'h0
) (
  output O,
  input I0
);
  assign O = INIT[{I0}];
endmodule

module LUT2 #(
  parameter [3:0] INIT = 4'h0
) (
  output O,
  input I0, input I1
);
  assign O = INIT[{I1, I0}];
endmodule

module LUT3 #(
  parameter [7:0] INIT = 8'h0
) (
  output O,
  input I0, input I1, input I2
);
  assign O = INIT[{I2, I1, I0}];
endmodule

module LUT4 #(
  parameter [15:0] INIT = 16'h0
) (
  output O,
  input I0, input I1, input I2, input I3
);
  assign O = INIT[{I3, I2, I1, I0}];
endmodule

module LUT5 #(
  parameter [31:0] INIT = 32'h0
) (
  output O,
  input I0, input I1, input I2, input I3, input I4
);
  assign O = INIT[{I4, I3, I2, I1, I0}];
endmodule

module LUT6 #(
  parameter [63:0] INIT = 64'h0
) (
  output O,
  input I0, input I1, input I2, input I3, input I4, input I5
);
  assign O = INIT[{I5, I4, I3, I2, I1, I0}];
endmodule

module MUXF7 (
  output O,
  input I0,
  input I1,
  input S
);
  assign O = S ? I1 : I0;
endmodule

// 7-series carry chain: CI and CYINIT are never both used, the unused one is 0.
module CARRY4 (
  output [3:0] CO,
  output [3:0] O,
  input CI,
  input CYINIT,
  input [3:0] DI,
  input [3:0] S
);
  wire [4:0] carry;
  assign carry[0] = CI | CYINIT;
  assign carry[1] = S[0] ? carry[0] : DI[0];
  assign carry[2] = S[1] ? carry[1] : DI[1];
  assign carry[3] = S[2] ? carry[2] : DI[2];
  assign carry[4] = S[3] ? carry[3] : DI[3];
  assign CO = carry[4:1];
  assign O = S ^ carry[3:0];
endmodule

// Synchronous reset has priority over clock enable.
module FDRE #(
  parameter [0:0] INIT = 1'b0
) (
  output reg Q,
  input C,
  input CE,
  input D,
  input R
);
  initial Q = INIT;
  always @(posedge C) begin
    if (R) Q <= 1'b0;
    else if (CE) Q <= D;
  end
endmodule
