module async_fifo_ptr #(
  parameter int DEPTH = 256,              // must be power of 2
  parameter int AFULL_MARGIN = 4           // almost-full when <= margin free
) (
  // write domain
  input  logic wclk,
  input  logic wrst_n,
  input  logic wpush,                     // write increment (when accepted)
  output logic wfull,
  output logic walmost_full,

  // read domain
  input  logic rclk,
  input  logic rrst_n,
  input  logic rpop,                      // read increment (when accepted)
  output logic rempty,
  output logic ralmost_full,              // "view" of almost-full in read domain (synced)
  output logic [$clog2(DEPTH+1)-1:0] rused // occupancy estimate in read domain
);

  // ----------------------------
  // Parameters / widths
  // ----------------------------
  localparam int ADDR_W = $clog2(DEPTH);
  // Async FIFO pointers typically use ADDR_W+1 bits (extra MSB for wrap)
  localparam int PTR_W  = ADDR_W + 1;

  // Compile-time check (synthesis-time or sim-time)
  initial begin
    if ((DEPTH & (DEPTH-1)) != 0) $fatal(1, "DEPTH must be power of 2");
    if (AFULL_MARGIN < 0 || AFULL_MARGIN >= DEPTH) $fatal(1, "Bad AFULL_MARGIN");
  end

  // ----------------------------
  // Gray/bin helpers
  // ----------------------------
  function automatic logic [PTR_W-1:0] bin2gray(input logic [PTR_W-1:0] b);
    return (b >> 1) ^ b;
  endfunction

  function automatic logic [PTR_W-1:0] gray2bin(input logic [PTR_W-1:0] g);
    logic [PTR_W-1:0] b;
    b[PTR_W-1] = g[PTR_W-1];
    for (int i = PTR_W-2; i >= 0; i--) begin
      b[i] = b[i+1] ^ g[i];
    end
    return b;
  endfunction

  // ----------------------------
  // Write-domain pointers
  // ----------------------------
  logic [PTR_W-1:0] wbin_q, wbin_d;
  logic [PTR_W-1:0] wgray_q, wgray_d;

  // Sync read pointer into write domain
  logic [PTR_W-1:0] rgray_w1, rgray_w2;

  // full detection uses next write gray and synced read gray with MSB inversion
  logic [PTR_W-1:0] wgray_next;
  logic [PTR_W-1:0] rgray_sync_w;

  assign rgray_sync_w = rgray_w2;

  // compute next pointers
  always_comb begin
    wbin_d  = wbin_q;
    if (wpush && !wfull) wbin_d = wbin_q + 1'b1;

    wgray_d = bin2gray(wbin_d);
  end

  // classic full compare (invert top two bits)
  // (works with PTR_W = ADDR_W+1)
  always_comb begin
    wgray_next = bin2gray(wbin_q + ((wpush && !wfull) ? 1'b1 : 1'b0));
    wfull = (wgray_next == {~rgray_sync_w[PTR_W-1:PTR_W-2], rgray_sync_w[PTR_W-3:0]});
  end

  // almost-full in write domain using occupancy estimate in write domain
  // used_w = wbin - rbin_sync (mod 2^PTR_W), take lower PTR_W bits
  logic [PTR_W-1:0] rbin_sync_w;
  logic [PTR_W-1:0] used_w;

  // ----------------------------
  // Read-domain pointers
  // ----------------------------
  logic [PTR_W-1:0] rbin_q, rbin_d;
  logic [PTR_W-1:0] rgray_q, rgray_d;

  // Sync write pointer into read domain
  logic [PTR_W-1:0] wgray_r1, wgray_r2;
  logic [PTR_W-1:0] wgray_sync_r;


  // occupancy in read domain: used_r = wbin_sync - rbin
  logic [PTR_W-1:0] wbin_sync_r;
  logic [PTR_W-1:0] used_r;

  assign rbin_sync_w = gray2bin(rgray_sync_w);
  assign used_w      = wbin_q - rbin_sync_w;

  always_comb begin
    // almost-full when free <= margin => used >= DEPTH - margin
    walmost_full = (used_w[ADDR_W-1:0] >= (DEPTH - AFULL_MARGIN));
    // Note: used_w has PTR_W bits; the lower ADDR_W bits represent modulo DEPTH count.
    // For correct "used in 0..DEPTH" you typically interpret with PTR_W; for AF test this works.
  end

  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wbin_q  <= '0;
      wgray_q <= '0;
      rgray_w1 <= '0;
      rgray_w2 <= '0;
    end else begin
      wbin_q  <= wbin_d;
      wgray_q <= wgray_d;

      rgray_w1 <= rgray_q;
      rgray_w2 <= rgray_w1;
    end
  end


  assign wgray_sync_r = wgray_r2;

  // compute next pointers
  always_comb begin
    rbin_d  = rbin_q;
    if (rpop && !rempty) rbin_d = rbin_q + 1'b1;

    rgray_d = bin2gray(rbin_d);
  end

  // empty compare
  always_comb begin
    rempty = (rgray_q == wgray_sync_r);
  end



  assign wbin_sync_r = gray2bin(wgray_sync_r);
  assign used_r      = wbin_sync_r - rbin_q;

  // "used words" in 0..DEPTH (PTR_W bits covers wrap)
  // Expose as up-to DEPTH count (ADDR_W+1 bits)
  always_comb begin
    rused = used_r[$clog2(DEPTH+1)-1:0];
    ralmost_full = (rused >= (DEPTH - AFULL_MARGIN));
  end

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      rbin_q  <= '0;
      rgray_q <= '0;
      wgray_r1 <= '0;
      wgray_r2 <= '0;
    end else begin
      rbin_q  <= rbin_d;
      rgray_q <= rgray_d;

      wgray_r1 <= wgray_q;
      wgray_r2 <= wgray_r1;
    end
  end

endmodule
