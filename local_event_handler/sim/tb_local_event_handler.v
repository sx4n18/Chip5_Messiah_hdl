`timescale 1ns/1ps

module tb_local_event_handler;

    // ================================================================
    // Clock / reset
    // ================================================================

    reg clk40m;
    reg pb_clk;
    reg rst_n;

    initial begin
        clk40m = 1'b0;
        forever #12.5 clk40m = ~clk40m;       // 40 MHz
    end

    // Separate PB clock to exercise the event_ack CDC path.
    // 75 MHz, intentionally asynchronous to clk40m.
    initial begin
        pb_clk = 1'b0;
        forever #6.667 pb_clk = ~pb_clk;
    end


    // ================================================================
    // DUT inputs
    // ================================================================

    reg         cmd_apply_mask;
    reg [39:0]  mask_shadow;

    reg         cmd_blk_enable;

    reg         global_reconfig;
    reg         global_enable;
    reg [8:0]   new_NMAX;
    reg         mode_1bit;

    reg [7:0]   fifo_overflow;
    reg         fifo_all_empty;

    reg [45:0]  mission_counter;

    // PB -> LEH acknowledgement
    reg         event_ack;


    // ================================================================
    // DUT outputs
    // ================================================================

    wire        compressor_enable;
    wire        afifo_reset_n;

    wire [39:0] pix_mask_active;
    wire        mode_1bit_active;
    wire [8:0]  NMAX_active;

    wire        block_busy;
    wire        block_enabled;

    wire        event_valid;
    wire [3:0]  event_type;
    wire [2:0]  event_fifo_id;
    wire [44:0] event_time0;
    wire [44:0] event_time1;


    // ================================================================
    // DUT
    // ================================================================

    local_event_handler dut (
        .clk40m             (clk40m),
        .rst_n              (rst_n),

        .cmd_apply_mask     (cmd_apply_mask),
        .mask_shadow        (mask_shadow),

        .cmd_blk_enable     (cmd_blk_enable),

        .global_reconfig    (global_reconfig),
        .global_enable      (global_enable),
        .new_NMAX           (new_NMAX),
        .mode_1bit          (mode_1bit),

        .fifo_overflow      (fifo_overflow),
        .fifo_all_empty     (fifo_all_empty),

        .mission_counter    (mission_counter[45:1]),

        .compressor_enable  (compressor_enable),
        .afifo_reset_n      (afifo_reset_n),

        .pix_mask_active    (pix_mask_active),
        .mode_1bit_active   (mode_1bit_active),
        .NMAX_active        (NMAX_active),

        .block_busy         (block_busy),
        .block_enabled      (block_enabled),

        .event_valid        (event_valid),
        .event_type         (event_type),
        .event_fifo_id      (event_fifo_id),
        .event_time0        (event_time0),
        .event_time1        (event_time1),

        .event_ack          (event_ack)
    );


    // ================================================================
    // FSM constants from DUT
    // ================================================================

    localparam RESET_STATE          = 4'd0;
    localparam IDLE_STATE           = 4'd1;
    localparam CAPTURE0_STATE       = 4'd2;
    localparam DISABLE_BLK_STATE    = 4'd3;
    localparam WAIT_EMPTY_STATE     = 4'd4;
    localparam RESET_AFIFO_STATE    = 4'd5;
    localparam APPLY_CONFIG_STATE   = 4'd6;
    localparam ENABLE_BLK_STATE     = 4'd7;
    localparam CAPTURE1_STATE       = 4'd8;
    localparam CREATE_EVENT_STATE   = 4'd9;
    localparam WAIT_ACK_STATE       = 4'd10;

    localparam FIFO_OF              = 4'h0;
    localparam LCAL_MSK_CHANGE      = 4'h1;
    localparam GLB_1_BIT_MODE       = 4'h2;
    localparam BLK_DISABLE_REQ      = 4'h3;

    // Standalone encoder instance used by the encoder-only test.
    // This avoids driving the DUT\'s overflow input during IDLE.
    reg  [7:0] encoder_test_input;
    wire [2:0] encoder_test_id;

    onehot_encoder encoder_test_dut (
        .fifo_overflow (encoder_test_input),
        .fifo_id       (encoder_test_id)
    );


    // ================================================================
    // Mission counter
    // ================================================================

    always @(posedge clk40m or negedge rst_n) begin
        if (!rst_n)
            mission_counter <= 46'd0;
        else
            mission_counter <= mission_counter + 46'd1;
    end


    // ================================================================
    // Clock helper
    //
    // All command stimulus is changed 1 ns after a clk40m edge to
    // avoid races with the DUT's sequential logic.
    // ================================================================

    task wait_clk;
    begin
        @(posedge clk40m);
        #1;
    end
    endtask


    // ================================================================
    // Wait for DUT FSM state
    // ================================================================

    task wait_state;
        input [3:0] expected_state;
        integer timeout;
    begin
        timeout = 0;

        while (dut.curr_state !== expected_state) begin
            wait_clk;
            timeout = timeout + 1;

            if (timeout > 200) begin
                $display("ERROR [%0t ns]: timeout waiting for state %0d",
                         $time, expected_state);
                $fatal;
            end
        end
    end
    endtask


    // ================================================================
    // Reset
    // ================================================================

    task reset_dut;
    begin
        rst_n = 1'b0;

        cmd_apply_mask = 1'b0;
        mask_shadow = 40'd0;

        cmd_blk_enable = 1'b0;

        global_reconfig = 1'b0;
        global_enable = 1'b0;
        new_NMAX = 9'd32;
        mode_1bit = 1'b0;

        fifo_overflow = 8'd0;
        fifo_all_empty = 1'b1;

        event_ack = 1'b0;
        encoder_test_input = 8'd0;

        repeat (4)
            wait_clk;

        rst_n = 1'b1;
        #1;
    end
    endtask


    // ================================================================
    // PB model
    //
    // event_valid is synchronised into the PB domain with 2 FFs.
    // The PB holds event_ack high until it sees event_valid deassert.
    // This models a 4-phase level handshake:
    //
    //       event_valid  -> 1
    //       event_ack    -> 1
    //       event_valid  -> 0
    //       event_ack    -> 0
    //
    // The payload is checked when PB accepts the event.
    // ================================================================

    reg pb_event_valid_meta;
    reg pb_event_valid_sync;
    reg pb_last_event_valid;

    reg [31:0] pb_event_count;
    integer pb_ack_delay_count;
    localparam integer PB_ACK_DELAY_CYCLES = 8;

    always @(posedge pb_clk or negedge rst_n) begin
        if (!rst_n) begin
            pb_event_valid_meta <= 1'b0;
            pb_event_valid_sync <= 1'b0;
            pb_last_event_valid <= 1'b0;
            event_ack <= 1'b0;
            pb_event_count <= 0;
            pb_ack_delay_count <= -1;
        end
        else begin
            pb_event_valid_meta <= event_valid;
            pb_event_valid_sync <= pb_event_valid_meta;
            pb_last_event_valid <= pb_event_valid_sync;

            // New event observed by PB.  Wait a few PB clocks before
            // acknowledging so the testbench also verifies that the
            // LEH holds event_valid continuously while waiting.
            if (pb_event_valid_sync && !pb_last_event_valid) begin
                pb_event_count <= pb_event_count + 1;
                pb_ack_delay_count <= PB_ACK_DELAY_CYCLES;

                $display("[%0t ns] PB observed event: type=%h fifo=%0d T0=%0d T1=%0d",
                         $time, event_type, event_fifo_id,
                         event_time0, event_time1);
            end

            if (pb_ack_delay_count > 0) begin
                pb_ack_delay_count <= pb_ack_delay_count - 1;
            end
            else if (pb_ack_delay_count == 0) begin
                event_ack <= 1'b1;
                pb_ack_delay_count <= -1;

                $display("[%0t ns] PB raises event_ack", $time);
            end

            // Four-phase return: once the LEH has dropped event_valid,
            // PB releases event_ack.
            if (!pb_event_valid_sync && pb_last_event_valid) begin
                event_ack <= 1'b0;
                $display("[%0t ns] PB releases event_ack", $time);
            end
        end
    end



    // ================================================================
    // Test 1: initial enable
    // ================================================================

    task test_initial_enable;
    begin
        $display("\n================================================");
        $display("TEST 1: Initial enable");
        $display("================================================");

        mask_shadow = 40'h12345_6789A;
        mode_1bit = 1'b0;
        new_NMAX = 9'd32;

        global_enable = 1'b1;
        cmd_blk_enable = 1'b1;

        wait_clk;

        if (compressor_enable !== 1'b1)
            $fatal(1, "Initial compressor_enable incorrect");

        if (block_enabled !== 1'b1)
            $fatal(1, "block_enabled incorrect");

        if (pix_mask_active !== 40'h12345_6789A)
            $fatal(1, "Initial mask incorrect: %h", pix_mask_active);

        if (mode_1bit_active !== 1'b0)
            $fatal(1, "Initial mode incorrect");

        if (NMAX_active !== 9'd32)
            $fatal(1, "Initial NMAX incorrect: %0d", NMAX_active);

        if (block_busy !== 1'b0)
            $fatal(1, "block_busy should be 0 after initial enable");

        if (event_valid !== 1'b0)
            $fatal(1, "event_valid should be 0 after initial enable");

        $display("PASS: initial configuration");
    end
    endtask


    // ================================================================
    // Test 2: local mask change
    // ================================================================

    task test_local_mask_change;
    reg [44:0] expected_t0;
    reg [44:0] expected_t1;
    begin
        $display("\n================================================");
        $display("TEST 2: Local mask change");
        $display("================================================");

        mask_shadow = 40'hABCDE_F0123;

        #1;
        cmd_apply_mask = 1'b1;

        wait_clk;
        cmd_apply_mask = 1'b0;

        if (event_type !== LCAL_MSK_CHANGE)
            $fatal(1, "Wrong mask event type: %h", event_type);

        if (!block_busy)
            $fatal(1, "block_busy not asserted for mask change");

        wait_state(DISABLE_BLK_STATE);
        wait_clk;

        if (compressor_enable !== 1'b0)
            $fatal(1, "Compressor did not disable");

        wait_state(WAIT_EMPTY_STATE);

        // FIFO empty so reconfiguration may proceed immediately.
        fifo_all_empty = 1'b1;

        wait_state(APPLY_CONFIG_STATE);

        wait_clk;
        if (pix_mask_active !== 40'hABCDE_F0123)
            $fatal(1, "Mask was not applied: %h", pix_mask_active);

        wait_state(WAIT_ACK_STATE);

        if (event_valid !== 1'b1)
            $fatal(1, "event_valid did not assert");

        if (block_busy !== 1'b1)
            $fatal(1, "block_busy dropped before ACK");

        if (event_time1 < event_time0)
            $fatal(1, "T1 (%0d) is earlier than T0 (%0d)",
                   event_time1, event_time0);

        expected_t0 = event_time0;
        expected_t1 = event_time1;

        // Check that the event stays valid until PB acknowledges it.
        repeat (4) begin
            wait_clk;
            if (event_valid !== 1'b1)
                $fatal(1, "event_valid dropped before ACK");
        end

        // PB model will raise ACK asynchronously to the LEH clock.
        wait_state(IDLE_STATE);

        if (event_valid !== 1'b0)
            $fatal(1, "event_valid not cleared after ACK");

        if (block_busy !== 1'b0)
            $fatal(1, "block_busy not cleared after ACK");

        // Allow PB to finish the second half of the 4-phase handshake.
        repeat (4)
            wait_clk;

        if (event_ack !== 1'b0)
            $fatal(1, "PB ACK did not return low");

        $display("PASS: local mask change (T0=%0d T1=%0d)",
                 expected_t0, expected_t1);
    end
    endtask


    // ================================================================
    // Test 3: FIFO overflow
    // ================================================================

    task test_fifo_overflow;
    begin
        $display("\n================================================");
        $display("TEST 3: FIFO overflow");
        $display("================================================");

        fifo_all_empty = 1'b0;

        // FIFO 2 overflows.
        fifo_overflow = 8'b0000_0100;
        #1;

        wait_clk;
        fifo_overflow = 8'd0;

        if (event_type !== FIFO_OF)
            $fatal(1, "Wrong overflow event type: %h", event_type);

        if (event_fifo_id !== 3'd2)
            $fatal(1, "Wrong FIFO ID for 0000_0100: %0d", event_fifo_id);

        wait_state(DISABLE_BLK_STATE);

        wait_clk;
        if (compressor_enable !== 1'b0)
            $fatal(1, "Compressor did not disable on overflow");

        wait_state(WAIT_EMPTY_STATE);

        // Keep FIFOs non-empty for a few cycles.
        repeat (3)
            wait_clk;

        if (dut.curr_state !== WAIT_EMPTY_STATE)
            $fatal(1, "Left WAIT_FIFO_EMPTY before fifo_all_empty");

        fifo_all_empty = 1'b1;

        wait_state(RESET_AFIFO_STATE);

        if (afifo_reset_n !== 1'b0)
            $fatal(1, "AFIFO reset pulse not asserted low");

        // RESET_AFIFO is a one-clock combinational pulse.
        wait_clk;

        if (afifo_reset_n !== 1'b1)
            $fatal(1, "AFIFO reset pulse did not release");

        wait_state(WAIT_ACK_STATE);

        if (compressor_enable !== 1'b1)
            $fatal(1, "Compressor was not re-enabled after overflow");

        if (event_valid !== 1'b1)
            $fatal(1, "Overflow event_valid did not assert");

        if (event_fifo_id !== 3'd2)
            $fatal(1, "FIFO ID changed after event creation");

        if (event_time1 < event_time0)
            $fatal(1, "Overflow T1 earlier than T0");

        wait_state(IDLE_STATE);

        repeat (4)
            wait_clk;

        if (event_ack !== 1'b0)
            $fatal(1, "PB ACK did not return low after overflow event");

        $display("PASS: FIFO overflow");
    end
    endtask


    // ================================================================
    // Test 4: encoder priority cases
    // ================================================================

    task test_encoder_priority;
    begin
        $display("\n================================================");
        $display("TEST 4: One-hot encoder priority");
        $display("================================================");

        // Multiple bits asserted. Because the casez patterns are
        // ordered from bit 7 down to bit 0, the LOWEST numbered
        // asserted bit is the first matching pattern and therefore
        // has priority.

        encoder_test_input = 8'b1010_0101;
        #1;
        if (encoder_test_id !== 3'd0)
            $fatal(1, "Encoder priority incorrect for 1010_0101: got %0d",
                   encoder_test_id);

        encoder_test_input = 8'b0010_0100;
        #1;
        if (encoder_test_id !== 3'd2)
            $fatal(1, "Encoder priority incorrect for 0010_0100: got %0d",
                   encoder_test_id);

        encoder_test_input = 8'b1000_0000;
        #1;
        if (encoder_test_id !== 3'd7)
            $fatal(1, "Encoder incorrect for FIFO 7: got %0d",
                   encoder_test_id);

        encoder_test_input = 8'd0;
        #1;
        $display("PASS: encoder priority");
    end
    endtask


    // ================================================================
    // Test 5: global reconfiguration
    // ================================================================

    task test_global_reconfig;
    begin
        $display("\n================================================");
        $display("TEST 5: Global reconfiguration");
        $display("================================================");

        mode_1bit = 1'b1;
        new_NMAX = 9'd127;

        global_reconfig = 1'b1;
        #1;
        wait_clk;
        global_reconfig = 1'b0;

        if (event_type !== GLB_1_BIT_MODE)
            $fatal(1, "Wrong global event type: %h", event_type);

        wait_state(WAIT_EMPTY_STATE);

        fifo_all_empty = 1'b1;

        wait_state(APPLY_CONFIG_STATE);
        wait_clk;
        if (mode_1bit_active !== 1'b1)
            $fatal(1, "1-bit mode was not applied");

        if (NMAX_active !== 9'd127)
            $fatal(1, "NMAX was not applied: %0d", NMAX_active);

        wait_state(WAIT_ACK_STATE);

        if (event_valid !== 1'b1)
            $fatal(1, "Global event_valid did not assert");

        wait_state(IDLE_STATE);

        repeat (4)
            wait_clk;

        if (event_ack !== 1'b0)
            $fatal(1, "PB ACK did not return low after global event");

        $display("PASS: global reconfiguration");
    end
    endtask


    // ================================================================
    // Test 6: intentional block disable
    //
    // This path must NOT generate a packet-builder event.
    // ================================================================

    task test_block_disable;
    begin
        $display("\n================================================");
        $display("TEST 6: Intentional block disable");
        $display("================================================");

        cmd_blk_enable = 1'b0;
        #1;

        wait_clk;

        if (event_type !== BLK_DISABLE_REQ)
            $fatal(1, "Wrong internal disable path type: %h", event_type);

        if (!block_busy)
            $fatal(1, "block_busy not asserted during disable flow");

        wait_state(DISABLE_BLK_STATE);

        wait_clk;
        if (compressor_enable !== 1'b0)
            $fatal(1, "Compressor did not disable");

        fifo_all_empty = 1'b1;

        wait_state(RESET_STATE);

        if (compressor_enable !== 1'b0)
            $fatal(1, "Compressor re-enabled unexpectedly");

        if (block_busy !== 1'b0)
            $fatal(1, "block_busy not cleared for intentional disable");

        if (event_valid !== 1'b0)
            $fatal(1, "Intentional disable incorrectly generated an event");

        $display("PASS: intentional block disable");
    end
    endtask


    // ================================================================
    // Test 7: re-enable after intentional disable
    // ================================================================

    task test_reenable;
    begin
        $display("\n================================================");
        $display("TEST 7: Re-enable after intentional disable");
        $display("================================================");

        cmd_blk_enable = 1'b1;
        #1;

        wait_clk;

        if (compressor_enable !== 1'b1)
            $fatal(1, "Compressor did not re-enable");

        if (block_enabled !== 1'b1)
            $fatal(1, "block_enabled incorrect after re-enable");

        if (pix_mask_active !== 40'hABCDE_F0123)
            $fatal(1, "Unexpected mask after re-enable: %h", pix_mask_active);

        if (mode_1bit_active !== 1'b1)
            $fatal(1, "Unexpected mode after re-enable");

        if (NMAX_active !== 9'd127)
            $fatal(1, "Unexpected NMAX after re-enable: %0d", NMAX_active);

        $display("PASS: re-enable");
    end
    endtask


    // ================================================================
    // Test 8: second event must not be falsely completed by stale ACK
    // ================================================================

    task test_second_event_after_ack;
    begin
        $display("\n================================================");
        $display("TEST 8: No stale ACK on next event");
        $display("================================================");

        // Wait until PB has definitely released ACK.
        while (event_ack !== 1'b0)
            wait_clk;

        mask_shadow = 40'h00000_0AAAA;
        cmd_apply_mask = 1'b1;
        #1;
        wait_clk;
        cmd_apply_mask = 1'b0;

        wait_state(WAIT_ACK_STATE);

        if (event_valid !== 1'b1)
            $fatal(1, "Second event did not assert event_valid");

        // At this point ACK must still be low until PB sees the new event.
        if (event_ack !== 1'b0)
            $fatal(1, "Stale PB ACK was high before new event was observed");

        // Give PB enough time to see event_valid and acknowledge it.
        wait_state(IDLE_STATE);

        repeat (4)
            wait_clk;

        if (event_ack !== 1'b0)
            $fatal(1, "PB ACK did not return low after second event");

        $display("PASS: no stale ACK on next event");
    end
    endtask


    // ================================================================
    // Main sequence
    // ================================================================

    initial begin
        $display("\n############################################################");
        $display("# LOCAL EVENT HANDLER TESTBENCH");
        $display("############################################################\n");

        reset_dut;

        test_initial_enable;
        test_local_mask_change;
        test_fifo_overflow;
        test_encoder_priority;
        test_global_reconfig;
        test_block_disable;
        test_reenable;
        test_second_event_after_ack;

        $display("\n############################################################");
        $display("# ALL TESTS PASSED");
        $display("############################################################\n");

        #100;
        $finish;
    end


    // ================================================================
    // Lightweight waveform/debug monitor
    // ================================================================

    reg [3:0] monitor_prev_state;

    initial monitor_prev_state = RESET_STATE;

    always @(posedge clk40m) begin
        #0.1;

        if (rst_n && dut.curr_state !== monitor_prev_state) begin
            $display("[%0t ns] LEH state %0d -> %0d | enable=%b busy=%b " ,
                     $time,
                     monitor_prev_state,
                     dut.curr_state,
                     compressor_enable,
                     block_busy);
            monitor_prev_state = dut.curr_state;
        end
    end

endmodule
