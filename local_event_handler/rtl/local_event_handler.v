`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////
//
//  This is the local event handler that shall takes over the handling
//  the following cases:
//   + overflow handling
//   + apply new mask
//   + apply new N_MAX for arbiter
//   + disabling the whole block
//   + swtiching between 1-bit/3-bit mode
//  
//   Local handling: 
//   - overflow, this is triggered automatically
//   overflow -> disable the block, record T0 -> wait until all AFIFOs empty -> re-enable the block, reset all fifos, record T1 -> Raise event -> drop fifo reset until ack
//   
//   - apply new mask, this should be an external command:
//   cmd arrives -> disable the block, record T0 -> wait until all AFIFOs empty -> apply the new mask, reset all fifos, re-enable, record T1 -> raise event -> drop fifo reset until ack
// 
//   Global handling: 
//   system handler should assign each local event handler the exact event
//   - switching between 1-3 bit mode:
//   global reconfig -> disable the block, record T0 -> wait until all AFIFOs empty -> apply the new mode, reset all fifos, re-enable, record T1 -> raise event
//
//   - apply new N_MAx for arbiter:
//   similar flow as above
//
//   - disable the whole module:
//   
//   New edit: 19 Sep 2026
//
//   Ver. 0.1
//   In this updated version, we added the following new features:
//	+ New state dedicated as a resting state for block disabling *DOWN*
//	+ Move the functionality of *RESET* to *DOWN*
//	+ *RESET* now acts as a real reset state when the block just had a proper reset and waiting to be brought up
//	+ Added new external command port: acq_start_cmd, a 40 Mhz one cycle pulse
//	+ Added new output registers to be exposed to SPI: ACQ_START_T, BLK_DISABLE_T, BLK_ENABLE_T
//
//  New edit: 21 Sep 2026
//
//  Ver. 0.1.1
//  In this small iteration, I added an extra signal in the event bus as in: *event_time_valid*. this signal is simply used
//  to make the event information to be accurately sampled with the correct information so that we will not have event
//  racing over the right timing T1.
//
//  New edit: 23 Sep 2026
// 
//  Ver. 0.1.2
//  Added new port *encs_all_empty*, which is the indicator for all compressors are in idle state. This is because when blocks
//  are getting disabled, they do not necessarily go to idle state right away, they may need to push out last few words.
//  
//  On top of it, I added register AFIFO_DRAIN_CNT to make sure FSM to wait at least 5 cycles before checking the clear signals
//  from both producers and consumers. In this case, *encs_all_idle* and *fifo_all_empty*

module local_event_handler (
	input clk40m,    			// Clock runs at the same freqeuncy as the front end
	input rst_n,  				// Asynchronous reset active low
	
	// local command
	input 			cmd_apply_mask, 	// the command that only applies this block to apply the mask
	input [39:0]   		mask_shadow,  		// the shadow mask that was just transmitted through SPI

	input           	cmd_blk_enable, 	// the commad to enable or disable the block

	// glbal configuration
	//////// Ver 0.1 new////////
	input			acq_start_cmd, 		// The acquisition start command to start the whole process
	//////// Ver 0.1 new////////

	input 			global_reconfig,    // the command to run global reconfiguration
	input 			global_enable, 		
	input 	[9:0]   	new_NMAX,     		// the new shadow n_max for arbiter
	input 			mode_1bit,           // 1-bit or 3-bit mode, by default it should be 0 --> 3-bit mode

	// overflow
	input 	[7:0]   	fifo_overflow,      // the overflow flag from all 8 fifos
	// consumer status
	input 			fifo_all_empty,     // all the fifos are empty
	// producer status
	input			encs_all_idle, 		// idle state indicator, all compressors empty

	input 	[44:0]  	mission_counter, 	// mission timer


	// block control 
	output 	reg		compressor_enable, 		
	// afifo reset
	output 	reg		afifo_reset_n, 

	// active mask
	output 	reg [39:0] 	pix_mask_active,
	output 	reg 		mode_1bit_active, 
	output 	reg [9:0]	NMAX_active,

	// status
	output 	reg		block_busy, 		// external flag to be read by SPI host
	output 			block_enabled, 		// block active indicator 
	//////// Ver 0.1 new////////
	output	reg [44:0]	ACQ_START_T, 		// The time of the beginning of acquisition
	output	reg [44:0]	BLK_DISABLE_T, 		// The time of the intentionally disabling
	output  reg [44:0] 	BLK_ENABLE_T, 		// The time of the intentionally enabling
	//////// Ver 0.1 new////////

	// event interface to packet builder
	output 	reg 		event_valid, 
	output  reg 		event_time_valid, 	// special valid signal to indicate the validity of event time1
	output	reg [3:0]	event_type, 
	output	reg [2:0]	event_fifo_id, 
	output	reg [44:0] 	event_time0, 
	output	reg [44:0]	event_time1, 

	input				event_ack


);

// system parameters
localparam			RESET  	= 0;	
localparam   			IDLE   	= 1;
localparam			CAPCHAT0= 2;
localparam 			DISABLE_BLK = 3;
localparam			WAIT_FIFO_EMPTY  = 4;
localparam 			RESET_AFIFO 	= 5;
localparam 			APPLY_CONFIG 	= 6;
localparam 			ENABLE_BLK 		= 7;
localparam 			CAPCHAT1 		= 8;
//localparam 			CREATE_EVENT 	= 9;
localparam 			WAIT_EVENT_ACK 	= 9;
localparam			DOWN 		= 10; 	// resting state for block intentionally disabling


// event type
localparam 			FIFO_OF = 4'h0;
localparam			LCAL_MSK_CHANGE = 4'h1;
localparam			GLB_1_BIT_MODE  = 4'h2;
localparam 			BLK_DISABLE_REQ = 4'h3;

// instantiated a fixed priority one hot encoder from one hot to 3-bit id

wire 		[2:0]	encoded_1hot_fifo_id;

onehot_encoder onehot_fixed_prio_encoder (
	.fifo_overflow(fifo_overflow),
	.fifo_id(encoded_1hot_fifo_id) );

// registers 

reg 	[3:0] 	curr_state, next_state;

reg 	[1:0] 	reconfig_type;

reg 			event_ack_sync_x, event_ack_synced;


reg 	[2:0] 		AFIFO_DRAIN_CNT;

wire 				fifo_overflow_event;


assign fifo_overflow_event = |fifo_overflow;

assign block_enabled = compressor_enable;


////////////////////////////////////////////////////////
//		effective enable
//////////////////////////////////////////////////////

wire eff_enable;

assign eff_enable = global_enable & cmd_blk_enable;


////////////////////////////////////////////////////////
//		synchronisation from PB
//////////////////////////////////////////////////////
always @(posedge clk40m or negedge rst_n) begin 
	if(~rst_n) begin
		 event_ack_sync_x <= 0;
		 event_ack_synced <= 0;
	end else begin
		event_ack_sync_x <= event_ack;
		event_ack_synced <=  event_ack_sync_x;
	end
end

////////////////////////////////////////////////////////////
// 			current state logic 
////////////////////////////////////////////////////////////

always @(posedge clk40m or negedge rst_n) begin 
	if(~rst_n) begin
		curr_state <= RESET;
	end else begin
		curr_state <= next_state;
	end
end



/////////////////////////////////////////////////////////////
//				current state logic sequential
/////////////////////////////////////////////////////////////

always @(posedge clk40m or negedge rst_n) begin
	if(~rst_n) begin
		// clean up all the registers 
		compressor_enable <= 0;
		// configurations
		pix_mask_active <= 0;
		mode_1bit_active <= 0;
		NMAX_active <= 10'd32;
		// event info
		event_valid  <= 0;
		event_type <= 4'hf;
		event_fifo_id <= 0;
		event_time0 <= 0;
		event_time1 <= 0;
		event_time_valid <= 0;
		// status
		block_busy <= 0;
		// timestamp flag
		ACQ_START_T <= 45'd0;
		BLK_DISABLE_T <= 45'd0;
		BLK_ENABLE_T <= 45'd0;
		// patch
		AFIFO_DRAIN_CNT <= 0;
	end else begin
		case (curr_state)
		
		RESET: begin 
			// WHEN WE ARE READY TO FUNCTION, WE GET ALL THE CONFIGS READY
			if (eff_enable && acq_start_cmd) begin
				compressor_enable <= 1;
				pix_mask_active <= mask_shadow;
				mode_1bit_active <= mode_1bit;
				NMAX_active		<= new_NMAX;
				ACQ_START_T		<= mission_counter;
			end
		end


		IDLE: begin 
			// there are 3 different entries for the IDLE to split
			// fifo overflow, it should handle this automatically without external command
			if (fifo_overflow) begin
				event_type <= FIFO_OF;
				event_fifo_id <=  encoded_1hot_fifo_id;
				// flag block to be busy
				block_busy <= 1;
			end
			else if (cmd_apply_mask) begin
				// local cmd mask
				event_type <= LCAL_MSK_CHANGE;
				block_busy <= 1;
			end
			else if (global_reconfig) begin 
				event_type <= GLB_1_BIT_MODE;
				block_busy <= 1;
			end
			else if (!eff_enable)
			begin 
				event_type <= BLK_DISABLE_REQ;
				block_busy <= 1;
			end
			
		end


		CAPCHAT0:
		begin
			// simply just sample current mission counter 
			event_time0 <= mission_counter;
		end 


		DISABLE_BLK:
		begin 
			// turn off the block 
			compressor_enable <= 0;

			// if this was intentional, we update the sticky flag
			if (event_type == BLK_DISABLE_REQ) begin
				BLK_DISABLE_T <= mission_counter;
			end

		end 


		WAIT_FIFO_EMPTY:
		begin 
			if (AFIFO_DRAIN_CNT < 3'd5) begin
				AFIFO_DRAIN_CNT <= AFIFO_DRAIN_CNT +1;
			end


		end 


		RESET_AFIFO: 
		begin 	AFIFO_DRAIN_CNT <= 0;
			if (event_type == BLK_DISABLE_REQ) begin
				block_busy <= 0;
			end
		end	
        

        APPLY_CONFIG: 	
        begin
        	if (event_type == LCAL_MSK_CHANGE) begin
        		pix_mask_active <= mask_shadow;
        	end
        	else if (event_type == GLB_1_BIT_MODE) begin
        		mode_1bit_active <= mode_1bit;
        		NMAX_active <= new_NMAX;
        	end
        end

        ENABLE_BLK:
        begin 
        	compressor_enable <= 1;
        	event_valid <= 1;
        end 		
        

        CAPCHAT1:
        begin 
        	event_time1 <= mission_counter;
        	event_time_valid <= 1;
        end 		
        
/*	remove redundent state 

        CREATE_EVENT:
        begin 
        end 	
*/    

        WAIT_EVENT_ACK: 	
		begin 
			if (event_ack_synced) begin
				event_valid <= 0;
				block_busy <= 0;
				event_time_valid <= 0;
			end
		end


	DOWN: 
	begin 
		// the resting state for the case when the block was intentionally turned off
		if (eff_enable) begin
			BLK_ENABLE_T <= mission_counter;
			compressor_enable <= 1;
		end
	end


		default : /* default */;
		endcase
	end
end



/////////////////////////////////////////////////////////////
//				next state logic 
/////////////////////////////////////////////////////////////


always @(*)
begin 

// by default the outputs and next state should be:
next_state = curr_state; 
afifo_reset_n = 1;

case (curr_state)

		RESET: begin 
			// WHEN WE ARE READY TO FUNCTION, WE GET ALL THE CONFIGS READY
			if (eff_enable && acq_start_cmd) begin
				next_state = IDLE;
			end
		end


		IDLE: begin 
			// normal functional states for the block
			// if any of fifo overflow or local config or global config happens, an event is raised
			if (fifo_overflow || cmd_apply_mask || global_reconfig) begin
				next_state = CAPCHAT0;
			end
			else if (!eff_enable) begin 
				next_state = DISABLE_BLK;
			end
		end


		CAPCHAT0:
		begin 
			next_state = DISABLE_BLK;
		 end 


		DISABLE_BLK: 
		begin 
			next_state = WAIT_FIFO_EMPTY;
		end


		WAIT_FIFO_EMPTY: 
		begin 
			if (AFIFO_DRAIN_CNT >= 3'd5 && fifo_all_empty && encs_all_idle) begin
				next_state = RESET_AFIFO;
			end
			
		end


		RESET_AFIFO:
		begin 
			afifo_reset_n = 0;

			if (event_type == FIFO_OF) begin
				next_state = ENABLE_BLK;
			end
			else if (event_type == LCAL_MSK_CHANGE || event_type == GLB_1_BIT_MODE) begin
				next_state = APPLY_CONFIG;
			end
			else if(event_type == BLK_DISABLE_REQ) begin 
				next_state = DOWN;
			end
		end 	
        

        APPLY_CONFIG:
        begin 
        	next_state = ENABLE_BLK; 
        end 	
        

        ENABLE_BLK:
        begin 
        	next_state = CAPCHAT1; 
        end 		
        

        CAPCHAT1: 		
        begin 
        	next_state = WAIT_EVENT_ACK;
        end

/*   removed redundant state
        CREATE_EVENT:
        begin 
        	next_state = WAIT_EVENT_ACK;
        end 	
*/         

        WAIT_EVENT_ACK:
        begin 
        	if (event_ack_synced) begin
        		next_state = IDLE;
        	end
        end 
	


        DOWN: 
        begin 
        	if (eff_enable) begin
        		next_state = IDLE;
        	end
        end


	default : /* default */;
endcase





end







endmodule


module  onehot_encoder(
	input 		[7:0] 	fifo_overflow,
	
	output	reg	[2:0]	fifo_id
);

// fixed priority one hot translator, will always prioritise lower bit

always @(fifo_overflow) begin

casez (fifo_overflow)
 	
	8'b1000_0000: fifo_id = 3'b111; 
	8'b?100_0000: fifo_id = 3'b110;
	8'b??10_0000: fifo_id = 3'b101;
	8'b???1_0000: fifo_id = 3'b100;
	8'b????_1000: fifo_id = 3'b011;
	8'b????_?100: fifo_id = 3'b010;
	8'b????_??10: fifo_id = 3'b001;
	8'b????_???1: fifo_id = 3'b000;
	

 	default : fifo_id = 3'b000;
 endcase 

end



endmodule