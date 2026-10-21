// Ver. 0.1
// The packet builder I built from the table derived.
// TODO: Include the escape mechanism, correct response when FRAME FIFO is full, pixel fifo overflow contingency.
// 
// Ver. 0.2
// This version will add extra states to deal with escape mechanism.
// and
// Frame fifo almost full case. 
//
// Ver. 0.3
// This version is the updated packet builder that implemented the following changes:
//  + Renamed the module to packet_builder instead of Packet_builder
//  + Added ports and states to interact with local event handler to handle special events
//  + Added extra state to export META info (pkt_type)
// Ver. 0.3.1
// This is simply a minor iteration to add the support for event_time_valid

module packet_builder #(parameter int N_CH = 8) (
	input 	CLK75M,    // Clock, 75 Mhz
	input 	rst_n,  // Asynchronous reset active low

    // interface from local event handler
    input               event_valid,        // the event valid signal that comes from local event handler, which lives in 40 MHz
    input       [3:0]   event_type, 
    input       [2:0]   event_fifo_id, 
    input       [44:0]  event_time0, 
    input       [44:0]  event_time1, 
    input               event_time_valid,   // simple reg to indicate the completion of the encapsulation of packets.

    output  logic       event_ack,

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

typedef enum logic [4:0] {
    IDLE,
    FRAME_START,
    SCI_WORD, // new state to export the science words as the pkt_type
    METADATA,
    HDR_WORD,
    HDR_CID,
    PAYLOAD,
    PAYLOAD_X,
    ESC_DATA, // state to emit payload ^ FFFF
    COOLDOWN, // state to stay still, no pop, no push, just wait until fram fifo is less congested
    FRAME_END, 
    INTRP_STA, // start handling interrupt
    EVENT_W,  // export event words "EV"
    TYPE_EVENT, // export type of events that happened
    EVE_TIMET0, // export the start time of the event
    EVE_TIMET1, // export the ending time of the event
    WAIT_TIME1, // wait for the time1 to be ready to safely sample.
    EVE_FIFO_ID, // export the event fifo id, only applicable for overflow
    INTRP_END,  // finishing handling interrupt
    WAIT_ACK   // wait for the acknowledge signal to be recognised
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


///////////////////////////////////////////////////////////
// additional new regs introduced in ver 0.3

reg  event_valid_meta, event_valid_sync;

reg  event_time_valid_meta, event_time_valid_sync;

reg [1:0] event_t0_t1_cnt; // count to 3, since we need to stay in eve_time0 and eve_time1 for 3 cycles

reg [47:0] event_time_buf;

// synchronisation from 40 MHz to 75 MHz
always_ff @(posedge CLK75M or negedge rst_n) begin 
    if(~rst_n) begin
        event_valid_meta <= 0;
        event_valid_sync <= 0;
        event_time_valid_meta <= 0;
        event_time_valid_sync <= 0;
    end else begin
        event_valid_meta <= event_valid;
        event_valid_sync <= event_valid_meta;
        event_time_valid_meta <= event_time_valid;
        event_time_valid_sync <= event_time_valid_meta;
    end
end



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
        event_t0_t1_cnt <= 0;
        event_time_buf <= 0;
    end
    else begin

        case(curr_state)

        	IDLE: 
        	begin 

        	end

        	FRAME_START: 
        	begin 

        	end


            SCI_WORD: 
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

            INTRP_STA: 
            begin 
                event_time_buf <= {3'b000, event_time0}; // 3bit + 45 bit --> 48 bit 
            end

            EVENT_W: 
            begin 
            end

            TYPE_EVENT: 
            begin 
            end

            EVE_TIMET0: 
            begin 
                if (event_t0_t1_cnt < 2'b10) begin
                    event_t0_t1_cnt <= event_t0_t1_cnt + 1;
                    event_time_buf <=  (event_time_buf >> 16);
                end
                else
                begin
                    event_t0_t1_cnt <= '0;
                    if (event_time_valid_sync) begin
                        event_time_buf <= {3'b000, event_time1};
                    end
                end
            end

            EVE_FIFO_ID:                // state that can only occur in overflow case
            begin 
                if (event_time_valid_sync) begin    
                    event_time_buf <= {3'b000, event_time1};
                end
            end

            WAIT_TIME1: 
            begin 
                if (event_time_valid_sync) begin
                    event_time_buf <=  {3'b000, event_time1};
                end
            end


            EVE_TIMET1: 
            begin 
                if (event_t0_t1_cnt < 2'b10) begin
                    event_t0_t1_cnt <= event_t0_t1_cnt +1;
                    event_time_buf <= (event_time_buf >> 16);
                end
                else begin
                    event_t0_t1_cnt <= '0;
                end
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
    // new output in ver 0.3
    event_ack = 0;
    case (curr_state)

    	IDLE: // absolute idle state because FIFO is empty
    	begin
            // module prioritise the process for interrupt over normal process
            if (event_valid_sync) begin
                 next_state = INTRP_STA;
            end
            else 
    		if (data_fifo_not_empty) begin
    			next_state = FRAME_START;
    		end
    	end

    	FRAME_START:
    	begin 
    		DATA_2_FIFO = 16'hFACE;
    		FRAME_FIFO_PUSH = 1;
    		next_state = SCI_WORD;
    	end

        ////////////////////////////////
        // new state in ver 0.3
        SCI_WORD:  // a very simple state that only exports the science packet type
        begin
            DATA_2_FIFO = 16'h5343; // asc ii for "SC"
            FRAME_FIFO_PUSH = 1;
            next_state = METADATA;
        end
        ////////////////////////////////

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
    
        ////////////////////////////////
        // new state in ver 0.3
        INTRP_STA:  // beginning state to handle event
        begin 
            next_state = EVENT_W;
            DATA_2_FIFO = 16'hFACE; 
            FRAME_FIFO_PUSH = 1;
        end

        EVENT_W: // event word export
        begin 
            next_state = TYPE_EVENT;
            DATA_2_FIFO = 16'h4556; // asc ii words for "EV"
            FRAME_FIFO_PUSH = 1;
        end

        TYPE_EVENT: // state to export type of event
        begin 
            next_state = EVE_TIMET0;
            DATA_2_FIFO = { 12'b0, event_type};
            FRAME_FIFO_PUSH = 1;
        end

        EVE_TIMET0: // export the time 0
        begin 
            FRAME_FIFO_PUSH = 1;
            DATA_2_FIFO = event_time_buf[15:0]; // only export the last 16-bit of the buffer
            if (event_t0_t1_cnt >= 2'b10)
            begin 
                if (event_type == '0) begin // overflow type
                    next_state = EVE_FIFO_ID;
                end
                else begin
                    if (event_time_valid_sync) begin
                        next_state = EVE_TIMET1; // if the event information is complete and stable
                     end
                    else begin 
                        next_state = WAIT_TIME1; // wait for the last piece of the event to be finished
                    end 
                end
            end
        end

        EVE_FIFO_ID: // export the overflow id
        begin 
            FRAME_FIFO_PUSH = 1;
            DATA_2_FIFO = {13'd0, event_fifo_id}; // 13-bit + 3-bit id --> 16 bit data
            if (event_time_valid_sync) begin
               next_state = EVE_TIMET1; // export event time t1 next since it is now ready
            end
            else begin 
                next_state = WAIT_TIME1;  // event time T1 is not ready to sample, we wait
            end
                    
        end

        WAIT_TIME1: 
        begin 
            if (event_time_valid_sync) begin  // DO NOTHING BUT WAIT
                next_state = EVE_TIMET1;
            end
        end



        EVE_TIMET1: // same logic to export the event timer t1
        begin 
            FRAME_FIFO_PUSH = 1;
            DATA_2_FIFO = event_time_buf[15:0];
            if (event_t0_t1_cnt >= 2'b10) begin
                next_state = INTRP_END;
            end
        end

        INTRP_END: 
        begin 
            FRAME_FIFO_PUSH = 1;
            DATA_2_FIFO = 16'hDEAD;
            next_state = WAIT_ACK;
        end

        WAIT_ACK: 
        begin 
            event_ack = 1;
            if (!event_valid_sync) begin
                next_state = IDLE;
            end
        end



        ////////////////////////////////
    
    	default : /* default */;
    endcase
end

endmodule