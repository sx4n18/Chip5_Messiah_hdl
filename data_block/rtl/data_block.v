///////////////////////////////////////////////////////////////////////////////
// This is the data block module that should encapsulate the following modules:
//  - local event handler
//  - mission_counter
//  - 8 row_based_encoder_5P
//  - 8 Async FIFO
//  - CARR arbiter
//  - packet_builder
//	


module data_block (

	input 					clk40m, 	// 40 Mhz clock
	input					rst_n, 		// global reset signal

	input					clk75m, 
	// interface to local event handler

	// local config
	input 					cmd_apply_mask, 
	input		[39:0]		mask_shadow, 
	input 					cmd_blk_enable,
	// global config
	input 					global_reconfig,
	input					global_enable, 
	input		[9:0]		new_NMAX, 
	input 					mode_1bit, 

	// output to the system
	output					block_busy, 
	output 					block_enabled, 

	// interface to the pixels
	input					pix_valid, 
	input		[119:0]		pix_value, 

	// interface of the packet builder
	input 					FRAME_FIFO_AFULL, 

	output 		[15:0]		DATA_2_FIFO,
	output 					FRAME_FIFO_PUSH
	
);

// instantiate a mission counter


	wire [44:0] mission_cnt;
	mission_counter i_mission_counter 
	(	
	.clk40m(clk40m), 
	.rst_n(rst_n), 
	.mission_cnt(mission_cnt)
	);



// instantiate the local event handler

	wire [7:0] fifo_overflow;
	wire fifo_all_empty;

	wire compressor_enable;
	wire afifo_reset_n;
	wire [39:0] pix_mask_active;
	wire mode_1bit_active;
	wire [9:0] NMAX_active;

	wire event_valid;
	wire [3:0] event_type;
	wire [2:0] event_fifo_id;
	wire [44:0] event_time0;
	wire [44:0] event_time1;
	wire event_ack;

local_event_handler i_local_event_handler (
	.clk40m           (clk40m           ),
	.rst_n            (rst_n            ),
	// input from external
	.cmd_apply_mask   (cmd_apply_mask   ),
	.mask_shadow      (mask_shadow      ),
	.cmd_blk_enable   (cmd_blk_enable   ),
	.global_reconfig  (global_reconfig  ),
	.global_enable    (global_enable    ),
	.new_NMAX         (new_NMAX         ),
	.mode_1bit        (mode_1bit        ),
	// connection with fifos
	.fifo_overflow    (fifo_overflow    ),
	.fifo_all_empty   (fifo_all_empty   ),
	.afifo_reset_n    (afifo_reset_n    ),
	// components control
	.mission_counter  (mission_cnt  ),
	.compressor_enable(compressor_enable),
	// active configs
	.pix_mask_active  (pix_mask_active  ),
	.mode_1bit_active (mode_1bit_active ),
	.NMAX_active      (NMAX_active      ),
	// block indicator
	.block_busy       (block_busy       ),
	.block_enabled    (block_enabled    ),
	// event bus
	.event_valid      (event_valid      ),
	.event_type       (event_type       ),
	.event_fifo_id    (event_fifo_id    ),
	.event_time0      (event_time0      ),
	.event_time1      (event_time1      ),
	.event_ack        (event_ack        )
);


// instantiate the compressors and async fifo

wire	[7:0]		AFIFO_PUSH;
wire	[127:0]		enc_2_afifo_DAT;



wire WRSTN; 				// needs to be modified 
wire RRSTN;


// for simulation simplicity only, we have the following

// TODO: THEY NEED TO BE SYNC-ED INTO THE CLOCK DOMAIN

assign WRSTN = rst_n & afifo_reset_n;
assign RRSTN = rst_n & afifo_reset_n;  


// wires 

// wires between AFIFO, ARB and PB
	
	// AFIFO <-> ARB
	wire [7:0] EMPTY_75M;	// THIS ALSO GOES TO PB TO MAKE PB STOP REQ					
	wire [7:0] ALMOST_FULL_75M;
	wire [7:0] POP_PX_FIFO;
	wire [127:0] DATA_FROM_ASYNC_FIFO;
	// ARB <-> PB
	wire DO_POP_SLOT;			// REQ
	wire DAT_VALID_OF_THIS_POP; // ACK FROM ARB
	wire [2:0] SEL_FIFO_IDQ;
	wire [15:0] MUX_OUT;


assign fifo_all_empty = & EMPTY_75M;

genvar i;

generate 
	for ( i = 0; i < 8; i++) begin : encoder_fifo_blk
	
	Row_encode_5P i_row_encoder_5p (
	
 		.clk40m(clk40m),				// max 40MHz clock
		.rstn(rst_n), 				// active low reset
 		.EN(compressor_enable), 				// active high enable
 		.one_bit(mode_1bit_active), 			// one bit mode on or off, change of this mode can only happen at IDLE state
 		.pix_valid(pix_valid), 			// pixel valid signal from ADC
		//input 		[2:0]	rescombo, 			// resistor combo from ADC?  we actually do not need this for the implementation
 		.pix_mask(pix_mask_active[5*i +: 5]), 			// 5-bit pixel mask to block out the pixel
 		.pix_gray(pix_value[15*i +: 15]),				// 15-bit pixel values, in gray code

	 	.enc_ready(AFIFO_PUSH[i]), 			// 1-bit pulse for encoding ready
	 	.enc_data(enc_2_afifo_DAT[16*i +: 16])        	// encoded 16-bit data 	
	
);

	Async_FIFO_256X16 i_Async_FIFO_256X16 (
	.CLK40M         (clk40m               ),
	.DATAIN         (enc_2_afifo_DAT[16*i +: 16]               ),
	.PUSH           (AFIFO_PUSH[i]      ),
	.WRSTN          (WRSTN                ),
	.FULL_40M       (fifo_overflow[i]             ),
	.CLK75M         (clk75m               ),
	.POP            (POP_PX_FIFO[i]),
	.RRSTN          (RRSTN                ),
	.ALMOST_FULL_75M(ALMOST_FULL_75M[i]      ), // TODO: Check connection ! Signal/port not matching : Expecting logic  -- Found logic [7:0] 
	.EMPTY_75M      (EMPTY_75M[i]            ), // TODO: Check connection ! Signal/port not matching : Expecting logic  -- Found logic [7:0] 
	.DATAOUT        (DATA_FROM_ASYNC_FIFO[16*i +: 16]  )
);
	end
endgenerate



// instantiate the arbiter




CARR_ARB_MUX i_CARR_ARB_MUX (
	.CLK75M               (clk75m               ),
	.rst_n                (rst_n                ),
	.MAX_READS            (NMAX_active          ),
	.EMPTY_75M            (EMPTY_75M            ),
	.ALMOST_FULL_75M      (ALMOST_FULL_75M      ),
	.POP_PX_FIFO          (POP_PX_FIFO          ),
	.DATA_FROM_ASYNC_FIFO (DATA_FROM_ASYNC_FIFO ),
	.DO_POP_SLOT          (DO_POP_SLOT          ),
	.DAT_VALID_OF_THIS_POP(DAT_VALID_OF_THIS_POP),
	.SEL_FIFO_IDQ         (SEL_FIFO_IDQ         ),
	.MUX_OUT              (MUX_OUT              )
);


// instantiate the packet builder






packet_builder i_packet_builder (
	.CLK75M          (clk75m          ),
	.rst_n           (rst_n           ),
	.event_valid     (event_valid     ),
	.event_type      (event_type      ),
	.event_fifo_id   (event_fifo_id   ),
	.event_time0     (event_time0     ),
	.event_time1     (event_time1     ),
	.event_ack       (event_ack       ),
	.data_valid      (DAT_VALID_OF_THIS_POP      ),
	.FIFO_DAT        (MUX_OUT        ),
	.SEL_ID          (SEL_FIFO_IDQ          ),
	.EMPTY           (EMPTY_75M       ),
	.do_pop_slot     (DO_POP_SLOT     ),
	.FRAME_FIFO_AFULL(FRAME_FIFO_AFULL),
	.DATA_2_FIFO     (DATA_2_FIFO     ),
	.FRAME_FIFO_PUSH (FRAME_FIFO_PUSH )
);


endmodule
