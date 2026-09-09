`timescale 1ns/1ps

module tb_CARR_ARB_MUX;

    // Clock / reset
    logic CLK75M;
    logic rst_n;

    // DUT inputs
    logic [3:0] EMPTY_75M;
    logic [3:0] ALMOST_FULL_75M;
    logic [63:0] DATA_FROM_ASYNC_FIFO;
    logic DO_POP_SLOT;

    // DUT outputs
    logic [3:0] POP_PX_FIFO;
    logic DAT_VALID_OF_THIS_POP;
    logic [1:0] SEL_FIFO_IDQ;
    logic [15:0] MUX_OUT;

    // Internal FIFO memory models (simple queues)
    logic [15:0] fifo_mem [3:0][0:15];
    int wr_ptr [3:0];
    int rd_ptr [3:0];
    int fifo_count [3:0];

    // -----------------------------
    // DUT instantiation
    // -----------------------------
    CARR_ARB_MUX dut (
        .CLK75M(CLK75M),
        .rst_n(rst_n),
        .EMPTY_75M(EMPTY_75M),
        .ALMOST_FULL_75M(ALMOST_FULL_75M),
        .POP_PX_FIFO(POP_PX_FIFO),
        .DATA_FROM_ASYNC_FIFO(DATA_FROM_ASYNC_FIFO),
        .DO_POP_SLOT(DO_POP_SLOT),
        .DAT_VALID_OF_THIS_POP(DAT_VALID_OF_THIS_POP),
        .SEL_FIFO_IDQ(SEL_FIFO_IDQ),
        .MUX_OUT(MUX_OUT)
    );

    // -----------------------------
    // Clock generation (75 MHz)
    // -----------------------------
    initial CLK75M = 0;
    always #6.666 CLK75M = ~CLK75M; // ~13.33 ns period

    // -----------------------------
    // Reset
    // -----------------------------
    initial begin
        rst_n = 0;
        #50;
        rst_n = 1;
    end

    // -----------------------------
    // FIFO model behavior
    // -----------------------------
    // Update EMPTY flags
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            EMPTY_75M[i] = (fifo_count[i] == 0);
            ALMOST_FULL_75M[i] = (fifo_count[i] > 12);
        end
    end

    // POP behavior + DATA output with delay (1–2 ns)
logic [63:0] data_from_fifo_ideal;

always_comb begin
    data_from_fifo_ideal = 64'd0;

    for (int i = 0; i < 4; i++) begin
        if (POP_PX_FIFO[i] && fifo_count[i] > 0) begin
            data_from_fifo_ideal[i*16 +: 16] = fifo_mem[i][rd_ptr[i]];
        end
    end
end

assign #(0.5) DATA_FROM_ASYNC_FIFO = data_from_fifo_ideal;

    // Update FIFO read pointers
    always @(posedge CLK75M) begin
        if (rst_n) begin
            for (int i = 0; i < 4; i++) begin
                if (POP_PX_FIFO[i] && fifo_count[i] > 0) begin
                    rd_ptr[i]   <= (rd_ptr[i] + 1) % 16;
                    fifo_count[i] <= fifo_count[i] - 1;
                end
            end
        end
    end

    // -----------------------------
    // Stimulus
    // -----------------------------
    initial begin
        DO_POP_SLOT = 0;

        // Init FIFO state
        for (int i = 0; i < 4; i++) begin
            wr_ptr[i] = 0;
            rd_ptr[i] = 0;
            fifo_count[i] = 0;
        end

        wait(rst_n);

        // Fill FIFOs with different patterns
        repeat (8) begin
            push_fifo(0, $random);
            push_fifo(1, $random);
            push_fifo(2, $random);
            push_fifo(3, $random);
        end

        #20;

        // Start popping
        repeat (30) begin
            @(posedge CLK75M);
            #1 DO_POP_SLOT = 1;
            @(posedge CLK75M);
            #1 DO_POP_SLOT = 0;
        end

        DO_POP_SLOT = 0;

        #100;
        $finish;
    end

    // -----------------------------
    // FIFO push task
    // -----------------------------
    task push_fifo(input int id, input logic [15:0] data);
        if (fifo_count[id] < 16) begin
            fifo_mem[id][wr_ptr[id]] = data;
            wr_ptr[id] = (wr_ptr[id] + 1) % 16;
            fifo_count[id]++;
        end
    endtask

    // -----------------------------
    // Monitor
    // -----------------------------
    always @(posedge CLK75M) begin
        if (rst_n && DO_POP_SLOT) begin
            $display("[%0t] POP=%b SEL=%0d VALID=%b DATA=%h",
                $time,
                POP_PX_FIFO,
                SEL_FIFO_IDQ,
                DAT_VALID_OF_THIS_POP,
                MUX_OUT
            );
        end
    end

endmodule