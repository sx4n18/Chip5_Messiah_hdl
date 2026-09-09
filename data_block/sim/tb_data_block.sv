`timescale 1ns/1ps

module tb_data_block;

///////////////////////////////////////////////////////////////////////////////
// Clock / reset
///////////////////////////////////////////////////////////////////////////////

logic clk40m;
logic clk75m;
logic rst_n;

initial begin
    clk40m = 1'b0;
    forever #12.5 clk40m = ~clk40m;      // 40 MHz
end

initial begin
    clk75m = 1'b0;
    forever #6.666666 clk75m = ~clk75m;  // 75 MHz
end


///////////////////////////////////////////////////////////////////////////////
// DUT inputs
///////////////////////////////////////////////////////////////////////////////

logic         cmd_apply_mask;
logic [39:0]  mask_shadow;
logic         cmd_blk_enable;

logic         global_reconfig;
logic         global_enable;
logic [9:0]   new_NMAX;
logic         mode_1bit;

logic         pix_valid;
logic [119:0] pix_value;

logic         FRAME_FIFO_AFULL;


///////////////////////////////////////////////////////////////////////////////
// DUT outputs
///////////////////////////////////////////////////////////////////////////////

wire        block_busy;
wire        block_enabled;

wire [15:0] DATA_2_FIFO;
wire        FRAME_FIFO_PUSH;


///////////////////////////////////////////////////////////////////////////////
// DUT
///////////////////////////////////////////////////////////////////////////////

data_block dut (
    .clk40m            (clk40m),
    .rst_n             (rst_n),

    .clk75m            (clk75m),

    .cmd_apply_mask    (cmd_apply_mask),
    .mask_shadow       (mask_shadow),
    .cmd_blk_enable    (cmd_blk_enable),

    .global_reconfig   (global_reconfig),
    .global_enable     (global_enable),
    .new_NMAX          (new_NMAX),
    .mode_1bit         (mode_1bit),

    .block_busy        (block_busy),
    .block_enabled     (block_enabled),

    .pix_valid         (pix_valid),
    .pix_value         (pix_value),

    .FRAME_FIFO_AFULL  (FRAME_FIFO_AFULL),

    .DATA_2_FIFO       (DATA_2_FIFO),
    .FRAME_FIFO_PUSH   (FRAME_FIFO_PUSH)
);


///////////////////////////////////////////////////////////////////////////////
// Statistics
///////////////////////////////////////////////////////////////////////////////

integer packet_word_count;
integer event_count;
integer event_ack_count;

initial begin
    packet_word_count = 0;
    event_count       = 0;
    event_ack_count   = 0;
end


///////////////////////////////////////////////////////////////////////////////
// Monitor packet builder output
///////////////////////////////////////////////////////////////////////////////

always @(posedge clk75m) begin
    #1;

    if (FRAME_FIFO_PUSH) begin
        packet_word_count = packet_word_count + 1;

        $display("[%0t] FRAME_FIFO_PUSH  DATA=%04h",
                 $time, DATA_2_FIFO);
    end
end


///////////////////////////////////////////////////////////////////////////////
// Monitor local event handler
//
// These are internal DUT signals, useful for integration debugging.
// They do not affect DUT operation.
///////////////////////////////////////////////////////////////////////////////

always @(posedge clk40m) begin
    #1;

    if (dut.event_valid) begin
        event_count = event_count + 1;

        $display("[%0t] EVENT VALID type=%0d fifo_id=%0d t0=%0d t1=%0d",
                 $time,
                 dut.event_type,
                 dut.event_fifo_id,
                 dut.event_time0,
                 dut.event_time1);
    end

    if (dut.event_ack) begin
        event_ack_count = event_ack_count + 1;

        $display("[%0t] EVENT ACK",
                 $time);
    end
end


///////////////////////////////////////////////////////////////////////////////
// Basic X/Z checking
///////////////////////////////////////////////////////////////////////////////

always @(posedge clk75m) begin
    #1;

    if (rst_n) begin

        if ($isunknown(DATA_2_FIFO)) begin
            $error("[%0t] DATA_2_FIFO contains X/Z",
                   $time);
        end

        if ($isunknown(FRAME_FIFO_PUSH)) begin
            $error("[%0t] FRAME_FIFO_PUSH contains X/Z",
                   $time);
        end

        if ($isunknown(block_busy)) begin
            $error("[%0t] block_busy contains X/Z",
                   $time);
        end

        if ($isunknown(block_enabled)) begin
            $error("[%0t] block_enabled contains X/Z",
                   $time);
        end

    end
end


///////////////////////////////////////////////////////////////////////////////
// FRAME FIFO almost-full protocol check
//
// Packet builder should not push into a full/almost-full frame FIFO.
///////////////////////////////////////////////////////////////////////////////

always @(posedge clk75m) begin
    #1;

    if (rst_n && FRAME_FIFO_AFULL && FRAME_FIFO_PUSH) begin
        $error("[%0t] FRAME_FIFO_PUSH asserted while FRAME_FIFO_AFULL=1",
               $time);
    end
end


///////////////////////////////////////////////////////////////////////////////
// Task: reset
///////////////////////////////////////////////////////////////////////////////

task automatic do_reset;
begin

    rst_n = 1'b0;

    cmd_apply_mask  = 1'b0;
    mask_shadow     = '1;
    cmd_blk_enable  = 1'b0;

    global_reconfig = 1'b0;
    global_enable   = 1'b0;
    new_NMAX        = 10'd128;
    mode_1bit       = 1'b0;

    pix_valid       = 1'b0;
    pix_value       = 120'b0;

    FRAME_FIFO_AFULL = 1'b0;

    repeat (8) @(posedge clk40m);
    #1;

    rst_n = 1'b1;

    $display("[%0t] Reset released",
             $time);
end
endtask


///////////////////////////////////////////////////////////////////////////////
// Task: pulse a 40 MHz command
///////////////////////////////////////////////////////////////////////////////

task automatic pulse_cmd40(
    output logic cmd_signal
);
begin

    @(posedge clk40m);
    #1;
    cmd_signal = 1'b1;

    @(posedge clk40m);
    #1;
    cmd_signal = 1'b0;

end
endtask


///////////////////////////////////////////////////////////////////////////////
// Task: global configuration
///////////////////////////////////////////////////////////////////////////////

task automatic apply_global_config(
    input logic [9:0] nmax,
    input logic       mode
);
begin

    @(posedge clk40m);
    #1;

    new_NMAX      = nmax;
    mode_1bit     = mode;
    global_enable = 1'b1;

    @(posedge clk40m);
    #1;

    global_reconfig = 1'b1;

    @(posedge clk40m);
    #1;

    global_reconfig = 1'b0;


    $display("[%0t] Global config applied: NMAX=%0d mode_1bit=%0d",
             $time, nmax, mode);

end
endtask


///////////////////////////////////////////////////////////////////////////////
// Task: apply pixel mask
///////////////////////////////////////////////////////////////////////////////

task automatic apply_mask(
    input logic [39:0] new_mask
);
begin

    @(posedge clk40m);
    #1;

    mask_shadow = new_mask;

    @(posedge clk40m);
    #1;

    cmd_apply_mask = 1'b1;

    @(posedge clk40m);
    #1;

    cmd_apply_mask = 1'b0;

    $display("[%0t] Pixel mask applied: %040h",
             $time, new_mask);

end
endtask


///////////////////////////////////////////////////////////////////////////////
// Task: enable block
///////////////////////////////////////////////////////////////////////////////

task automatic enable_block;
begin

    @(posedge clk40m);
    #1;

    cmd_blk_enable = 1'b1;

    @(posedge clk40m);
    #1;


    $display("[%0t] Block enable command issued",
             $time);

end
endtask


///////////////////////////////////////////////////////////////////////////////
// Task: send pixels
//
// pix_value contains eight 15-bit pixels.
// Each transaction therefore presents 8 pixels to the 8 encoders.
///////////////////////////////////////////////////////////////////////////////

task automatic send_pixels(
    input integer num_cycles
);
    integer k;

begin

    for (k = 0; k < num_cycles; k = k + 1) begin

        @(posedge clk40m);
        #1;

        pix_valid = 1'b1;

        pix_value[14:0]    = 15'h1000 + k;
        pix_value[29:15]   = 15'h1100 + k;
        pix_value[44:30]   = 15'h1200 + k;
        pix_value[59:45]   = 15'h1300 + k;
        pix_value[74:60]   = 15'h1400 + k;
        pix_value[89:75]   = 15'h1500 + k;
        pix_value[104:90]  = 15'h1600 + k;
        pix_value[119:105] = 15'h1700 + k;

        @(posedge clk40m)
        #1;

        pix_valid = 1'b0;

    end

    @(posedge clk40m);
    #1;

    pix_valid = 1'b0;
    pix_value = 120'b0;

end
endtask


///////////////////////////////////////////////////////////////////////////////
// Wait for block enabled
///////////////////////////////////////////////////////////////////////////////

task automatic wait_block_enabled;
    integer timeout;

begin

    timeout = 0;

    while (!block_enabled) begin

        @(posedge clk40m);
        #1;

        timeout = timeout + 1;

        if (timeout > 1000) begin
            $fatal(1,
                   "[%0t] Timeout waiting for block_enabled",
                   $time);
        end

    end

    $display("[%0t] block_enabled asserted",
             $time);

end
endtask


///////////////////////////////////////////////////////////////////////////////
// Wait for block to become idle
///////////////////////////////////////////////////////////////////////////////

task automatic wait_block_idle;
    integer timeout;

begin

    timeout = 0;

    while (block_busy) begin

        @(posedge clk40m);
        #1;

        timeout = timeout + 1;

        if (timeout > 5000) begin
            $fatal(1,
                   "[%0t] Timeout waiting for block_busy to deassert",
                   $time);
        end

    end

    $display("[%0t] block_busy deasserted",
             $time);

end
endtask


///////////////////////////////////////////////////////////////////////////////
// Main test sequence
///////////////////////////////////////////////////////////////////////////////

initial begin

    ///////////////////////////////////////////////////////////////////////////
    // Initial values
    ///////////////////////////////////////////////////////////////////////////

    rst_n = 1'b0;

    cmd_apply_mask  = 1'b0;
    mask_shadow     = '1;
    cmd_blk_enable  = 1'b0;

    global_reconfig = 1'b0;
    global_enable   = 1'b0;
    new_NMAX        = 10'd128;
    mode_1bit       = 1'b0;

    pix_valid       = 1'b0;
    pix_value       = 120'b0;

    FRAME_FIFO_AFULL = 1'b0;


    ///////////////////////////////////////////////////////////////////////////
    // TEST 1: Reset
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST 1: RESET");
    $display("============================================================");

    do_reset;

    repeat (4) @(posedge clk40m);
    #1;


    ///////////////////////////////////////////////////////////////////////////
    // TEST 2: Global configuration
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST 2: GLOBAL CONFIGURATION");
    $display("============================================================");

    apply_global_config(
        10'd128,
        1'b0
    );


    ///////////////////////////////////////////////////////////////////////////
    // TEST 3: Enable block
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST 3: ENABLE BLOCK");
    $display("============================================================");

    enable_block;

    wait_block_enabled;


    ///////////////////////////////////////////////////////////////////////////
    // TEST 4: Pixel traffic
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST 4: PIXEL TRAFFIC");
    $display("============================================================");

    send_pixels(100);

    repeat (100) @(posedge clk75m);
    #1;

    $display("[%0t] Packet words generated so far = %0d",
             $time, packet_word_count);


    ///////////////////////////////////////////////////////////////////////////
    // TEST 5: Apply pixel mask
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST 5: PIXEL MASK UPDATE");
    $display("============================================================");

    apply_mask(
        40'b00000_11111_00000_11111_00000_11111_00000_11111
    );

    send_pixels(100);


    while(block_busy) 
    begin 
        @(posedge clk75m);
        #1;
    end

    repeat (10) @(posedge clk75m);
    #1;


    ///////////////////////////////////////////////////////////////////////////
    // TEST 6: Change operating mode / NMAX
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST 6: GLOBAL RECONFIGURATION");
    $display("============================================================");

    apply_global_config(
        10'd64,
        1'b1
    );

    // Give the handler time to complete the reconfiguration.

    while(block_busy) 
    begin 
        @(posedge clk75m);
        #1;
    end

    repeat (10) @(posedge clk75m);
    #1;

    send_pixels(100);

    repeat (100) @(posedge clk75m);
    #1;


    ///////////////////////////////////////////////////////////////////////////
    // TEST 7: FRAME FIFO almost full
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST 7: FRAME_FIFO_AFULL");
    $display("============================================================");

    @(posedge clk75m);
    #1;

    FRAME_FIFO_AFULL = 1'b1;

    // Keep pixel traffic running while packet FIFO is blocked.
    send_pixels(50);

    repeat (20) @(posedge clk75m);
    #1;

    if (FRAME_FIFO_PUSH !== 1'b0) begin
        $error("[%0t] FRAME_FIFO_PUSH should be blocked when AFULL is asserted",
               $time);
    end

    @(posedge clk75m);
    #1;

    FRAME_FIFO_AFULL = 1'b0;

    repeat (50) @(posedge clk75m);
    #1;


    ///////////////////////////////////////////////////////////////////////////
    // TEST 8: Final traffic burst
    ///////////////////////////////////////////////////////////////////////////

    // before final burst test, we set the bit mode back to 3-bit and max read of 128 words

    apply_global_config(
        10'd128,
        1'b0);

    repeat(10) @(posedge clk75m);

    while(block_busy)
    begin 
        @(posedge clk75m);
        #1;
    end

    $display("");
    $display("============================================================");
    $display("TEST 8: FINAL TRAFFIC BURST");
    $display("============================================================");

    send_pixels(1000);

    repeat (300) @(posedge clk75m);
    #1;


    ///////////////////////////////////////////////////////////////////////////
    // TEST SUMMARY
    ///////////////////////////////////////////////////////////////////////////

    $display("");
    $display("============================================================");
    $display("TEST SUMMARY");
    $display("============================================================");

    $display("Packet words pushed : %0d", packet_word_count);
    $display("Events generated    : %0d", event_count);
    $display("Events acknowledged  : %0d", event_ack_count);
    $display("block_enabled       : %0d", block_enabled);
    $display("block_busy          : %0d", block_busy);

    if (packet_word_count == 0) begin
        $error("No packet words were generated.");
    end

    $display("");
    $display("DATA BLOCK INTEGRATION TEST COMPLETE");
    $display("");

    #100;
    $finish;

end


///////////////////////////////////////////////////////////////////////////////
// Optional waveform dump
///////////////////////////////////////////////////////////////////////////////
/*
initial begin

    $dumpfile("tb_data_block.vcd");
    $dumpvars(0, tb_data_block);

end
*/
endmodule