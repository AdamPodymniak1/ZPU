// Simple blinky: Tang Nano 20K has a 27 MHz onboard oscillator.
// Blinks LED[0] at ~1 Hz.
module top (
    input  wire clk,      // 27 MHz onboard oscillator
    output wire [5:0] led // 6 onboard LEDs, active LOW on Tang Nano 20K
);

    localparam integer COUNT_MAX = 27_000_000 / 2; // ~0.5s at 27MHz
    reg [24:0] counter = 0;
    reg blink = 0;

    always @(posedge clk) begin
        if (counter >= COUNT_MAX - 1) begin
            counter <= 0;
            blink   <= ~blink;
        end else begin
            counter <= counter + 1;
        end
    end

    // LEDs are active-low: drive 0 to light one, 1s elsewhere to keep rest off
    assign led = {5'b11111, ~blink};

endmodule