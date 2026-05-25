// Smallest design: a parameterizable counter driving an LED.
module blinky #(parameter WIDTH = 24) (
    input  wire clk,
    output wire led
);
    reg [WIDTH-1:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1'b1;
    assign led = cnt[WIDTH-1];
endmodule
