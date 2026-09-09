
`timescale 1ns/1ps

module tb_packet_builder;

parameter N_CH = 4;

logic CLK75M;
logic rst_n;

logic data_valid;
logic [15:0] FIFO_DAT;
logic [$clog2(N_CH)-1:0] SEL_ID;
logic [N_CH-1:0] EMPTY;

logic do_pop_slot;

logic FRAME_FIFO_AFULL;

logic [15:0] DATA_2_FIFO;
logic FRAME_FIFO_PUSH;

////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////
/*
Packet_builder #(.N_CH(N_CH)) dut (
    .CLK75M(CLK75M),
    .rst_n(rst_n),
    .data_valid(data_valid),
    .FIFO_DAT(FIFO_DAT),
    .SEL_ID(SEL_ID),
    .EMPTY(EMPTY),
    .do_pop_slot(do_pop_slot),
    .FRAME_FIFO_AFULL(FRAME_FIFO_AFULL),
    .DATA_2_FIFO(DATA_2_FIFO),
    .FRAME_FIFO_PUSH(FRAME_FIFO_PUSH)
);
*/

Packet_builder dut (
    .CLK75M(CLK75M),
    .rst_n(rst_n),
    .data_valid(data_valid),
    .FIFO_DAT(FIFO_DAT),
    .SEL_ID(SEL_ID),
    .EMPTY(EMPTY),
    .do_pop_slot(do_pop_slot),
    .FRAME_FIFO_AFULL(FRAME_FIFO_AFULL),
    .DATA_2_FIFO(DATA_2_FIFO),
    .FRAME_FIFO_PUSH(FRAME_FIFO_PUSH)
);
////////////////////////////////////////////////////////////
// Clock generation
////////////////////////////////////////////////////////////

initial CLK75M = 0;
always #6.666 CLK75M = ~CLK75M;   // 75 MHz

////////////////////////////////////////////////////////////
// Reset
////////////////////////////////////////////////////////////

initial begin
    rst_n = 0;
    data_valid = 0;
    FIFO_DAT = 0;
    SEL_ID = 0;
    EMPTY = '1;
    FRAME_FIFO_AFULL = 0;

    repeat(10) @(posedge CLK75M);
    rst_n = 1;
end

////////////////////////////////////////////////////////////
// Arbiter response model
////////////////////////////////////////////////////////////

logic pending_valid;
logic [15:0] next_data;
logic [$clog2(N_CH)-1:0] next_id;

////////////////////////////////////////////////////////////
// Arbiter response model (1-cycle latency)
////////////////////////////////////////////////////////////

logic pop_d;

always @(posedge CLK75M) begin

    data_valid <= #1 do_pop_slot;


    if (do_pop_slot) begin
        FIFO_DAT <= #1 next_data;
        SEL_ID   <= #1 next_id;
    end

end

////////////////////////////////////////////////////////////
// Payload generator
////////////////////////////////////////////////////////////

int payload_counter;

task send_word(input [15:0] data, input int cid);
begin
    next_data = data;
    next_id   = cid;
end
endtask

////////////////////////////////////////////////////////////
// FIFO state control
////////////////////////////////////////////////////////////

task set_fifo_nonempty();
begin
    EMPTY = '0;
end
endtask

task set_fifo_empty();
begin
    EMPTY = '1;
end
endtask

////////////////////////////////////////////////////////////
// Stream scenarios
////////////////////////////////////////////////////////////

task stream_same_channel(int nwords, int cid);
begin
    for (int i=0;i<nwords;i++) begin
        send_word(payload_counter, cid);
        payload_counter++;
        wait(do_pop_slot);
        @(posedge CLK75M);
        @(negedge CLK75M);
    end
end
endtask


task stream_channel_switch();
begin
    send_word(16'h1111,0); wait(do_pop_slot); @(posedge CLK75M); @(negedge CLK75M);
    send_word(16'h2222,1); wait(do_pop_slot); @(posedge CLK75M);         @(negedge CLK75M);
    send_word(16'h3333,2); wait(do_pop_slot); @(posedge CLK75M);        @(negedge CLK75M);
end
endtask


task stream_channel_wrap();
begin
    send_word(16'hAAAA,3); wait(do_pop_slot); @(posedge CLK75M); @(negedge CLK75M);
    send_word(16'hBBBB,0); wait(do_pop_slot); @(posedge CLK75M); @(negedge CLK75M);
end
endtask


task stream_reserved_words();
begin
    send_word(16'hC0DE,1); wait(do_pop_slot); @(posedge CLK75M); @(negedge CLK75M);
    send_word(16'hBEEF,1); wait(do_pop_slot); @(posedge CLK75M); @(negedge CLK75M);
    send_word(16'hDEAD,1); wait(do_pop_slot); @(posedge CLK75M); @(negedge CLK75M);
end
endtask


task backpressure_test();
begin
    @(posedge CLK75M);
    #1
    FRAME_FIFO_AFULL = 1;
    repeat(6) @(posedge CLK75M);
    #1
    FRAME_FIFO_AFULL = 0;
end
endtask

////////////////////////////////////////////////////////////
// Output monitor
////////////////////////////////////////////////////////////

always @(posedge CLK75M) begin
    if (FRAME_FIFO_PUSH) begin
        $display("%0t OUTPUT: %h", $time, DATA_2_FIFO);
    end
end

////////////////////////////////////////////////////////////
// Test sequence
////////////////////////////////////////////////////////////

initial begin

    wait(rst_n);

    set_fifo_nonempty();

    $display("---- Same channel stream ----");
    stream_same_channel(8,0);

    $display("---- Channel switch test ----");
    stream_channel_switch();

    $display("---- Reserved payload test ----");
    stream_reserved_words();

    $display("---- Channel wrap test ----");
    stream_channel_wrap();

    $display("---- Backpressure test ----");
    fork
        stream_same_channel(10,2);
        backpressure_test();
    join

    $display("---- FIFO empty termination ----");
    stream_same_channel(3,1);
    set_fifo_empty();

    repeat(20) @(posedge CLK75M);

    set_fifo_nonempty();
    $display("---- Random stress test ----");

    repeat(50) begin
        send_word($random, ($random % N_CH + N_CH) % N_CH);
        wait(do_pop_slot);
        @(posedge CLK75M);
    end

    repeat(20) @(posedge CLK75M);

    $display("TEST COMPLETE");
    $finish;

end

endmodule

