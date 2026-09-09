`timescale 1ns/1ps

module tb_packet_builder;

reg CLK75M;
reg rst_n;

reg data_valid;
reg [15:0] FIFO_DAT;
reg [1:0] SEL_ID;
reg [3:0] EMPTY;

wire do_pop_slot;

reg FRAME_FIFO_FULL;
wire [15:0] DATA_2_FIFO;
wire FRAME_FIFO_PUSH;

////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////

Packet_builder  dut(
    .CLK75M(CLK75M),
    .rst_n(rst_n),
    .data_valid(data_valid),
    .FIFO_DAT(FIFO_DAT),
    .SEL_ID(SEL_ID),
    .EMPTY(EMPTY),
    .do_pop_slot(do_pop_slot),
    .FRAME_FIFO_FULL(FRAME_FIFO_FULL),
    .DATA_2_FIFO(DATA_2_FIFO),
    .FRAME_FIFO_PUSH(FRAME_FIFO_PUSH)
);



////////////////////////////////////////////////////////////
// 75 MHz Clock
////////////////////////////////////////////////////////////

initial begin
    CLK75M = 0;
    forever #6.666 CLK75M = ~CLK75M; // 13.333ns period
end

////////////////////////////////////////////////////////////
// Reset
////////////////////////////////////////////////////////////

initial begin
    rst_n = 0;
    data_valid = 0;
    FIFO_DAT = 0;
    SEL_ID = 0;
    EMPTY = 4'b1111;
    FRAME_FIFO_FULL = 0;

    #100;
    rst_n = 1;
end

////////////////////////////////////////////////////////////
// Payload generator
// Emulates Encoder_FIFO_arb behavior
////////////////////////////////////////////////////////////

reg [15:0] payload_counter;

always @(posedge CLK75M) begin

    if (!rst_n) begin
        payload_counter <= 0;
        data_valid <= 0;
    end
    else begin

        // emulate arbiter response one cycle after pop
        if (do_pop_slot) begin
            data_valid <= 1;
            FIFO_DAT <= payload_counter;
            payload_counter <= payload_counter + 1;

            // rotate channel occasionally
            SEL_ID <= payload_counter[1:0];
        end
        else begin
            data_valid <= 0;
        end

    end

end

////////////////////////////////////////////////////////////
// FIFO emptiness model
////////////////////////////////////////////////////////////

initial begin

    wait(rst_n);

    // start with data available
    EMPTY = 4'b0000;

    #5000;

    #20;

    // simulate channel 2 empty
    EMPTY = 4'b1111;

    #2000;

    EMPTY = 4'b0000;

end

////////////////////////////////////////////////////////////
// Frame FIFO backpressure test
////////////////////////////////////////////////////////////

initial begin

    wait(rst_n);

    #4000;
    FRAME_FIFO_FULL = 1;

    #200;
    FRAME_FIFO_FULL = 0;

end

////////////////////////////////////////////////////////////
// Monitor
////////////////////////////////////////////////////////////

always @(posedge CLK75M) begin

    if (FRAME_FIFO_PUSH) begin
        $display("TIME=%0t PUSH DATA=0x%h",
            $time, DATA_2_FIFO);
    end

end

////////////////////////////////////////////////////////////
// Simulation stop
////////////////////////////////////////////////////////////

initial begin
    #20000;
    $finish;
end

endmodule