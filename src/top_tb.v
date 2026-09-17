`timescale 1ns/1ps

module top_tb;

    reg clk = 0;
    wire [5:0] led;

    // 27 MHz clock -> period ~37.037 ns
    always #18.518 clk = ~clk;

    top uut (
        .clk(clk),
        .led(led)
    );

    initial begin
        $dumpfile("top_tb.vcd");
        $dumpvars(0, top_tb);
        #100000;
        $display("Simulation finished.");
        $finish;
    end

endmodule