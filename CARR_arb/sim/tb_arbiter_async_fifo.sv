`timescale 1ns/1ps

module tb_async_fifo_arb;

  // ---------------- Params ----------------
  parameter int FIFO_num  = 8;
  parameter int MAX_read  = 32;

  parameter int DEPTH         = 256;
  parameter int AFULL_MARGIN  = 4;

  // ---------------- Clocks / resets ----------------
  logic wclk, wrst_n;
  logic rclk, rrst_n;

  // Arbiter control
  logic do_pop_slot;

  // FIFO write logic
  logic [FIFO_num-1:0] wpush;
  wire  [FIFO_num-1:0] wfull;
  wire  [FIFO_num-1:0] walmost_full;

  // FIFO read logic
  wire  [FIFO_num-1:0] rpop;         // driven by arbiter
  wire  [FIFO_num-1:0] rempty;
  wire  [FIFO_num-1:0] ralmost_full;

  wire [$clog2(FIFO_num)-1:0] sel_idx_q;

  // ---------------- DUTs ----------------
  genvar i;
  generate
    for (i = 0; i < FIFO_num; i++) begin : G_FIFOS
      async_fifo_ptr #(
        .DEPTH(DEPTH),
        .AFULL_MARGIN(AFULL_MARGIN)
      ) u_fifo (
        .wclk         (wclk),
        .wrst_n       (wrst_n),
        .wpush        (wpush[i]),
        .wfull        (wfull[i]),
        .walmost_full (walmost_full[i]),

        .rclk         (rclk),
        .rrst_n       (rrst_n),
        .rpop         (rpop[i]),
        .rempty       (rempty[i]),
        .ralmost_full (ralmost_full[i]),
        .rused        (/*unused*/)
      );
    end
  endgenerate

  CARR_arb #(
    .N_CH(FIFO_num),
    .MAX_READS(8)
  ) CARR_arb_inst (
    .clk         (rclk),
    .rst_n       (rrst_n),
    .do_pop_slot (do_pop_slot),
    .empty       (rempty),
    .almost_full (ralmost_full),
    .pop         (rpop),
    .sel_idx_q   (sel_idx_q)
  );

  // ---------------- Clock gen ----------------
  initial begin
    rclk = 0;
    wclk = 0;
  end

  // write clock at 40 MHz => period 25ns => half 12.5ns
  always #12.5 wclk = ~wclk;

  // read clock at 75 MHz => period 13.333..ns => half 6.666..ns
  // your 6.65 is close; use 6.666 for accuracy if you want
  always #6.666 rclk = ~rclk;

  // ---------------- Helpers ----------------

  // drive do_pop_slot as a clean 1-cycle pulse in rclk domain
  task automatic pulse_pop_slot();
    @(negedge rclk);
    do_pop_slot = 1'b1;
    @(negedge rclk);
    do_pop_slot = 1'b0;
  endtask

  // push N words into FIFO idx (in write clock domain), respecting wfull
  task automatic push_words(input int idx, input int nwords);
    int pushed;
    pushed = 0;
    while (pushed < nwords) begin
      @(negedge wclk);
      wpush[idx] = '0;
      if (!wfull[idx]) begin
        wpush[idx] = 1'b1;
        pushed++;
      end
      @(negedge wclk);
      wpush[idx] = '0;
    end
  endtask

  // wait some rclk cycles (for pointer sync to settle)
  task automatic wait_rclk(input int n);
    repeat (n) @(posedge rclk);
  endtask

  // ---------------- Monitors / assertions ----------------
  // pop should be onehot0 at posedge when do_pop_slot is high
  always @(posedge rclk) begin
    if (rrst_n && do_pop_slot) begin
      assert($onehot0(rpop))
        else $fatal(1, "[%0t] ERROR: rpop not onehot0: %b", $time, rpop);

      for (int k = 0; k < FIFO_num; k++) begin
        if (rpop[k]) begin
          assert(!rempty[k])
            else $fatal(1, "[%0t] ERROR: pop asserted when rempty[%0d]=1", $time, k);
        end
      end
    end
  end

  // optional: log decisions
  always @(posedge rclk) begin
    if (rrst_n && do_pop_slot) begin
      if (rpop != '0)
        $display("[%0t] sel=%0d pop=%b empty=%b af=%b",
                 $time, sel_idx_q, rpop, rempty, ralmost_full);
    end
  end

  // ---------------- Test sequence ----------------
  initial begin
  	int seen5;
  	int last, runlen, maxrun;
  	int p = -1;
    // init controls
    wpush = '0;
    do_pop_slot = 1'b0;

    // reset
    wrst_n = 1'b0;
    rrst_n = 1'b0;
    repeat (5) @(posedge wclk);
    repeat (5) @(posedge rclk);
    wrst_n = 1'b1;
    rrst_n = 1'b1;

    // allow synchronizers to settle
    wait_rclk(10);

    // ---------------------------------------------------
    // Phase 1: Seed all FIFOs so arbiter has data
    // ---------------------------------------------------
    $display("\n=== Phase 1: Seed all FIFOs ===");
    fork
      push_words(0, 40);
      push_words(1, 30);
      push_words(2, 20);
      push_words(3, 10);
      push_words(4, 25);
      push_words(5, 15);
      push_words(6, 35);
      push_words(7, 5);
    join

    // wait for write->read pointer sync (~2 rclk)
    wait_rclk(200);

    // run arbiter for a while (pop slots)
    repeat (80) pulse_pop_slot();

    // ---------------------------------------------------
    // Phase 2: Trigger congestion: make FIFO 5 almost full
    // Expect arbiter to pre-empt to FIFO 5 when current not AF
    // ---------------------------------------------------
    $display("\n=== Phase 2: Force FIFO5 almost-full, expect pre-emption ===");

    // top up FIFO5 close to full: push until walmost_full goes high
    // (use write-domain flag; then wait for read-domain ralmost_full to follow)
    while (!walmost_full[5] && !wfull[5]) begin
      @(negedge wclk);
      wpush = '0;
      wpush[5] = 1'b1;
      @(negedge wclk);
      wpush = '0;
    end

    // wait for ralmost_full[5] to go high (CDC latency)
    wait_rclk(20);
    assert(ralmost_full[5] === 1'b1)
      else $fatal(1, "FIFO5 did not become ralmost_full as expected");

    // run for a few pop-slots and check that FIFO5 gets serviced promptly

    seen5 = 0;
    repeat (20) begin
      pulse_pop_slot();
      // sample at posedge during slot: easiest is just check after pulse
      // (rpop is registered or stable during do_pop_slot in your implementation)
      if (rpop[5]) seen5++;
    end
    assert(seen5 > 0)
      else $fatal(1, "Did not observe any pops from FIFO5 during congestion window");

    // ---------------------------------------------------
    // Phase 3: Burst-limit behaviour: make two FIFOs non-empty
    // Expect after MAX_READS pops, arbiter advances RR to other
    // ---------------------------------------------------
    $display("\n=== Phase 3: Burst limit switching ===");

    // Clear congestion flags by draining a bit
    repeat (50) pulse_pop_slot();
    wait_rclk(10);

    // Ensure FIFO1 and FIFO2 have plenty of data
    fork
      push_words(1, 60);
      push_words(2, 60);
    join
    wait_rclk(10);

    // Now observe pattern: should not stay on one FIFO beyond MAX_READS repeatedly
   
    last = -1; runlen = 0; maxrun = 0;

    repeat (120) begin
      pulse_pop_slot();
      // find which FIFO popped

      for (int k = 0; k < FIFO_num; k++) if (rpop[k]) p = k;

      if (p != -1) begin
        if (p == last) runlen++;
        else begin
          if (runlen > maxrun) maxrun = runlen;
          last = p;
          runlen = 1;
        end
      end
    end
    if (runlen > maxrun) maxrun = runlen;

    $display("Observed maximum consecutive pops on same FIFO = %0d (MAX_READS=%0d)", maxrun, 8);
    assert(maxrun <= 9) // allow 1-cycle fuzz depending on how you count switch/reset
      else $fatal(1, "Burst limit appears violated (maxrun=%0d)", maxrun);

    $display("\nAll test phases completed.");
    $finish;
  end

endmodule
