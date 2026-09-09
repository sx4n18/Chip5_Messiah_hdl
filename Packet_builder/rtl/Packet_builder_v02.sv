// Ver. 0.1
// The packet builder I built from the table derived.
// TODO: Include the escape mechanism, correct response when FRAME FIFO is full, pixel fifo overflow contingency.
// 
// Ver. 0.2
// This version will add extra states to deal with escape mechanism.
// and
// Frame fifo almost full case. 

module Packet_builder #(parameter int N_CH = 4) (
	input 	CLK75M,    // Clock, 75 Mhz
	input 	rst_n,  // Asynchronous reset active low

	// interface input from arbiter

	input   		data_valid, // data coming back from arbiter
	input 	[15:0]	FIFO_DAT, 
	input 	[$clog2(N_CH)-1:0]	SEL_ID, // selected ID of the FIFO.
	input 	[N_CH-1:0]  EMPTY,  // empty signal from FIFO


	// interface back to arbiter

	output	logic do_pop_slot,		// the pop slot pulse back to arbiter

	// interface back to FIFO.

	input			FRAME_FIFO_AFULL,  // frame fifo almost full, (5-6 words reserved for headroom)
	
	output	logic [15:0]	DATA_2_FIFO,
	output	logic 		FRAME_FIFO_PUSH

);



////////////////////////////////////////////////////////////
// State machine
////////////////////////////////////////////////////////////

typedef enum logic [3:0] {
    IDLE,
    FRAME_START,
    METADATA,
    HDR_WORD,
    HDR_CID,
    PAYLOAD,
    PAYLOAD_X,
    ESC_DATA, // state to emit payload ^ FFFF
    COOLDOWN, // state to stay still, no pop, no push, just wait until fram fifo is less congested
    FRAME_END
} state_t;

state_t curr_state, next_state;


localparam ext_len = 16 - $clog2(N_CH);

////////////////////////////////////////////////////////////
// Registers
////////////////////////////////////////////////////////////

reg [$clog2(N_CH)-1:0] prev_id;
reg [$clog2(N_CH)-1:0] buf_id;

reg [15:0] payload_buf;
reg buf_valid;

reg esc_pending, payload_pending;

reg [13:0] frame_cnt;


////////////////////////////////////////////////////////////
// Status signals
////////////////////////////////////////////////////////////

wire data_fifo_not_empty = ~(&EMPTY); 

wire payload_reserved = (payload_buf == 16'hC0DE) || (payload_buf == 16'hDEAD) || (payload_buf == 16'hBEEF);


////////////////////////////////////////////////////////////
// State register
////////////////////////////////////////////////////////////

always @(posedge CLK75M or negedge rst_n) begin
    if(!rst_n)
        curr_state <= IDLE;
    else
        curr_state <= next_state;
end


////////////////////////////////////////////////////////////
// Payload capture (skid buffer)
////////////////////////////////////////////////////////////

always @(posedge CLK75M) begin
    if(data_valid) begin
        payload_buf <= FIFO_DAT;
        buf_id <= SEL_ID;
    end
end


////////////////////////////////////////////////////////////
// Control register updates
////////////////////////////////////////////////////////////



always @(posedge CLK75M or negedge rst_n) begin
    if(!rst_n) begin
        prev_id <= 0;
        esc_pending <= 0;
        frame_cnt <= 0;
        buf_valid <= 0;
        payload_pending <= 0;
    end
    else begin

        case(curr_state)

        	IDLE: 
        	begin 

        	end

        	FRAME_START: 
        	begin 

        	end

        	METADATA: 
        	begin 
        		frame_cnt <= frame_cnt +1;
        	end

        	HDR_WORD: 
        	begin 

        	end

        	HDR_CID: // this state can appear either at the begining of the fresh frame out of IDLE, or channel ID changed
        	begin 
        		if (!payload_pending) begin
        			prev_id <= SEL_ID;
        		end
        		else
        		begin 
        			prev_id <= buf_id;
        		end
        	end

        	PAYLOAD:
        	begin
        		 payload_pending <= 0;
        	 
        	end 

        	PAYLOAD_X: // messy state a lot of stuff can happen, this is also when the new data comes in. we need to decide if we need to do insertion
        	begin 
        		if (prev_id != SEL_ID) begin // channel is different, either insert C0DE, or frame wrap. either way, we will need to set up payload pending.
        			payload_pending <= 1;
        		end


        	end 

        	FRAME_END: 
        	begin 

        	end

        	default: /* */; 
        endcase
       end
end






////////////////////////////////////////////////////////////
// Next state logic
////////////////////////////////////////////////////////////

always @(*) begin

    next_state = curr_state;

    DATA_2_FIFO = 16'h0000;
    FRAME_FIFO_PUSH = 0;
    
    do_pop_slot = 0;


    case (curr_state)

    	IDLE: // absolute idle state because FIFO is empty
    	begin 
    		if (data_fifo_not_empty) begin
    			next_state = FRAME_START;
    		end
    	end

    	FRAME_START:
    	begin 
    		DATA_2_FIFO = 16'hFACE;
    		FRAME_FIFO_PUSH = 1;
    		next_state = METADATA;
    	end

    	METADATA: 
    	begin 
    		DATA_2_FIFO = {2'b00, frame_cnt};
    		FRAME_FIFO_PUSH = 1;
    		next_state = HDR_WORD;
    	end

    	HDR_WORD: 
    	begin 
    		next_state = HDR_CID;
    		DATA_2_FIFO = 16'hC0DE;
    		FRAME_FIFO_PUSH = 1; 
    		if (!payload_pending) begin // fresh new frame without payload or cid pending
    			do_pop_slot = 1;
    		end
    	end

    	HDR_CID: 
    	begin 
    		next_state = PAYLOAD;
    		FRAME_FIFO_PUSH = 1;
    		if (payload_pending) begin // if there are payload/cid pending because of C0DE header insertion
    			DATA_2_FIFO = { {ext_len{1'b0}}, buf_id};
    		end
    		else 
    		begin 
    			DATA_2_FIFO = { {ext_len{1'b0}},SEL_ID}; // if it is a fresh frame and has been requested from last cycle
    		end
    	end

    	PAYLOAD: // consume state, this is where payload is actually consumed, in the meantime, a new data will be requested if FIFOs are not empty.
    	begin
            if (payload_reserved) begin // if the payload in in the reserved bank, 
                DATA_2_FIFO = 16'hBEEF; // we will need to push ESC and then
                FRAME_FIFO_PUSH = 1;    // jump to data escaping state.
                next_state = ESC_DATA;
            end
            else
            begin 
            // if the data is not in the reserved bank...
            // regardless of next state, the data will need to be pushed into frame fifo
                DATA_2_FIFO = payload_buf;
                FRAME_FIFO_PUSH = 1;
                // if the fifo are all empty after this read
                if (!data_fifo_not_empty) 
                begin 
    			     next_state = FRAME_END;
    		    end
                else
                begin 
                    next_state = PAYLOAD_X;
    			    do_pop_slot = 1;
    		    end
    		
    	   end
        end

        ESC_DATA: // The state that will only be entered when the payload if in the reserved bank, simply output the xor ffff of the word.
        begin 
            DATA_2_FIFO = payload_buf ^ 16'hFFFF;
            FRAME_FIFO_PUSH = 1;

            //depending on the pixel fifo state, we shall jump back to payload_X, or finish the frame
            if (!data_fifo_not_empty) begin
                next_state = FRAME_END;    // pixel fifos are all empty, jump to finish the frame.
            end
            else
            begin 
                next_state = PAYLOAD_X;     // pixel fifos are not empty, we shall do fifo pop again
                do_pop_slot = 1;
            end
        end



    	PAYLOAD_X: // this is the state of chaos, where all the header insertion will happen here, data should be valid at this stage.
    	begin
            if (FRAME_FIFO_AFULL) begin // frame fifo almost full, we shall jump to the state where we will just do nothing and wait
                 next_state = COOLDOWN; // no push, no pop, no evaluation, simply just go cool down.
            end
            else
            begin 
             
                if (SEL_ID == prev_id) begin // current data still has the same selected id, outputs nothing
                    next_state = PAYLOAD;
    		    end
    		    else if (SEL_ID >  prev_id) begin // current data comes from a different channel ID, but this ID is bigger than what we have now
                    next_state = HDR_CID;
    			    DATA_2_FIFO = 16'hC0DE; // insert C0DE header here
    			    FRAME_FIFO_PUSH = 1;
    		    end
    		    else		// curernt data comes from a channel that has a smaller channel ID (we have a wrap/drop), we need to seal frame
    		    begin 
    			    next_state = FRAME_START;
    			    DATA_2_FIFO = 16'hDEAD;
    			    FRAME_FIFO_PUSH = 1;
    		    end
            end 

    	end


        COOLDOWN: // this is the state where we shall wait until the packet building fifo is not almost full.
        begin 
            if (!FRAME_FIFO_AFULL) begin
                next_state = PAYLOAD_X;
            end
        end


    	FRAME_END: // A simple state where a key word DEAD is produced
    	begin 
    		next_state = IDLE;
    		DATA_2_FIFO = 16'hDEAD;
    		FRAME_FIFO_PUSH = 1;
    	end
    


    	default : /* default */;
    endcase
end

endmodule