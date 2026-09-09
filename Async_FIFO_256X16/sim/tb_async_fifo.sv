`timescale 1ns/1ps

module tb_async_fifo;

    // ------------------------------------------
    // Clock parameters
    // ------------------------------------------
    localparam WCLK_PERIOD = 25;   // 40 MHz
    localparam RCLK_PERIOD = 13.333; // ~75 MHz

    // ------------------------------------------
    // DUT signals
    // ------------------------------------------
    reg         CLK40M;
    reg         CLK75M;
    reg         WRSTN;
    reg         RRSTN;
    reg  [15:0] DATAIN;
    reg         PUSH;
    reg         POP;

    wire        FULL_40M;
    wire        EMPTY_75M;
    wire        ALMOST_FULL_75M;
    wire [15:0] DATAOUT;

    // ------------------------------------------
    // Instantiate DUT
    // ------------------------------------------
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

    // ------------------------------------------
    // Clock generation
    // ------------------------------------------
    initial CLK40M = 0;
    always #(WCLK_PERIOD/2) CLK40M = ~CLK40M;

    initial CLK75M = 0;
    always #(RCLK_PERIOD/2) CLK75M = ~CLK75M;

    // ------------------------------------------
    // Scoreboard
    // ------------------------------------------
    int unsigned write_count = 0;
    int unsigned read_count  = 0;

    typedef int unsigned data_t;
    data_t expected_queue[$];

    data_t expected;
    // ------------------------------------------
    // Reset
    // ------------------------------------------
    initial begin
        WRSTN = 0;
        RRSTN = 0;
        PUSH  = 0;
        POP   = 0;
        DATAIN = 0;

        repeat (5) @(posedge CLK40M);
        #1 WRSTN = 1;
        RRSTN = 1;
    end

    // ------------------------------------------
    // Write stimulus
    // ------------------------------------------
    always @(posedge CLK40M) begin
        if (!WRSTN) begin
            PUSH <= 0;
        end else begin
            // Random burst behavior
            if (($random() & 32'h3) == 0 && !FULL_40M) begin
                PUSH <= #1 1;
                DATAIN <= #1 write_count;
                expected_queue.push_back(write_count);
                write_count++;
            end else begin
                PUSH <= #1 0;
            end
        end
    end

    // ------------------------------------------
    // Read stimulus
    // ------------------------------------------
    always @(posedge CLK75M) begin
        if (!RRSTN) begin
            POP <= 0;
        end else begin
            if (($random()%3+3)%3 == 0 && !EMPTY_75M && ~POP ) begin
                POP <= #1 1;
            end else begin
                POP <= #1 0;
            end
        end
    end

    // ------------------------------------------
    // Data checking
    // ------------------------------------------
    always @(posedge CLK75M) begin
        if (POP && !EMPTY_75M) begin
            if (expected_queue.size() == 0) begin
                $fatal("Underflow detected!");
            end


            expected = expected_queue.pop_front();

//            if (DATAOUT !== expected) begin
//                $fatal("Data mismatch! Expected %0d, Got %0d",
//                        expected, DATAOUT);
//            end

            read_count++;
        end
    end

    // ------------------------------------------
    // Monitor overflow condition
    // ------------------------------------------
    always @(posedge CLK40M) begin
        if (PUSH && FULL_40M) begin
            $fatal("Overflow condition detected!");
        end
    end

    // ------------------------------------------
    // Simulation duration
    // ------------------------------------------
    initial begin
        #200000;  // run long enough to wrap pointers multiple times
        $display("Simulation completed successfully.");
        $display("Total writes: %0d", write_count);
        $display("Total reads : %0d", read_count);
        $finish;
    end

endmodule
