`timescale 1ns/1ps

module tb_CARR_arb;

  localparam int N_CH  = 8;
  localparam int IDX_W = $clog2(N_CH);

  // --------------------------------------------------------------------------
  // DUT signals
  // --------------------------------------------------------------------------
  logic                   clk;
  logic                   rst_n;

  logic [9:0]             MAX_READS;
  logic                   do_pop_slot;

  logic [N_CH-1:0]        empty;
  logic [N_CH-1:0]        almost_full;

  logic [N_CH-1:0]        pop;
  logic [IDX_W-1:0]       sel_idx_q;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  CARR_arb #(
    .N_CH(N_CH)
  ) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .MAX_READS    (MAX_READS),
    .do_pop_slot  (do_pop_slot),
    .empty        (empty),
    .almost_full  (almost_full),
    .pop          (pop),
    .sel_idx_q    (sel_idx_q)
  );

  // --------------------------------------------------------------------------
  // 75 MHz clock
  // Period = 13.333 ns
  // --------------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #6.666 clk = ~clk;
  end

  // --------------------------------------------------------------------------
  // Test bookkeeping
  // --------------------------------------------------------------------------
  int test_count = 0;
  int error_count = 0;

  // --------------------------------------------------------------------------
  // Helper: print current DUT state
  // --------------------------------------------------------------------------
  task automatic print_state(string prefix);
    $display(
      "[%0t] %s | MAX_READS=%0d empty=%b almost_full=%b do_pop=%b sel=%0d pop=%b",
      //"sel=%0d burst=%0d pop=%b",
      // Uncomment burst counter if useful
      
      $time,
      prefix,
      MAX_READS,
      empty,
      almost_full,
      do_pop_slot,
      sel_idx_q,
      pop
      //dut.burst_cnt_q
    );
  endtask

  // --------------------------------------------------------------------------
  // Check combinational pop before the next rising edge.
  //
  // Since pop is combinational in the DUT, it represents the slot that will
  // be consumed during this pop slot.
  // --------------------------------------------------------------------------
  task automatic check_pop(
    input int expected_sel,
    input bit expected_valid = 1'b1
  );
    logic [N_CH-1:0] expected_pop;

    expected_pop = '0;

    if (expected_valid)
      expected_pop[expected_sel] = 1'b1;

    #1;

    test_count++;

    if (pop !== expected_pop) begin
      $error(
        "[%0t] TEST %0d FAILED: pop mismatch.\n Expected pop=%b, got pop=%b, expected_sel=%0d",
        $time,
        test_count,
        expected_pop,
        pop,
        expected_sel
      );
      error_count++;
    end
    else begin
      $display(
        "[%0t] TEST %0d PASS: pop=%b, selected=%0d",
        $time,
        test_count,
        pop,
        expected_sel
      );
    end
  endtask

  // --------------------------------------------------------------------------
  // Perform one pop slot.
  //
  // Inputs are changed on negedge so that they are stable before posedge.
  // pop is checked before posedge.
  // sel_idx_q is checked after posedge.
  // --------------------------------------------------------------------------
  task automatic do_slot(
    input int expected_sel,
    input bit expected_valid = 1'b1
  );

    @(negedge clk);

    do_pop_slot = 1'b1;

    #1;

    check_pop(expected_sel, expected_valid);

    @(posedge clk);
    #1;

    if (expected_valid) begin
      if (sel_idx_q !== expected_sel[IDX_W-1:0]) begin
        $error(
          "[%0t] sel_idx_q mismatch: expected=%0d got=%0d",
          $time,
          expected_sel,
          sel_idx_q
        );
        error_count++;
      end
    end

    @(negedge clk);
    do_pop_slot = 1'b0;
  endtask

  // --------------------------------------------------------------------------
  // Reset
  // --------------------------------------------------------------------------
  task automatic reset_dut;
    begin
      rst_n         = 1'b0;
      MAX_READS     = 10'd32;
      do_pop_slot   = 1'b0;
      empty         = '1;
      almost_full   = '0;

      #20;

      rst_n = 1'b1;

      @(posedge clk);
      #1;

      if (sel_idx_q !== '0) begin
        $error(
          "[%0t] Reset FAILED: sel_idx_q expected 0, got %0d",
          $time,
          sel_idx_q
        );
        error_count++;
      end
      else begin
        $display("[%0t] Reset PASS", $time);
      end

      @(negedge clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // Main test sequence
  // --------------------------------------------------------------------------
  initial begin

    // Initial values
    clk          = 1'b0;
    rst_n        = 1'b1;
    MAX_READS    = 10'd32;
    do_pop_slot  = 1'b0;
    empty        = '1;
    almost_full  = '0;

    // ========================================================================
    // TEST 1: Reset
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 1: RESET");
    $display("============================================================");

    reset_dut();


    // ========================================================================
    // TEST 2: No pop slot
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 2: NO POP WHEN do_pop_slot=0");
    $display("============================================================");

    @(negedge clk);

    empty[0] = 1'b0;

    #1;

    if (pop !== '0) begin
      $error("[%0t] pop should be zero when do_pop_slot=0", $time);
      error_count++;
    end
    else begin
      $display("[%0t] TEST PASS: pop=0 when do_pop_slot=0", $time);
    end


    // ========================================================================
    // TEST 3: Select first non-empty FIFO
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 3: FIRST NON-EMPTY FIFO");
    $display("============================================================");

    // Current selector is 0.
    // FIFO 0 empty, FIFO 3 available.
    empty = '1;
    empty[3] = 1'b0;

    do_slot(3);


    // ========================================================================
    // TEST 4: Skip current FIFO if it becomes empty
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 4: SKIP EMPTY CURRENT FIFO");
    $display("============================================================");

    // Current selector is now 3.
    // Make FIFO 3 empty and FIFO 5 available.
    empty = '1;
    empty[5] = 1'b0;

    do_slot(5);


    // ========================================================================
    // TEST 5: MAX_READS = 4
    //
    // FIFOs 0 and 1 are available.
    //
    // Starting at FIFO 0:
    //   pop #1 -> 0
    //   pop #2 -> 0
    //   pop #3 -> 0
    //   pop #4 -> 0
    //   pop #5 -> 1
    //
    // This verifies that the configurable input really controls the burst
    // limit.
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 5: CONFIGURABLE MAX_READS = 4");
    $display("============================================================");

    reset_dut();

    MAX_READS   = 10'd4;
    empty       = '1;
    empty[0]    = 1'b0;
    empty[1]    = 1'b0;
    almost_full = '0;

    do_slot(0);
    do_slot(0);
    do_slot(0);
    do_slot(0);

    // On the 5th pop burst_cnt_q is 4, therefore >= MAX_READS.
    do_slot(1);


    // ========================================================================
    // TEST 6: Change MAX_READS dynamically
    //
    // Start with MAX_READS=4 and then change it to 2 while the arbiter is
    // already operating.
    //
    // After switching to FIFO 1, burst count = 1.
    // With MAX_READS=2:
    //   next -> FIFO 1 (burst becomes 2)
    //   next -> FIFO 0
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 6: DYNAMIC MAX_READS CHANGE");
    $display("============================================================");

    MAX_READS = 10'd2;

    do_slot(1);
    do_slot(0);


    // ========================================================================
    // TEST 7: MAX_READS = 1
    //
    // With two active FIFOs the arbiter should alternate:
    //   0, 1, 0, 1, ...
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 7: MAX_READS = 1");
    $display("============================================================");

    reset_dut();

    MAX_READS   = 10'd1;
    empty       = '1;
    empty[0]    = 1'b0;
    empty[1]    = 1'b0;
    almost_full = '0;

    do_slot(0);
    do_slot(1);
    do_slot(0);
    do_slot(1);
    do_slot(0);
    do_slot(1);


    // ========================================================================
    // TEST 8: almost_full pre-emption
    //
    // Current FIFO = 0
    // FIFO 0 is available but NOT almost full
    // FIFO 2 is available AND almost full
    //
    // The DUT should immediately prefer FIFO 2, independent of MAX_READS.
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 8: ALMOST_FULL PRE-EMPTION");
    $display("============================================================");

    reset_dut();

    MAX_READS      = 10'd100;
    empty          = '1;
    empty[0]       = 1'b0;
    empty[2]       = 1'b0;

    almost_full    = '0;
    almost_full[2] = 1'b1;

    do_slot(2);


    // ========================================================================
    // TEST 9: Stay on current FIFO when current FIFO is almost_full
    //
    // Current FIFO = 2
    // FIFO 2 is almost_full
    // FIFO 0 is available but not almost_full
    //
    // The DUT should stay on FIFO 2.
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 9: STAY ON CURRENT ALMOST_FULL FIFO");
    $display("============================================================");

    empty          = '1;
    empty[0]       = 1'b0;
    empty[2]       = 1'b0;

    almost_full    = '0;
    almost_full[2] = 1'b1;

    do_slot(2);


    // ========================================================================
    // TEST 10: MAX_READS still overrides normal sticking behavior
    //
    // Make current FIFO 2 almost_full and MAX_READS=2.
    //
    // The implementation checks the burst-limit condition first, then the
    // almost-full preference logic. This test documents the actual intended
    // behavior of the current RTL.
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 10: BURST LIMIT + ALMOST_FULL INTERACTION");
    $display("============================================================");

    reset_dut();

    MAX_READS       = 10'd2;

    empty           = '1;
    empty[0]        = 1'b0;
    empty[2]        = 1'b0;

    almost_full     = '0;
    almost_full[2]  = 1'b1;

    // First selection moves from 0 -> 2.
    do_slot(2);

    // burst count is now 1, so still FIFO 2.
    do_slot(2);

    // burst count is now 2 >= MAX_READS.
    // The fairness logic attempts to move to FIFO 0.
    // However, because FIFO 2 is almost_full, the final almost_full logic
    // does not pre-empt away from it.
    //
    // Therefore the current RTL keeps FIFO 2.
    do_slot(2);


    // ========================================================================
    // TEST 11: All FIFOs empty
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 11: ALL FIFOS EMPTY");
    $display("============================================================");

    empty        = '1;
    almost_full  = '0;

    do_slot(sel_idx_q, 1'b0);


    // ========================================================================
    // TEST 12: Large MAX_READS value
    //
    // 10-bit MAX_READS allows up to 1023.
    // Use 1023 to check the new full-width configuration.
    // ========================================================================
    $display("\n============================================================");
    $display("TEST 12: MAX_READS = 1023");
    $display("============================================================");

    reset_dut();

    MAX_READS   = 10'd1023;

    empty       = '1;
    empty[0]    = 1'b0;
    empty[1]    = 1'b0;

    almost_full = '0;

    // Just demonstrate that it continues to read FIFO 0 with such a large
    // limit. We don't need to perform 1023 cycles here.
    do_slot(0);
    do_slot(0);
    do_slot(0);
    do_slot(0);
    do_slot(0);


    // ========================================================================
    // Final result
    // ========================================================================
    $display("\n============================================================");
    $display("SIMULATION COMPLETE");
    $display("============================================================");

    if (error_count == 0) begin
      $display("ALL TESTS PASSED");
    end
    else begin
      $display("TEST FAILED: %0d errors detected", error_count);
    end

    $finish;
  end

endmodule