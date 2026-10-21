`timescale 1ns/1ps

module tb_row_encode_5p_1bit;

////////////////////////////////////////////////////////////
// Clock
////////////////////////////////////////////////////////////

reg clk40m;

initial begin
    clk40m = 1'b0;
    forever #12.5 clk40m = ~clk40m;
end


////////////////////////////////////////////////////////////
// DUT inputs
////////////////////////////////////////////////////////////

reg         rstn;
reg         EN;
reg         one_bit;
reg         pix_valid;
reg [4:0]   pix_mask;
reg [14:0]  pix_gray;


////////////////////////////////////////////////////////////
// DUT outputs
////////////////////////////////////////////////////////////

wire        enc_ready;
wire [15:0] enc_data;


////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////

Row_encode_5P dut (
    .clk40m    (clk40m),
    .rstn      (rstn),
    .EN        (EN),
    .one_bit   (one_bit),
    .pix_valid (pix_valid),
    .pix_mask  (pix_mask),
    .pix_gray  (pix_gray),
    .enc_ready (enc_ready),
    .enc_data  (enc_data)
);


////////////////////////////////////////////////////////////
// Test variables
////////////////////////////////////////////////////////////

integer error_count;
integer output_count;

reg [15:0] expected_data;
reg        expected_ready;


////////////////////////////////////////////////////////////
// Monitor
////////////////////////////////////////////////////////////

always @(posedge clk40m) begin

    if (enc_ready) begin

        output_count = output_count + 1;

        $display(
            "[%0t] OUTPUT #%0d : 0x%04h",
            $time,
            output_count,
            enc_data
        );

    end

end


////////////////////////////////////////////////////////////
// Basic reset
////////////////////////////////////////////////////////////

task reset_dut;
begin

    rstn      = 1'b0;
    EN        = 1'b0;
    one_bit   = 1'b0;
    pix_valid = 1'b0;
    pix_mask  = 5'b11111;
    pix_gray  = 15'b0;

    repeat (5)
        @(posedge clk40m);

    rstn = 1'b1;

    repeat (2)
        @(posedge clk40m);

end
endtask


////////////////////////////////////////////////////////////
// Send one pixel evaluation
//
// IMPORTANT:
//
// pix_valid is changed on negedge so that there is no
// race with the DUT's posedge logic.
//
// One call = one ADC evaluation.
//
// The DUT itself only evaluates the 1-bit pattern after
// three such calls.
//
////////////////////////////////////////////////////////////

`ifdef GATE_LEVEL

task tb_drive_edge;
begin
    @(posedge clk40m);
    #1;
end
endtask

`else

task tb_drive_edge;
begin
    @(negedge clk40m);
end
endtask

`endif


task send_pixel;
input [14:0] d;
begin

    tb_drive_edge();

    pix_gray  = d;
    pix_valid = 1'b1;

    tb_drive_edge();

    pix_valid = 1'b0;

end
endtask


////////////////////////////////////////////////////////////
// Send three pixels
//
// These three evaluations form one 15-bit 1-bit pattern.
//
////////////////////////////////////////////////////////////

task send_3_pixels;
input [14:0] p0;
input [14:0] p1;
input [14:0] p2;
begin

    send_pixel(p0);
    send_pixel(p1);
    send_pixel(p2);

end
endtask


////////////////////////////////////////////////////////////
// Wait some clocks
////////////////////////////////////////////////////////////

task wait_clocks;
input integer n;
integer k;
begin

    for (k = 0; k < n; k = k + 1)
        @(posedge clk40m);

end
endtask


////////////////////////////////////////////////////////////
// TEST 1
//
// First 3-pixel pattern.
//
// All pixels are above threshold.
//
// Binary:
//
// 11111
//
// should generate:
//
// 15'b111111111111111
//
// Output:
//
// 0_111111111111111
//
////////////////////////////////////////////////////////////

task test_first_pattern;
begin

    $display("");
    $display("==========================================");
    $display("TEST 1: FIRST 1-BIT PATTERN");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Binary value 7 -> above threshold 4
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    wait_clocks(5);

end
endtask


////////////////////////////////////////////////////////////
// TEST 2
//
// Repeat exactly the same 3-pixel pattern.
//
// The first occurrence establishes the pattern.
// The second occurrence should NOT generate a data word.
//
// Instead the encoder should enter WAIT and start
// incrementing silence_counter.
//
////////////////////////////////////////////////////////////

task test_enter_wait;
begin

    $display("");
    $display("==========================================");
    $display("TEST 2: ENTER WAIT");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // First pattern
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    wait_clocks(2);

    // Same pattern again
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    wait_clocks(5);

end
endtask


////////////////////////////////////////////////////////////
// TEST 3
//
// Stay in WAIT for multiple evaluations.
//
// Expected:
//
// silence_counter
//
// 0 -> 1 -> 2 -> 3 -> ...
//
// No encoded output should be generated while remaining
// silent.
//
////////////////////////////////////////////////////////////

task test_wait_counter;
begin

    $display("");
    $display("==========================================");
    $display("TEST 3: WAIT / SILENCE COUNTER");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Establish pattern
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Repeat several times
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    wait_clocks(5);

end
endtask


////////////////////////////////////////////////////////////
// TEST 4
//
// Pattern changes while in WAIT.
//
// Expected:
//
//   previous data
//   timestamp
//   new data
//
// The timestamp must contain the number of repeated
// evaluations represented by silence_counter.
//
////////////////////////////////////////////////////////////

task test_wait_wakeup;
begin

    $display("");
    $display("==========================================");
    $display("TEST 4: WAIT -> WAKEUP");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Pattern A
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Repetition -> silence
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Pattern B
    send_3_pixels(
        15'b000_000_000_000_000,
        15'b000_000_000_000_000,
        15'b000_000_000_000_000
    );

    wait_clocks(8);

end
endtask


////////////////////////////////////////////////////////////
// TEST 5
//
// IMPORTANT EDGE CASE:
//
// The pattern changes during the accumulation.
//
// The encoder must NOT wake up until the THIRD pixel
// evaluation has arrived.
//
//
//
// Example:
//
// old pattern:
//
// AAAAA
// AAAAA
// AAAAA
//
// new candidate:
//
// BBBBB
// BBBBB
// CCCCC
//
// The comparison only happens after CCCCC.
//
////////////////////////////////////////////////////////////

task test_partial_accumulation_change;
begin

    $display("");
    $display("==========================================");
    $display("TEST 5: PARTIAL ACCUMULATION CHANGE");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Establish A
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Enter WAIT
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // New pattern begins.
    // First evaluation alone must NOT produce output.
    send_pixel(15'b000_000_000_000_000);

    wait_clocks(2);

    // Second evaluation.
    send_pixel(15'b000_000_000_000_000);

    wait_clocks(2);

    // Third evaluation.
    // Now the new 15-bit word is complete.
    send_pixel(15'b000_000_000_000_000);

    wait_clocks(8);

end
endtask


////////////////////////////////////////////////////////////
// TEST 6
//
// Disable while in WAIT.
//
// This is the important case we just discussed.
//
// Expected:
//
// WAIT
//   |
//   | EN = 0
//   v
// FLUSH
//   |
//   | timestamp
//   v
// PUSH
//   |
//   | final data
//   v
// IDLE
//
////////////////////////////////////////////////////////////

task test_disable_in_wait;
begin

    $display("");
    $display("==========================================");
    $display("TEST 6: DISABLE WHILE IN WAIT");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Establish pattern
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Enter WAIT
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Accumulate some silence
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Disable away from clock edge to avoid TB/DUT race.
    tb_drive_edge();
    EN = 1'b0;

    // Give FLUSH and PUSH time to execute.
    wait_clocks(8);

end
endtask


////////////////////////////////////////////////////////////
// TEST 7
//
// Disable while in PUSH.
//
// This should simply return to IDLE.
// There should NOT be a timestamp because there is no
// silence interval to report.
//
////////////////////////////////////////////////////////////

task test_disable_in_push;
begin

    $display("");
    $display("==========================================");
    $display("TEST 7: DISABLE WHILE IN PUSH");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Only one pixel of a new accumulation.
    send_pixel(15'b111_111_111_111_111);

    tb_drive_edge();
    EN = 1'b0;

    wait_clocks(5);

end
endtask


////////////////////////////////////////////////////////////
// TEST 8
//
// Alarm.
//
// Instead of waiting for 32768 actual silence periods,
// directly preload the counter.
//
// This is acceptable for a directed unit test.
//
// We put the DUT in WAIT and set:
//
// silence_counter = 7FFF
//
// Then provide another repeated pattern.
//
////////////////////////////////////////////////////////////

task test_alarm;
begin

    $display("");
    $display("==========================================");
    $display("TEST 8: SILENCE COUNTER ALARM");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Establish pattern
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    // Enter WAIT
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    wait_clocks(2);

    // Force counter near timeout.
    $display("[%0t] Starting long alarm-count test", $time);

    repeat (32765)
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111);

    // One more identical evaluation should bring it to 7FFF.
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

   send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );
    wait_clocks(5);

    // Another evaluation should cause alarm behaviour.
    send_3_pixels(
        15'b111_111_111_111_111,
        15'b111_111_111_111_111,
        15'b111_111_111_111_111
    );

    wait_clocks(8);

end
endtask


////////////////////////////////////////////////////////////
// TEST 9
//
// Test thresholding.
//
// Binary values:
//
// 000 = below threshold -> 0
// 100 = NOT greater than 100 -> 0
// 101 = greater than 100 -> 1
// 111 = greater than 100 -> 1
//
// We deliberately make each pixel different.
//
////////////////////////////////////////////////////////////

task test_threshold;
begin

    $display("");
    $display("==========================================");
    $display("TEST 9: 1-BIT THRESHOLD");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Each 15-bit word contains five pixels.
    //
    // pixel values:
    // Gray   Bin
    // 111 -> 101 -> 1
    // 101 -> 110 -> 1
    // 100 -> 111 -> 1
    // 010 -> 011 -> 0
    // 000 -> 000 -> 0
    //
    // expected one-bit result:
    //
    // 11100
    //
    // Repeat for three evaluations:
    //
    // 11100 11100 11100
    //
    // => 15'b111001110011100

    send_3_pixels(
        15'b111_101_100_010_000,
        15'b111_101_100_010_000,
        15'b111_101_100_010_000
    );

    wait_clocks(8);

end
endtask


////////////////////////////////////////////////////////////
// TEST 10
//
// Masking.
//
// A masked pixel is converted to 111 by your RTL:
//
// pix_mask[i] ? pix_bin : 3'b111
//
// Therefore masked pixels should always classify as 1.
//
////////////////////////////////////////////////////////////

task test_mask;
begin

    $display("");
    $display("==========================================");
    $display("TEST 10: PIXEL MASK");
    $display("==========================================");

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b1;

    // Mask all five pixels.
    pix_mask = 5'b00000;

    send_3_pixels(
        15'b000_000_000_000_000,
        15'b000_000_000_000_000,
        15'b000_000_000_000_000
    );

    wait_clocks(8);

    // Restore mask.
    pix_mask = 5'b11111;

    send_3_pixels(
        15'b000_000_000_000_000,
        15'b000_000_000_000_000,
        15'b000_000_000_000_000
    );

    wait_clocks(6);

end
endtask


////////////////////////////////////////////////////////////
// Main test sequence
////////////////////////////////////////////////////////////

initial begin

    error_count  = 0;
    output_count = 0;

    $display("");
    $display("******************************************");
    $display("* ROW ENCODER 5P - 1 BIT TESTBENCH      *");
    $display("******************************************");

    test_first_pattern;

    test_enter_wait;

    test_wait_counter;

    test_wait_wakeup;

    test_partial_accumulation_change;

    test_disable_in_wait;

    test_disable_in_push;

    test_alarm;

    test_threshold;

    test_mask;

    $display("");
    $display("******************************************");
    $display("* TESTBENCH COMPLETE                     *");
    $display("* OUTPUT COUNT = %0d                      *",
             output_count);
    $display("* ERROR COUNT  = %0d                      *",
             error_count);
    $display("******************************************");
    $display("");

    $finish;

end

endmodule
