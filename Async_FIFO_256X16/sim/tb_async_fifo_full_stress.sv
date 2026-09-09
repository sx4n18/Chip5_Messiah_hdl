`timescale 1ns/1ps

module tb_async_fifo_full_stress;

    // ---------------------------------------
    // Clock generation
    // ---------------------------------------
    reg CLK40M = 0;
    reg CLK75M = 0;

    always #12.5  CLK40M = ~CLK40M;  // 40 MHz
    always #6.667 CLK75M = ~CLK75M;  // 75 MHz

`ifdef REAL_IP	
	localparam CKQ_DELAY = 1;
`else
	localparam CKQ_DELAY = 1;
`endif

    // ---------------------------------------
    // DUT signals
    // ---------------------------------------
    reg WRSTN;
    reg RRSTN;

    reg  [15:0] DATAIN;
    reg         PUSH;
    reg         POP;

    wire        FULL_40M;
    wire        EMPTY_75M;
    wire        ALMOST_FULL_75M;
    wire [15:0] DATAOUT;

    // ---------------------------------------
    // Instantiate DUT
    // ---------------------------------------
    Async_FIFO_256X16 dut (
        .CLK40M(CLK40M),
        .DATAIN(DATAIN),
        .PUSH(PUSH),
        .WRSTN(WRSTN),
        .FULL_40M(FULL_40M),

        .CLK75M(CLK75M),
        .POP(POP),
        .RRSTN(RRSTN),
        .ALMOST_FULL_75M(ALMOST_FULL_75M),
        .EMPTY_75M(EMPTY_75M),
        .DATAOUT(DATAOUT)
    );

    // ---------------------------------------
    // Reset sequence
    // ---------------------------------------
    initial begin
        WRSTN = 0;
        RRSTN = 0;
        PUSH  = 0;
        POP   = 0;
        DATAIN = 0;

        repeat (5) @(posedge CLK40M);
	#(CKQ_DELAY)
        WRSTN = 1;
	#(CKQ_DELAY)
        RRSTN = 1;
    end

    // ---------------------------------------
    // WRITE: Continuous push until FULL
    // ---------------------------------------
    always @(posedge CLK40M) begin
        if (!WRSTN) begin
            PUSH <= 0;
            DATAIN <= 0;
        end else begin
            if (!FULL_40M) begin
                PUSH   <= #(CKQ_DELAY) 1;
                DATAIN <= #(CKQ_DELAY) DATAIN + 1;
            end else begin
                PUSH <= #(CKQ_DELAY) 0;
            end
        end
    end

    // ---------------------------------------
    // READ: Held OFF to force FULL
    // ---------------------------------------
    always @(posedge CLK75M) begin
        if (!RRSTN)
            POP <= 0;
        else
            POP <= #(CKQ_DELAY) 0;  // intentionally disabled
    end

    // ---------------------------------------
    // FULL Monitor
    // ---------------------------------------
    always @(posedge CLK40M) begin
        if (FULL_40M)
            $display("Time %0t: FULL asserted", $time);
    end

    // ---------------------------------------
    // Heartbeat monitor
    // ---------------------------------------
    always #20000
        $display("Heartbeat @ %0t  FULL=%b  EMPTY=%b",
                  $time, FULL_40M, EMPTY_75M);

    // ---------------------------------------
    // End condition
    // ---------------------------------------
    initial begin
        #500000;   // run long after full
        $display("FULL stress test completed.");
        $finish;
    end

endmodule
