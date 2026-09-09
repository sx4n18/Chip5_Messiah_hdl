// This is the complete carr arbiter module that include the extra mux logic
// and return the data valid after the do pop slot request

module CARR_ARB_MUX (
	input 			CLK75M, // 	Arbiter works at 75 MHz
	input 			rst_n,  //  asynchronous reset

	// interface with local event handler
	input 	[9:0]	MAX_READS,      // Configurable max numbers of reads from fifos

	// interface with the fifo groups

	input	[7:0]	EMPTY_75M, 		// The empty status flag from async FIFO that stores pixel values 
	input	[7:0]	ALMOST_FULL_75M,// The almost full flag that comes from the async fifo  
	output	[7:0]	POP_PX_FIFO, 	// individual pop signal to the async fifo
	input	[127:0]	DATA_FROM_ASYNC_FIFO, // The wire connection of that async fifo data output, each carries 16-bit, 8 fifos should have 128 bit

	// interface with the packet builder
	
	input			DO_POP_SLOT, //   interface with the packet builder, the command to pop a slot
	output			DAT_VALID_OF_THIS_POP,	// telling packet builder that current pop is valid
	output	[2:0]	SEL_FIFO_IDQ, // selected async fifo id
	output 	[15:0]	MUX_OUT



);






	logic do_pop_slot_reg;
	logic [15:0] mux_out;
	logic [127:0] FIFO_DATA_OUT;





CARR_arb #(.N_CH(8)) i_CARR_arb (
	.clk        (CLK75M        ),
	.rst_n      (rst_n      ),
	.MAX_READS  (MAX_READS      ),
	.do_pop_slot(DO_POP_SLOT),
	.empty      (EMPTY_75M      ),
	.almost_full(ALMOST_FULL_75M),
	.pop        (POP_PX_FIFO        ),
	.sel_idx_q  (SEL_FIFO_IDQ  )
);



// extra logic that register the data coming out of fifo and give
// data valid signal
// And mux out the 64 bit input to the out
// Or in our case, the data path.


wire [127:0] FIFO_DATA_WIRE;

assign FIFO_DATA_WIRE = DATA_FROM_ASYNC_FIFO;

always_ff @(posedge CLK75M)
begin 
	FIFO_DATA_OUT <=  FIFO_DATA_WIRE;
end

always_ff @(posedge CLK75M)
begin 
	do_pop_slot_reg <= DO_POP_SLOT;
end


always_comb
begin
	case (SEL_FIFO_IDQ)
	 	3'b000: mux_out = FIFO_DATA_OUT[15:0]; 

	 	3'b001: mux_out = FIFO_DATA_OUT[31:16];

	 	3'b010: mux_out = FIFO_DATA_OUT[47:32];

	 	3'b011: mux_out = FIFO_DATA_OUT[63:48];

	 	3'b100: mux_out = FIFO_DATA_OUT[79:64];

	 	3'b101: mux_out = FIFO_DATA_OUT[95:80];

	 	3'b110: mux_out = FIFO_DATA_OUT[111:96];

	 	3'b111: mux_out = FIFO_DATA_OUT[127:112];
	 	
	 	default : mux_out = FIFO_DATA_OUT[15:0];
	 endcase 

end





// Instantiate the packet builder
/*

// This is what the packet builder expect


	logic FRAME_FIFO_FULL;
	logic [15:0] DATA_2_FIFO;
	logic FRAME_FIFO_PUSH;

Packet_builder i_Packet_builder (
	.CLK75M         (CLK75M         ),
	.rst_n          (rst_n          ),
	.data_valid     (do_pop_slot_reg     ),
	.FIFO_DAT       (mux_out       ),
	.SEL_ID         (SEL_ID         ), // TODO: Check connection ! Signal/port not matching : Expecting logic [$clog2(4)-1:0]  -- Found logic [1:0] 
	.EMPTY          (EMPTY          ),
	.do_pop_slot    (do_pop_slot    ),
	.FRAME_FIFO_FULL(FRAME_FIFO_FULL),
	.DATA_2_FIFO    (DATA_2_FIFO    ),
	.FRAME_FIFO_PUSH(FRAME_FIFO_PUSH)
);

*/

assign MUX_OUT = mux_out;
assign DAT_VALID_OF_THIS_POP = do_pop_slot_reg;


endmodule



