// SystemVerilog source using a packed struct and always_ff — neither
// is in Verilog-2005.  sv2v will translate to plain Verilog.
package types_pkg;
    typedef struct packed {
        logic [3:0] hi;
        logic [3:0] lo;
    } byte_t;
endpackage

module top
    import types_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,
    input  byte_t      din,
    output logic [7:0] dout
);
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) dout <= '0;
        else        dout <= {din.hi, din.lo};
endmodule
