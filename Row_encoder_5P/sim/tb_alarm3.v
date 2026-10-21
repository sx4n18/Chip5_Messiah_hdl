`timescale 1ns/1ps

//`define GATE_LEVEL

module tb_alarm3;

reg clk40m;

always #12.5 clk40m = ~clk40m;

reg         rstn;
reg         EN;
reg         one_bit;
reg         pix_valid;
reg [4:0]   pix_mask;
reg [14:0]  pix_gray;

wire        enc_ready;
wire [15:0] enc_data;


Row_encode_5P dut (
    .clk40m    (clk40m),
    .rstn      (rstn),
    .EN        (EN),
    .one_bit   (one_bit),
    .pix_valid (pix_valid),
    .pix_mask  (pix_mask),
    .pix_gray  (pix_gray),
    .enc_ready (enc_ready),
    .enc_data  (enc_data)
);


`ifdef GATE_LEVEL

task tb_drive_edge;
begin
    @(posedge clk40m);
    #1;
end
endtask

`else

task tb_drive_edge;
begin
    @(negedge clk40m);
end
endtask

`endif


task send_pixel;
input [14:0] d;
begin

    tb_drive_edge();

    pix_gray  = d;
    pix_valid = 1'b1;

    tb_drive_edge();

    pix_valid = 1'b0;

end
endtask


task reset_dut;
begin

    rstn      = 1'b0;
    EN        = 1'b0;
    one_bit   = 1'b0;
    pix_valid = 1'b0;
    pix_mask  = 5'b11111;
    pix_gray  = 15'b0;

    repeat (5)
        @(posedge clk40m);

    rstn = 1'b1;

    repeat (2)
        @(posedge clk40m);

end
endtask


always @(posedge clk40m) begin

    if (enc_ready)

        $display(
            "[%0t] ALARM3 OUTPUT = %04h",
            $time,
            enc_data
        );

end


initial begin

    clk40m = 1'b0;

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b0;

    // Establish A.
    send_pixel(15'h1111);

    // Enter WAIT3.
    send_pixel(15'h1111);

    // Give DUT time to settle.
    repeat (2)
        @(posedge clk40m);

    //-----------------------------------------------------
    // Put silence counter at maximum.
    //-----------------------------------------------------

    $display("[%0t] Starting long alarm-count test", $time);

    repeat (32767)
    send_pixel(15'h1111);

    //-----------------------------------------------------
    // Same pattern.
    //
    // This should reach 7FFF and subsequently produce
    // the alarm according to your FSM timing.
    //-----------------------------------------------------

    send_pixel(15'h1111);

    repeat (5)
        @(posedge clk40m);

    // Next evaluation remains the same.
    send_pixel(15'h1111);

    repeat (8)
        @(posedge clk40m);

    $finish;

end

endmodule