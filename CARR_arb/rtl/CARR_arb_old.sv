//`timescale 1ns/1ps

// Congestion aware round robin arbiter 
// It takes the following inputs:
// Empty [i]: fifo i empty flag
// almost_full [i]: fifo i almost empty, this would be a flag that is calculated, this should have been synced from the writing clock to our clock
// 
// Does the following outputs:
// rd_en [i]: read enable for fifo i
//
// Parameters:
// MAX_READS: maximum consecutive read from a single FIFO, by default it is 32

module CARR_arb #(
	parameter int N_CH = 8, 
	parameter int MAX_READS = 32)
	(
	input clk,    // 75 MHz clock
	input rst_n,  // Asynchronous reset active low

	input do_pop_slot, 			// "pop slot" enable (phase == 0 and downstream ready)

	input logic [N_CH-1:0] empty, 		// all the empty signals from FIFOs
	input logic [N_CH-1:0] almost_full,  // all the almost full signals from FIFOs
	

	output logic [N_CH-1:0] pop,  // one hot pop strobes
	output logic [$clog2(N_CH)-1:0] sel_idx_q    // selected channel (registered)

);

// parameter N_CH = 8;                // number of FIFOs to juggle
// parameter MAX_READS = 6'd32;	// max consecutive read for a single FIFO

localparam int IDX_W = $clog2(N_CH);
localparam int BC_W = $clog2(MAX_READS+1);


logic [IDX_W-1:0] sel_idx_d;  	// current FIFO index to read from 
logic [BC_W-1:0] burst_cnt_q, burst_cnt_d;		// the read count from the FIFO




// -------- combinational CARR selector --------
  function automatic logic [IDX_W-1:0] carr_select_idx(
    input logic [IDX_W-1:0] curr,
    input logic [BC_W-1:0]  burst_cnt,
    input logic [N_CH-1:0]  empty_i,
    input logic [N_CH-1:0]  af_i
  );
    logic [IDX_W-1:0] candidate;
    logic found;

    candidate = curr;

    // All empty => hold
    if (&empty_i) begin
      return candidate;
    end

    // If current empty => advance to next non-empty
    if (empty_i[curr]) begin
      found = 1'b0;
      for (int k = 1; k <= N_CH; k++) begin
        logic [IDX_W-1:0] j;
        j = (curr + k[IDX_W-1:0]) & (N_CH-1);  // OK for N_CH power of 2 (8)
        if (!empty_i[j] && !found) begin
          candidate = j;
          found = 1'b1;
        end
      end
      return candidate;
    end

    // Fairness: burst limit => next non-empty
    if (burst_cnt >= MAX_READS[BC_W-1:0]) begin
      found = 1'b0;
      for (int k = 1; k <= N_CH; k++) begin
        logic [IDX_W-1:0] j;
        j = (curr + k[IDX_W-1:0]) & (N_CH-1);
        if (!empty_i[j] && !found) begin
          candidate = j;
          found = 1'b1;
        end
      end
    end
    
    // If current is almost-full, prefer to stick (your preference)
    if (!af_i[curr]) begin
      // Pre-empt to first other almost-full in RR order
      found = 1'b0;
      for (int k = 1; k <= N_CH; k++) begin
        logic [IDX_W-1:0] j;
        j = (curr + k[IDX_W-1:0]) & (N_CH-1);
        if ((j != curr) && af_i[j] && !empty_i[j] && !found) begin
          candidate = j;
          found = 1'b1;
        end
      end
      if (found) return candidate;
    end

    

    return candidate;
  endfunction



  // -------- next-state + outputs --------
  always_comb begin
    // defaults: hold state, no pop
    sel_idx_d    = sel_idx_q;
    burst_cnt_d  = burst_cnt_q;
    pop          = '0;

    if (do_pop_slot) begin
      // choose next selection based on current observed flags
      sel_idx_d = carr_select_idx(sel_idx_q, burst_cnt_q, empty, almost_full);

      // issue pop if selected is non-empty
      if (!empty[sel_idx_d]) begin
        pop[sel_idx_d] = 1'b1;

        // burst count bookkeeping:
        // - if we switched FIFOs, reset then increment
        if (sel_idx_d != sel_idx_q) burst_cnt_d = '0;
        burst_cnt_d = burst_cnt_d + 1'b1;
      end else begin
        // nothing popped => reset burst
        burst_cnt_d = '0;
      end
    end
  end

  // -------- registers --------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sel_idx_q   <= '0;
      burst_cnt_q <= '0;
    end else begin
      sel_idx_q   <= sel_idx_d;
      burst_cnt_q <= burst_cnt_d;
    end
  end

endmodule
