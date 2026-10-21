`timescale 1ns/1ps

//=========================================================
// Select simulation mode
//
// RTL:
//     drive inputs on negedge
//
// GLS:
//     drive inputs 1 ns after posedge
//
//=========================================================
//`define GATE_LEVEL


module tb_push3;

reg clk40m;

always #12.5 clk40m = ~clk40m;


//---------------------------------------------------------
// DUT inputs
//---------------------------------------------------------

reg         rstn;
reg         EN;
reg         one_bit;
reg         pix_valid;
reg [4:0]   pix_mask;
reg [14:0]  pix_gray;


//---------------------------------------------------------
// DUT outputs
//---------------------------------------------------------

wire        enc_ready;
wire [15:0] enc_data;


//---------------------------------------------------------
// DUT
//---------------------------------------------------------

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


//=========================================================
// Timing helper
//=========================================================

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


//=========================================================
// Send one 3-bit evaluation
//=========================================================

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


//=========================================================
// Reset
//=========================================================

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


//=========================================================
// Output monitor
//=========================================================

always @(posedge clk40m) begin

    if (enc_ready) begin

        $display(
            "[%0t] PUSH3 OUTPUT = %04h",
            $time,
            enc_data
        );

    end

end


//=========================================================
// Test
//=========================================================

initial begin

    clk40m = 1'b0;

    reset_dut;

    EN      = 1'b1;
    one_bit = 1'b0;

    // Initial pattern.
    send_pixel(15'h0123);

    // Repeated pattern.
    send_pixel(15'h0123);
    send_pixel(15'h0123);

    // Break repetition.
    send_pixel(15'h4567);

    repeat (10)
        @(posedge clk40m);

    $finish;

end

endmodule