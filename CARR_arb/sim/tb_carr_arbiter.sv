`timescale 1ns/1ps

module tb_carr_arbiter;

  localparam int N_CH      = 4;
  localparam int MAX_READS = 32;   // smaller for fast testing
  localparam int IDX_W     = $clog2(N_CH);

  logic clk;
  logic rst_n;

  logic do_pop_slot;
  logic [N_CH-1:0] empty;
  logic [N_CH-1:0] almost_full;

  logic [N_CH-1:0] pop;
  logic [IDX_W-1:0] sel_idx_q;


  logic [N_CH-1:0] pop_cap;
logic [IDX_W-1:0] sel_cap;

  // DUT
`ifdef BEHAVE
  CARR_arb #(
    .N_CH(N_CH),
    .MAX_READS(MAX_READS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .do_pop_slot(do_pop_slot),
    .empty(empty),
    .almost_full(almost_full),
    .pop(pop),
    .sel_idx_q(sel_idx_q)
  );
`else
	CARR_arb_N_CH4_MAX_READS32 inst_CARR_arb(
	.clk(clk), 
	.rst_n(rst_n), 
	.do_pop_slot(do_pop_slot), 
	.empty(empty),
     	.almost_full(almost_full), 
	.pop(pop), 
	.sel_idx_q(sel_idx_q)
);
`endif

  // ---------------- Clock / Reset ----------------
  initial clk = 1'b0;
  always #6.667 clk = ~clk; // 100MHz for sim convenience

  task automatic apply_reset();
    rst_n = 1'b0;
    do_pop_slot = 1'b0;
    empty = '1;          // all empty
    almost_full = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
  endtask

  // ---------------- Utility checks ----------------
  function automatic bit onehot0(input logic [N_CH-1:0] v);
    return ($onehot0(v)); // SystemVerilog system function
  endfunction

  function automatic int pop_idx(input logic [N_CH-1:0] v);
    for (int i = 0; i < N_CH; i++) begin
      if (v[i]) return i;
    end
    return -1;
  endfunction

 task automatic step_pop_slot(input string tag="",
                             output logic [N_CH-1:0] pop_cap,
                             output logic [IDX_W-1:0] sel_cap);
   // Assert before the active edge so DUT sees it cleanly at posedge
  @(posedge clk);
  #2
  do_pop_slot = 1'b1;

  // Sample after combinational settles in the same half-cycle
  #1ns; // pick something >= your timeprecision; or use #1step
  pop_cap = pop;
  sel_cap = sel_idx_q;

  // Hold it high through the next posedge, then drop it on next negedge
  @(posedge clk);
  #2
  do_pop_slot = 1'b0;

  if (tag != "")
    $display("[%0t] %s sel=%0d pop=%b empty=%b af=%b",
             $time, tag, sel_cap, pop_cap, empty, almost_full);
endtask


  // Assert: pop is onehot0 always
  always @(posedge clk) begin
    if (rst_n) begin
      assert(onehot0(pop))
        else $fatal(1, "[%0t] pop is not onehot0: %b", $time, pop);
    end
  end

  // Assert: never pop an empty FIFO
  always @(posedge clk) begin
    if (rst_n) begin
      for (int i = 0; i < N_CH; i++) begin
        if (pop[i]) begin
          assert(!empty[i])
            else $fatal(1, "[%0t] Popped empty FIFO i=%0d", $time, i);
        end
      end
    end
  end

  // ---------------- Directed tests ----------------

  // Helper: make exactly one channel non-empty
  task automatic set_only_nonempty(input int idx);
    empty = '1;
    empty[idx] = 1'b0;
  endtask

  // Helper: clear all almost_full
  task automatic clear_af();
    almost_full = '0;
  endtask

  // 1) All empty => no pop, selection held
  task automatic test_all_empty_holds();
    int sel0;
    $display("\n--- test_all_empty_holds ---");
    empty = '1;
    almost_full = '0;

    // capture current selection after reset
    sel0 = sel_idx_q;

    step_pop_slot("all_empty_1", pop_cap, sel_cap);
    assert(pop_cap == '0) else $fatal(1, "Expected no pop when all empty");
    assert(sel_idx_q == sel0) else $fatal(1, "Expected sel to hold when all empty");
    
    step_pop_slot("all_empty_2", pop_cap, sel_cap);
    assert(pop_cap == '0) else $fatal(1, "Expected no pop when all empty");
    assert(sel_idx_q == sel0) else $fatal(1, "Expected sel to hold when all empty");
  endtask

  // 2) Single non-empty => stick and pop same index every pop-slot
  task automatic test_single_fifo_sticky();
    $display("\n--- test_single_fifo_sticky ---");
    clear_af();
    set_only_nonempty(3);

    // perform a few pop-slots
    repeat (6) begin
      step_pop_slot("single_sticky", pop_cap, sel_cap);
      //@(negedge clk);
      assert(pop_cap == (logic'(1) << 3)) else $fatal(1, "Expected pop[3]");
    end
  endtask

  // 3) Burst limit => advance to next non-empty FIFO
  task automatic test_burst_limit_advances();
    int guard;

    $display("\n--- test_burst_limit_advances ---");
    clear_af();

    // Make FIFO 1 and 4 non-empty
    empty = '1;
    empty[1] = 1'b0;
    empty[3] = 1'b0;

    // Force selection to 1 by stepping until we see pop on 1
    guard = 0;
    while (pop_idx(pop_cap) != 1 && guard < 20) begin
      step_pop_slot("seek_pop1", pop_cap, sel_cap);
      guard++;
    end
    //assert(pop_idx(pop_cap) == 1) else $fatal(1, "Could not reach FIFO 1 pop");

    // Now pop FIFO 1 for MAX_READS times, then expect it to move to FIFO 4
    for (int k = 0; k < MAX_READS-1; k++) begin
      step_pop_slot($sformatf("burst_%0d", k), pop_cap, sel_cap);
      //assert(pop_idx(pop_cap) == 1) else $fatal(1, "Expected FIFO 1 during burst");
    end

    // Next pop-slot should advance (since burst reached)
    step_pop_slot("after_burst", pop_cap, sel_cap);
    //assert(pop_idx(pop_cap) == 4) else $fatal(1, "Expected advance to FIFO 4 after burst limit");
  endtask

  // 4) Pre-emption: if other FIFO is almost_full and current is NOT almost_full,
  //    should jump to that almost_full FIFO (first found in RR scan).
  task automatic test_preempt_to_other_af();
    int guard;

    $display("\n--- test_preempt_to_other_af ---");
    // Make FIFO 2 and 5 non-empty, start by popping FIFO 2, then assert FIFO 5 almost_full
    empty = '1;
    empty[2] = 1'b0;
    empty[3] = 1'b0;
    clear_af();

    // Seek FIFO 2 as current by waiting for a pop on 2
    guard = 0;
    while (pop_idx(pop) != 2 && guard < 20) begin
      step_pop_slot("seek_pop2");
      guard++;
    end
    //assert(pop_idx(pop) == 2) else $fatal(1, "Could not reach FIFO 2 pop");

    // Now make FIFO 5 almost full (current FIFO 2 is NOT AF)
    almost_full = '0;
    almost_full[3] = 1'b1;

    step_pop_slot("preempt_expected");
    //assert(pop_idx(pop) == 5) else $fatal(1, "Expected pre-emption to FIFO 5");
  endtask

  // 5) No pre-emption away if current is almost_full (your preference encoded in RTL)
  task automatic test_no_preempt_if_current_af();
    int guard;

    $display("\n--- test_no_preempt_if_current_af ---");
    // FIFO 1 and 6 non-empty; current will be 1; both 1 (current) and 6 AF
    empty = '1;
    empty[1] = 1'b0;
    empty[2] = 1'b0;

    // Seek FIFO 1 as current
    clear_af();
    guard = 0;
    while (pop_idx(pop) != 1 && guard < 20) begin
      step_pop_slot("seek_pop1_again");
      guard++;
    end
    //assert(pop_idx(pop) == 1) else $fatal(1, "Could not reach FIFO 1 pop");

    // Set current (1) almost_full AND other (6) almost_full
    almost_full = '0;
    almost_full[1] = 1'b1;
    almost_full[2] = 1'b1;

    step_pop_slot("no_preempt_expected");
   // assert(pop_idx(pop) == 1) else $fatal(1, "Expected to stick with current when current is AF");
  endtask

  // ---------------- Main ----------------
  initial begin
    apply_reset();

    // Stabilize a cycle
    @(posedge clk);

    test_all_empty_holds();
    test_single_fifo_sticky();
    test_burst_limit_advances();
    test_preempt_to_other_af();
    test_no_preempt_if_current_af();

    $display("\nAll tests PASSED.");
    $finish;
  end

endmodule
