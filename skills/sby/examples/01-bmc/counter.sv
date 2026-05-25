// 3-bit counter with a formal property: q must never equal 3'd5.
// The property is *false* — sby should find a counterexample
// at cycle 5 (q reaches 5 starting from 0).  Flip the constant to
// 3'd7 to make the property true within depth=10.
module counter (
    input  wire       clk,
    input  wire       rst,
    output reg  [2:0] q
);
    always @(posedge clk)
        if (rst) q <= 3'd0;
        else     q <= q + 1'b1;

`ifdef FORMAL
    always @(posedge clk)
        if (!rst) assert (q != 3'd5);
`endif
endmodule
