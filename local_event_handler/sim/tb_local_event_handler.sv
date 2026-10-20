`timescale 1ns/1ps

///////////////////////////////////////////////////////////////////////
// Self-checking testbench for local_event_handler Ver. 0.1
//
// Assumes:
//   - commands are one-cycle pulses in clk40m
//   - global_enable and cmd_blk_enable are persistent enables
//   - fifo_all_empty is the already-synchronised 40 MHz status
//   - event_ack is a pulse/level that becomes high after PB has captured
//     the event. The testbench uses a one-cycle pulse.
///////////////////////////////////////////////////////////////////////

module tb_local_event_handler;

    reg         clk40m;
    reg         rst_n;

    reg         cmd_apply_mask;
    reg [39:0]  mask_shadow;
    reg         cmd_blk_enable;

    reg         acq_start_cmd;
    reg         global_reconfig;
    reg         global_enable;
    reg [9:0]   new_NMAX;
    reg         mode_1bit;

    reg [7:0]   fifo_overflow;
    reg         fifo_all_empty;

    reg [44:0]  mission_counter;
    reg         cnt_flip;

    reg         event_ack;

    wire        compressor_enable;
    wire        afifo_reset_n;

    wire [39:0] pix_mask_active;
    wire        mode_1bit_active;
    wire [9:0]  NMAX_active;

    wire        block_busy;
    wire        block_enabled;

    wire [44:0] ACQ_START_T;
    wire [44:0] BLK_DISABLE_T;
    wire [44:0] BLK_ENABLE_T;

    wire        event_valid;
    wire [3:0]  event_type;
    wire [2:0]  event_fifo_id;
    wire [44:0] event_time0;
    wire [44:0] event_time1;

    integer errors;
    integer cycles;

    local_event_handler dut (
        .clk40m(clk40m),
        .rst_n(rst_n),

        .cmd_apply_mask(cmd_apply_mask),
        .mask_shadow(mask_shadow),
        .cmd_blk_enable(cmd_blk_enable),

        .acq_start_cmd(acq_start_cmd),
        .global_reconfig(global_reconfig),
        .global_enable(global_enable),
        .new_NMAX(new_NMAX),
        .mode_1bit(mode_1bit),

        .fifo_overflow(fifo_overflow),
        .fifo_all_empty(fifo_all_empty),

        .mission_counter(mission_counter),

        .compressor_enable(compressor_enable),
        .afifo_reset_n(afifo_reset_n),

        .pix_mask_active(pix_mask_active),
        .mode_1bit_active(mode_1bit_active),
        .NMAX_active(NMAX_active),

        .block_busy(block_busy),
        .block_enabled(block_enabled),

        .ACQ_START_T(ACQ_START_T),
        .BLK_DISABLE_T(BLK_DISABLE_T),
        .BLK_ENABLE_T(BLK_ENABLE_T),

        .event_valid(event_valid),
        .event_type(event_type),
        .event_fifo_id(event_fifo_id),
        .event_time0(event_time0),
        .event_time1(event_time1),

        .event_ack(event_ack)
    );


        reg [44:0] expected_t;

    ///////////////////////////////////////////////////////////////////////
    // 40 MHz clock
    ///////////////////////////////////////////////////////////////////////
    initial begin
        clk40m = 1'b0;
        forever #12.5 clk40m = ~clk40m;
    end

    ///////////////////////////////////////////////////////////////////////
    // Free-running mission counter
    ///////////////////////////////////////////////////////////////////////
    always @(posedge clk40m or negedge rst_n) begin
        if (!rst_n)
            {mission_counter, cnt_flip} <= 46'd0;
        else
            {mission_counter, cnt_flip} <= {mission_counter, cnt_flip} + 1;
    end

    ///////////////////////////////////////////////////////////////////////
    // Helpers
    ///////////////////////////////////////////////////////////////////////
    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                $display("ERROR @ %0t: %s", $time, message);
                errors = errors + 1;
            end else begin
                $display("PASS  @ %0t: %s", $time, message);
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk40m);
            #1;
        end
    endtask

    task tick_n;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                tick;
        end
    endtask

    task pulse_acq_start;
        begin
            @(negedge clk40m);
            acq_start_cmd = 1'b1;
            @(posedge clk40m);
            // DUT and mission_counter both sample the pre-NBA counter here.
            expected_t = mission_counter;
            #1;
            acq_start_cmd = 1'b0;
        end
    endtask

    task pulse_apply_mask;
        begin
            @(negedge clk40m);
            cmd_apply_mask = 1'b1;
            @(negedge clk40m);
            cmd_apply_mask = 1'b0;
            #1;
        end
    endtask

    task pulse_global_reconfig;
        begin
            @(negedge clk40m);
            global_reconfig = 1'b1;
            @(negedge clk40m);
            global_reconfig = 1'b0;
            #1;
        end
    endtask

    task pulse_overflow;
        input [7:0] value;
        begin
            @(negedge clk40m);
            fifo_overflow = value;
            @(negedge clk40m);
            fifo_overflow = 8'd0;
            #1;
        end
    endtask

    task pulse_event_ack;
        begin
            // Give the synchronizer enough time after event_valid appears.
            @(negedge clk40m);
            event_ack = 1'b1;
            @(negedge clk40m);
            event_ack = 1'b0;
            #1;
        end
    endtask

    task wait_event_valid;
        begin
            cycles = 0;
            while (!event_valid && cycles < 30) begin
                tick;
                cycles = cycles + 1;
            end
            check(event_valid, "event_valid asserted");
        end
    endtask

    ///////////////////////////////////////////////////////////////////////
    // Main test sequence
    ///////////////////////////////////////////////////////////////////////


    initial begin
        errors = 0;

        cmd_apply_mask = 1'b0;
        mask_shadow    = 40'd0;
        cmd_blk_enable = 1'b1;

        acq_start_cmd  = 1'b0;
        global_reconfig = 1'b0;
        global_enable  = 1'b0;
        new_NMAX       = 10'd32;
        mode_1bit      = 1'b0;

        fifo_overflow  = 8'd0;
        fifo_all_empty = 1'b1;

        event_ack      = 1'b0;

        rst_n          = 1'b0;
        repeat (3) tick;
        rst_n          = 1'b1;
        tick;

        ///////////////////////////////////////////////////////////////////
        // 1. RESET must wait for BOTH effective enable and acq_start_cmd.
        ///////////////////////////////////////////////////////////////////
        check(!compressor_enable, "compressor remains disabled after reset");
        check(ACQ_START_T == 45'd0, "ACQ_START_T starts at zero");

        global_enable = 1'b1;
        tick_n(2);
        check(!compressor_enable,
              "eff_enable alone does not leave RESET");

        ///////////////////////////////////////////////////////////////////
        // 2. Acquisition start: exact timestamp + initial configuration.
        ///////////////////////////////////////////////////////////////////
        mask_shadow = 40'h12345_6789A;
        mode_1bit   = 1'b1;
        new_NMAX    = 10'd55;

        // Put a known mission count on the clock edge used for acquisition start.
        pulse_acq_start;
        tick;

        check(compressor_enable, "compressor enabled after acquisition start");
        check(ACQ_START_T == expected_t,
              "ACQ_START_T captured at acquisition enable edge");
        check(pix_mask_active == 40'h12345_6789A,
              "initial mask captured at acquisition start");
        check(mode_1bit_active == 1'b1,
              "initial 1-bit/3-bit mode captured at acquisition start");
        check(NMAX_active == 10'd55,
              "initial NMAX captured at acquisition start");

        ///////////////////////////////////////////////////////////////////
        // 3. Overflow: lower-priority FIFO selection and event timestamps.
        ///////////////////////////////////////////////////////////////////
        tick_n(3);
        fifo_all_empty = 1'b1;

        pulse_overflow(8'b0000_1001);  // FIFO 0 and FIFO 3; FIFO 0 wins.

        // CAPCHAT0 captures T0 using the pre-NBA mission counter value.
        tick;
        expected_t = mission_counter - 45'd1;
        check(event_time0 == expected_t,
              "overflow event T0 is captured at the CAPCHAT0 edge");

        tick;  // DISABLE_BLK
        check(!compressor_enable,
              "overflow path disables compressor");

        tick;  // WAIT_FIFO_EMPTY
        tick;  // RESET_AFIFO
        check(!afifo_reset_n,
              "AFIFO reset asserted in RESET_AFIFO");

        tick;  // ENABLE_BLK state entry
        tick;  // ENABLE_BLK action
        check(compressor_enable,
              "overflow path re-enables compressor");

        tick;  // CAPCHAT1 state entry
        tick;  // CAPCHAT1 action: event_time1 + event_valid
        expected_t = mission_counter - 45'd1;
        check(event_valid, "overflow event is valid");
        check(event_type == 4'h0, "overflow event type is FIFO_OF");
        check(event_fifo_id == 3'd0,
              "FIFO 0 has highest priority when multiple overflow bits are high");
        check(event_time1 == expected_t,
              "overflow event T1 is captured before event_valid is raised");

        // Event must remain valid until ACK.
        tick;
        check(event_valid, "event_valid remains high before ACK");
        check(block_busy, "block remains busy before ACK");

        pulse_event_ack;
        tick_n(3);

        check(!event_valid, "event_valid clears after ACK");
        check(!block_busy, "block_busy clears after ACK");
        check(compressor_enable, "compressor remains enabled after overflow recovery");

        ///////////////////////////////////////////////////////////////////
        // 4. Local mask change.
        ///////////////////////////////////////////////////////////////////
        mask_shadow = 40'h0AAAA_BBBBB;

        pulse_apply_mask;
        tick;  // CAPCHAT0
        expected_t = mission_counter;
        tick;  // DISABLE_BLK

        check(!compressor_enable,
              "local mask change disables compressor");

        tick;  // WAIT FIFO
        tick;  // RESET_AFIFO
        check(!afifo_reset_n,
              "AFIFO reset asserted during local mask change");

        tick;  // APPLY_CONFIG state entry
        check(pix_mask_active != mask_shadow,
              "mask is not updated before APPLY_CONFIG executes");

        tick;  // APPLY_CONFIG action
        check(pix_mask_active == mask_shadow,
              "new mask applied in APPLY_CONFIG");

        tick;  // ENABLE_BLK action executes
        tick;  // CAPCHAT1 state entry
        tick;  // CAPCHAT1 action / event_valid
        check(pix_mask_active == mask_shadow,
              "new mask remains active when event is raised");
        check(event_type == 4'h1,
              "local config event type is correct");
        check(event_valid,
              "local config event is valid");

        pulse_event_ack;
        tick_n(3);

        check(!event_valid, "local config event clears after ACK");
        check(compressor_enable, "compressor restored after local config");

        ///////////////////////////////////////////////////////////////////
        // 5. Global reconfiguration applies all global settings together.
        ///////////////////////////////////////////////////////////////////
        mode_1bit = 1'b0;
        new_NMAX  = 10'd127;

        pulse_global_reconfig;
        tick;      // CAPCHAT0
        tick;      // DISABLE_BLK
        check(!compressor_enable,
              "global reconfig disables compressor");

        tick;      // WAIT FIFO
        tick;      // RESET AFIFO
        check(!afifo_reset_n,
              "AFIFO reset asserted during global reconfig");

        tick;      // APPLY_CONFIG state entry
        tick;      // APPLY_CONFIG action
        check(mode_1bit_active == 1'b0,
              "global mode updated");
        check(NMAX_active == 10'd127,
              "global NMAX updated together");

        tick;      // ENABLE_BLK action
        tick;      // CAPCHAT1 state entry
        tick;      // CAPCHAT1 action / event_valid
        check(event_type == 4'h2,
              "global config event type is correct");
        check(event_valid,
              "global config event is valid");

        pulse_event_ack;
        tick_n(3);

        check(!event_valid, "global config event clears after ACK");
        check(compressor_enable, "compressor restored after global config");

        ///////////////////////////////////////////////////////////////////
        // 6. Intentional disable -> DOWN, no event packet.
        ///////////////////////////////////////////////////////////////////
        tick_n(2);
        cmd_blk_enable = 1'b0;

        tick; // IDLE detects effective disable
        check(block_busy, "intentional disable marks block busy");

        tick; // CAPCHAT0
        tick; // DISABLE_BLK action
        expected_t = mission_counter - 45'd1;
        check(!compressor_enable,
              "intentional disable turns compressor off");
        check(BLK_DISABLE_T == expected_t,
              "BLK_DISABLE_T captured at the compressor disable edge");

        tick; // WAIT FIFO
        tick; // RESET AFIFO
        check(!afifo_reset_n,
              "AFIFO reset asserted during intentional disable");

        tick; // DOWN
        check(!compressor_enable, "block remains disabled in DOWN");
        check(!event_valid, "intentional disable does not raise an event");
        check(!block_busy, "block_busy clears before entering DOWN");

        ///////////////////////////////////////////////////////////////////
        // 7. Intentional re-enable -> ENABLE_BLK -> IDLE.
        ///////////////////////////////////////////////////////////////////
        tick;
        cmd_blk_enable = 1'b1;

        tick; // DOWN -> ENABLE_BLK
        tick; // ENABLE_BLK action
        expected_t = mission_counter - 45'd1;
        check(compressor_enable,
              "compressor enabled by intentional re-enable");
        check(BLK_ENABLE_T == expected_t,
              "BLK_ENABLE_T captured at the compressor enable edge");
        check(!event_valid,
              "intentional re-enable does not raise an event");

        tick; // IDLE
        check(compressor_enable, "block returns to IDLE enabled state");

        ///////////////////////////////////////////////////////////////////
        // 8. ACQ_START_T must not be overwritten by later enable events.
        ///////////////////////////////////////////////////////////////////
        check(ACQ_START_T != 45'd0,
              "ACQ_START_T remains stored after later block enable/disable");

        ///////////////////////////////////////////////////////////////////
        // Summary
        ///////////////////////////////////////////////////////////////////
        if (errors == 0) begin
            $display("============================================================");
            $display("ALL TESTS PASSED");
            $display("============================================================");
        end else begin
            $display("============================================================");
            $display("TESTBENCH FAILED: %0d error(s)", errors);
            $display("============================================================");
        end

        $finish;
    end

endmodule
