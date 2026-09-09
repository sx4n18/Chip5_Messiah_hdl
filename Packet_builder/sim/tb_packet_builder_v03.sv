`timescale 1ns/1ps

// ============================================================================
// Testbench for packet_builder v0.3
//
// This testbench is intentionally written as a protocol/packet scoreboard
// rather than as a state-by-state checker.  It verifies the externally visible
// behavior of the 19-state FSM:
//   * normal frame creation
//   * reserved-word escaping
//   * multiple payload words from one FIFO
//   * channel-ID increase -> C0DE + new CID
//   * channel-ID wrap -> DEAD + new frame
//   * FRAME_FIFO_AFULL -> COOLDOWN
//   * normal event packet
//   * overflow event packet with FIFO ID
//   * event priority over normal payload traffic
//
// The arbiter model returns a popped word one clock after do_pop_slot, which
// matches the skid-buffer intent in packet_builder.
//
// NOTE: The uploaded DUT source contains a few syntax/RTL issues that should
// be fixed before compiling this testbench.  See the comments near the end
// of this file for the important ones.
// ============================================================================

module tb_packet_builder;

    localparam int N_CH = 4;
    localparam int ID_W = $clog2(N_CH);
    localparam int FIFO_DEPTH = 32;
    localparam time CLK_PERIOD = 13.333ns; // ~75 MHz

    logic CLK75M;
    logic rst_n;

    // ------------------------------------------------------------------------
    // DUT <-> local event handler
    // ------------------------------------------------------------------------
    logic        event_valid;
    logic [3:0]  event_type;
    logic [2:0]  event_fifo_id;
    logic [44:0] event_time0;
    logic [44:0] event_time1;
    logic        event_ack;

    // ------------------------------------------------------------------------
    // DUT <-> arbiter
    // ------------------------------------------------------------------------
    logic             data_valid;
    logic [15:0]      FIFO_DAT;
    logic [ID_W-1:0]  SEL_ID;
    logic [N_CH-1:0]  EMPTY;
    logic             do_pop_slot;

    // ------------------------------------------------------------------------
    // DUT <-> frame FIFO
    // ------------------------------------------------------------------------
    logic        FRAME_FIFO_AFULL;
    logic [15:0] DATA_2_FIFO;
    logic        FRAME_FIFO_PUSH;

    // ------------------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------------------
    packet_builder #(.N_CH(N_CH)) dut (
        .CLK75M          (CLK75M),
        .rst_n           (rst_n),

        .event_valid     (event_valid),
        .event_type      (event_type),
        .event_fifo_id   (event_fifo_id),
        .event_time0     (event_time0),
        .event_time1     (event_time1),
        .event_ack       (event_ack),

        .data_valid      (data_valid),
        .FIFO_DAT        (FIFO_DAT),
        .SEL_ID          (SEL_ID),
        .EMPTY           (EMPTY),

        .do_pop_slot     (do_pop_slot),

        .FRAME_FIFO_AFULL(FRAME_FIFO_AFULL),
        .DATA_2_FIFO     (DATA_2_FIFO),
        .FRAME_FIFO_PUSH (FRAME_FIFO_PUSH)
    );

    // ------------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------------
    initial begin
        CLK75M = 1'b0;
        forever #(CLK_PERIOD/2.0) CLK75M = ~CLK75M;
    end

    // ------------------------------------------------------------------------
    // Simple FIFO model used by the arbiter model.
    // The model always selects the lowest-numbered non-empty channel.
    // ------------------------------------------------------------------------
    logic [15:0] fifo_mem [0:N_CH-1][0:FIFO_DEPTH-1];
    integer fifo_count [0:N_CH-1];
    integer fifo_rd_ptr [0:N_CH-1];
    integer fifo_wr_ptr [0:N_CH-1];

    integer ch;
    integer sel_ch;
    logic [ID_W-1:0] response_id;
    logic [15:0]      response_data;

    integer k;

    always_comb begin
        EMPTY = '0;
        sel_ch = -1;

        for (k = 0; k < N_CH; k = k + 1) begin
            EMPTY[k] = (fifo_count[k] == 0);
            if ((sel_ch == -1) && (fifo_count[k] != 0)) begin
                sel_ch = k;
            end
        end

        // Hold the ID associated with the currently valid response.  Between
        // responses the combinational value is simply the currently selected
        // FIFO, which lets packet_builder inspect the next channel in
        // PAYLOAD_X.
        if (data_valid) begin
            SEL_ID = response_id;
        end
        else if (sel_ch >= 0) begin
            SEL_ID = sel_ch[ID_W-1:0];
        end
        else begin
            SEL_ID = '0;
        end
    end

    // Response timing: request at cycle N -> data_valid at cycle N+1.
    always_ff @(posedge CLK75M or negedge rst_n) begin
        if (!rst_n) begin
            data_valid  <= 1'b0;
            FIFO_DAT    <= 16'h0000;
            response_id <= '0;
            response_data <= 16'h0000;
        end
        else begin
            data_valid <= 1'b0;

            if (do_pop_slot) begin
                // Select the lowest non-empty FIFO at the time of the request.
                if (sel_ch >= 0) begin
                    response_id   <= sel_ch[ID_W-1:0];
                    response_data <= fifo_mem[sel_ch][fifo_rd_ptr[sel_ch]];

                    FIFO_DAT <= fifo_mem[sel_ch][fifo_rd_ptr[sel_ch]];
                    data_valid <= 1'b1;

                    fifo_rd_ptr[sel_ch] <=
                        (fifo_rd_ptr[sel_ch] == FIFO_DEPTH-1) ? 0 : fifo_rd_ptr[sel_ch] + 1;
                    fifo_count[sel_ch] <= fifo_count[sel_ch] - 1;
                end
                else begin
                    $error("do_pop_slot asserted while all input FIFOs are empty at t=%0t", $time);
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Scoreboard for frame FIFO output
    // ------------------------------------------------------------------------
    logic [15:0] observed [0:255];
    integer observed_count;

    always @(posedge CLK75M) begin
        if (!rst_n) begin
            // scoreboard reset is handled in reset_tb / clear_scoreboard
        end
        else if (FRAME_FIFO_PUSH) begin
            if (observed_count < 256) begin
                observed[observed_count] = DATA_2_FIFO;
                observed_count = observed_count + 1;
            end
            else begin
                $fatal(1, "Scoreboard overflow");
            end
        end
    end

    // ------------------------------------------------------------------------
    // Basic protocol sanity checks.
    // ------------------------------------------------------------------------
    always @(posedge CLK75M) begin
        if (rst_n) begin
            if (FRAME_FIFO_PUSH && (dut.curr_state == 5'd0))
                $error("FRAME_FIFO_PUSH asserted in IDLE at t=%0t", $time);

            if (FRAME_FIFO_PUSH && (dut.curr_state == 5'd9))
                $error("FRAME_FIFO_PUSH asserted in COOLDOWN at t=%0t", $time);

            if (FRAME_FIFO_PUSH && (dut.curr_state == 5'd18))
                $error("FRAME_FIFO_PUSH asserted in WAIT_ACK at t=%0t", $time);
        end
    end

    // ------------------------------------------------------------------------
    // Tasks
    // ------------------------------------------------------------------------

    task automatic clear_scoreboard;
        begin
            observed_count = 0;
        end
    endtask

    task automatic clear_input_fifos;
        integer i;
        begin
            for (i = 0; i < N_CH; i = i + 1) begin
                fifo_count[i] = 0;
                fifo_rd_ptr[i] = 0;
                fifo_wr_ptr[i] = 0;
            end
        end
    endtask

    task automatic fifo_push_word(input integer fifo_id, input logic [15:0] word);
        begin
            if (fifo_id < 0 || fifo_id >= N_CH)
                $fatal(1, "fifo_push_word: bad fifo_id=%0d", fifo_id);

            if (fifo_count[fifo_id] >= FIFO_DEPTH)
                $fatal(1, "FIFO %0d overflow in testbench", fifo_id);

            fifo_mem[fifo_id][fifo_wr_ptr[fifo_id]] = word;
            fifo_wr_ptr[fifo_id] =
                (fifo_wr_ptr[fifo_id] == FIFO_DEPTH-1) ? 0 : fifo_wr_ptr[fifo_id] + 1;
            fifo_count[fifo_id] = fifo_count[fifo_id] + 1;
        end
    endtask

    task automatic clear_expected_and_check(
        input integer exp_count,
        input logic [15:0] exp0,
        input logic [15:0] exp1,
        input logic [15:0] exp2,
        input logic [15:0] exp3,
        input logic [15:0] exp4,
        input logic [15:0] exp5,
        input logic [15:0] exp6,
        input logic [15:0] exp7,
        input logic [15:0] exp8,
        input logic [15:0] exp9,
        input logic [15:0] exp10,
        input logic [15:0] exp11,
        input logic [15:0] exp12,
        input logic [15:0] exp13,
        input logic [15:0] exp14,
        input logic [15:0] exp15,
        input logic [15:0] exp16,
        input logic [15:0] exp17,
        input logic [15:0] exp18,
        input logic [15:0] exp19,
        input logic [15:0] exp20
    );
        logic [15:0] e [0:20];
        integer i;
        begin
            e[0]=exp0; e[1]=exp1; e[2]=exp2; e[3]=exp3; e[4]=exp4;
            e[5]=exp5; e[6]=exp6; e[7]=exp7; e[8]=exp8; e[9]=exp9;
            e[10]=exp10; e[11]=exp11; e[12]=exp12; e[13]=exp13; e[14]=exp14;
            e[15]=exp15; e[16]=exp16; e[17]=exp17; e[18]=exp18; e[19]=exp19;
            e[20]=exp20;

            repeat (20) @(posedge CLK75M);

            if (observed_count != exp_count) begin
                $error("Expected %0d frame words, observed %0d", exp_count, observed_count);
            end

            for (i = 0; i < exp_count; i = i + 1) begin
                if (observed[i] !== e[i]) begin
                    $error("Word %0d mismatch: expected %04h, observed %04h",
                           i, e[i], observed[i]);
                end
            end

            $display("  Observed %0d output words:", observed_count);
            for (i = 0; i < observed_count; i = i + 1)
                $display("    [%0d] %04h", i, observed[i]);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            event_valid = 1'b0;
            event_type = 4'h0;
            event_fifo_id = 3'h0;
            event_time0 = 45'h0;
            event_time1 = 45'h0;
            FRAME_FIFO_AFULL = 1'b0;
            clear_input_fifos();
            clear_scoreboard();
            repeat (4) @(posedge CLK75M);
            rst_n = 1'b1;
            repeat (3) @(posedge CLK75M);
        end
    endtask

    task automatic send_event(
        input logic [3:0] type_i,
        input logic [2:0] fifo_i,
        input logic [44:0] t0_i,
        input logic [44:0] t1_i
    );
        begin
            event_type    = type_i;
            event_fifo_id = fifo_i;
            event_time0   = t0_i;
            event_time1   = t1_i;
            event_valid   = 1'b1;

            // event_valid is synchronized inside the DUT, so hold it until
            // event_ack returns high and then release it.
            wait (event_ack === 1'b1);
            @(posedge CLK75M);
            event_valid = 1'b0;

            // Allow the DUT's synchronized event_valid to return low and the
            // WAIT_ACK -> IDLE transition to complete.
            repeat (4) @(posedge CLK75M);
        end
    endtask

    // ------------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------------
    initial begin : TESTS
        integer errors_before;

        // Default assignments.
        rst_n = 1'b0;
        event_valid = 1'b0;
        event_type = 4'h0;
        event_fifo_id = 3'h0;
        event_time0 = 45'h0;
        event_time1 = 45'h0;
        FRAME_FIFO_AFULL = 1'b0;
        observed_count = 0;

        clear_input_fifos();

        // ====================================================================
        // TEST 1: one normal payload word
        // ====================================================================
        $display("\nTEST 1: basic single-word frame");
        reset_dut();
        fifo_push_word(0, 16'h1234);

        clear_scoreboard();

        // Expected:
        // FACE SC 0000 C0DE CID PAYLOAD DEAD
        repeat (60) @(posedge CLK75M);

        clear_expected_and_check(
            7,
            16'hFACE, 16'h5343, 16'h0000, 16'hC0DE,
            16'h0000, 16'h1234, 16'hDEAD,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 2: reserved payload must emit BEEF then payload^FFFF
        // ====================================================================
        $display("\nTEST 2: reserved-word escaping");
        reset_dut();
        fifo_push_word(0, 16'hC0DE);
        clear_scoreboard();
        repeat (60) @(posedge CLK75M);

        // C0DE -> BEEF, 3F21
        clear_expected_and_check(
            8,
            16'hFACE, 16'h5343, 16'h0000, 16'hC0DE,
            16'h0000, 16'hBEEF, 16'h3F21, 16'hDEAD,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 3: multiple payloads on the same channel
        // ====================================================================
        $display("\nTEST 3: multiple payload words, same channel");
        reset_dut();
        fifo_push_word(1, 16'h1111);
        fifo_push_word(1, 16'h2222);
        fifo_push_word(1, 16'h3333);
        clear_scoreboard();
        repeat (100) @(posedge CLK75M);

        clear_expected_and_check(
            9,
            16'hFACE, 16'h5343, 16'h0000, 16'hC0DE,
            16'h0001, 16'h1111, 16'h2222, 16'h3333, 16'hDEAD,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 4: channel increases -> C0DE + new CID, same frame
        // ====================================================================
        $display("\nTEST 4: channel-ID increase");
        reset_dut();
        fifo_push_word(0, 16'hAAAA);
        fifo_push_word(1, 16'hBBBB);
        clear_scoreboard();
        repeat (100) @(posedge CLK75M);

        // Intended sequence:
        // FACE SC meta C0DE CID0 AAAA C0DE CID1 BBBB DEAD
        clear_expected_and_check(
            10,
            16'hFACE, 16'h5343, 16'h0000, 16'hC0DE,
            16'h0000, 16'hAAAA, 16'hC0DE, 16'h0001,
            16'hBBBB, 16'hDEAD,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 5: channel wrap -> DEAD then new frame
        //
        // IMPORTANT: this test intentionally checks the intended behavior.
        // With the current uploaded RTL, the buffered lower-ID word appears
        // to be discarded because PAYLOAD_X -> FRAME_START does not set
        // payload_pending, while HDR_WORD will issue another pop.  This test
        // should therefore expose that issue rather than hiding it.
        // ====================================================================
        $display("\nTEST 5: channel-ID wrap / frame restart");
        reset_dut();
        fifo_push_word(1, 16'hAAAA);
        fifo_push_word(0, 16'hBBBB);
        clear_scoreboard();
        repeat (140) @(posedge CLK75M);

        // Intended sequence:
        // frame0: FACE SC 0000 C0DE CID1 AAAA DEAD
        // frame1: FACE SC 0001 C0DE CID0 BBBB DEAD
        clear_expected_and_check(
            14,
            16'hFACE,16'h5343,16'h0000,16'hC0DE,16'h0001,16'hAAAA,16'hDEAD,
            16'hFACE,16'h5343,16'h0001,16'hC0DE,16'h0000,16'hBBBB,16'hDEAD,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 6: FRAME_FIFO_AFULL must enter COOLDOWN and resume afterward
        // ====================================================================
        $display("\nTEST 6: frame FIFO almost-full cooldown");
        reset_dut();
        fifo_push_word(0, 16'h1001);
        fifo_push_word(0, 16'h1002);
        clear_scoreboard();

        // Let the first payload be emitted, then force almost-full.  The next
        // state is PAYLOAD_X, where the DUT should enter COOLDOWN.
        wait (observed_count >= 6);
        @(negedge CLK75M);
        FRAME_FIFO_AFULL = 1'b1;
        repeat (3) @(posedge CLK75M);

        // Keep AFULL asserted for at least one cycle in COOLDOWN.
        if (dut.curr_state != 5'd9)
            $error("TEST 6: expected COOLDOWN (state 9), got state %0d", dut.curr_state);

        @(negedge CLK75M);
        FRAME_FIFO_AFULL = 1'b0;

        repeat (80) @(posedge CLK75M);

        clear_expected_and_check(
            8,
            16'hFACE,16'h5343,16'h0000,16'hC0DE,
            16'h0000,16'h1001,16'h1002,16'hDEAD,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 7: normal event packet (type != 0)
        // ====================================================================
        $display("\nTEST 7: normal event packet");
        reset_dut();
        clear_scoreboard();

        // 45-bit time values. The DUT exports each time as 3 x 16-bit words,
        // with event_time0 zero-extended to 48 bits.
        fork
            send_event(
                4'h3,
                3'h0,
                45'h012_3456_789A,
                45'h01A_BCDE_F012
            );
        join

        clear_expected_and_check(
            10,
            16'hFACE, 16'h4556, 16'h0003,
            16'h789A, 16'h3456, 16'h0012,
            // time1 expected low 48-bit chunks
            16'hF012, 16'hBCDE, 16'h001A,
            16'hDEAD,
            16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 8: overflow event packet (type == 0) includes FIFO ID
        // ====================================================================
        $display("\nTEST 8: overflow event packet");
        reset_dut();
        clear_scoreboard();

        fork
            send_event(
                4'h0,
                3'h5,
                45'h055_1234_5678,
                45'h066_9ABC_DEF0
            );
        join

        // Intended sequence:
        // FACE EV 0000 t0[15:0] t0[31:16] t0[47:32]
        // 0005 t1[15:0] t1[31:16] t1[47:32] DEAD
        clear_expected_and_check(
            11,
            16'hFACE,16'h4556,16'h0000,
            16'h5678,16'h1234,16'h0055,
            16'h0005,
            16'hDEF0,16'h9ABC,16'h0066,
            16'hDEAD,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,
            16'h0000,16'h0000,16'h0000,16'h0000,16'h0000
        );

        // ====================================================================
        // TEST 9: event has priority over normal packet generation
        // ====================================================================
        $display("\nTEST 9: event priority over normal FIFO traffic");
        reset_dut();
        fifo_push_word(0, 16'hCAFE);
        clear_scoreboard();

        // Assert event before the normal packet has a chance to start.
        event_type    = 4'h2;
        event_fifo_id = 3'h0;
        event_time0   = 45'h001_1111_2222;
        event_time1   = 45'h001_3333_4444;
        event_valid   = 1'b1;

        // The first output should be FACE for the event packet.  There should
        // be no SC science header before it.
        wait (observed_count >= 1);
        if (observed[0] !== 16'hFACE)
            $error("TEST 9: event did not get first packet-build priority");

        wait (event_ack === 1'b1);
        @(posedge CLK75M);
        event_valid = 1'b0;
        repeat (10) @(posedge CLK75M);

        // Now the normal payload should be processed as a separate packet.
        repeat (100) @(posedge CLK75M);

        if (observed_count < 17)
            $error("TEST 9: expected event plus normal packet output, observed only %0d words",
                   observed_count);

        // ====================================================================
        // Finish
        // ====================================================================
        $display("\n============================================================");
        $display("packet_builder testbench completed");
        $display("============================================================\n");
        $finish;
    end

    // ------------------------------------------------------------------------
    // Optional waveform dump
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_packet_builder.vcd");
        $dumpvars(0, tb_packet_builder);
    end

endmodule
