// This is the module definition for the compression module with the following new designs:
//	+ Instead of relying on the external counting clock, we shall have the internal
//    counter that will be enabled under "silence" mode, which should increment at the rate 
//    of the evaluation (20 MHz if 3-bit mode, 6.66 MHz if 1-bit mode )
//  + Adding the input of rescombo so we could decide internally where the 50% threshold is
//    for 1-bit mode
//	+ New additional 1-bit mode that functions similarly as the old algorithm. But it 
//	  only do the evaluation every 3 cycles.
//	+ Added Gray to Binary conversion to convert the 3-bit gray code back into binary
//
//
//	1-bit mode functions and process data as below:
//	
//	1. Depending on the resi combo, we shall convert the 3-bit pixel values into 1-bit
//	2. Accumulate 3 cycles data and form a 15-bit word
//	3. The word shall be compared to the last saved 15-bit word, depending on whether 
//	   they are same or different, we do the following:
//	   1> They are the same, repetition starts, we remain silent and the internal 
//	   	  counter starts incrementing.
//	   2> They are different, we export the raw data with leading 0, update the stored
//	      15-bit word
//	4. When it is in silence mode, but the new word does not match the saved word,
//	   we export the current silence count with a leading 1, and also the new word
//	5. When in silence mode, and the internal counter reaches 7FFF, we export a wrap word
//	   0x8000
//



module Row_encode_5P (
	
	input 				clk40m,				// max 40MHz clock
	input				rstn, 				// active low reset
	
	input 				EN, 				// active high enable
	input 				one_bit, 			// one bit mode on or off, change of this mode can only happen at IDLE state
	input 				pix_valid, 			// pixel valid signal from ADC
	//input 		[2:0]	rescombo, 			// resistor combo from ADC?  we actually do not need this for the implementation
	input 		[4:0] 	pix_mask, 			// 5-bit pixel mask to block out the pixel
	input 		[14:0]  pix_gray,				// 15-bit pixel values, in gray code

	output 	reg			enc_ready, 			// 1-bit pulse for encoding ready
	output 	reg	[15:0]  enc_data        	// encoded 16-bit data 	
	

);



// register declaration

reg  pix_valid_x_1;

reg [14:0]  repeating_pattern; // temporary word to save repeating pattern

reg [1:0] 	  acc_counter;  // only used in 1-bit mode
reg [9:0]     acc_temp_pattern; // temporary saved accumulated word for 1-bit mode

reg [14:0] 	  silence_counter;  // the counter that increment when it is in silent mode

reg [2:0]	  current_state, next_state;

reg data_flag;  	// we have data to push, assert this to indicate that
reg wake_up_flag;

reg first_push;		// helper flag for 1-bit mode only, to identify the very first loop

reg mode;      // the register to register 1-bit mode or what?

wire pix_valid_rise;

wire [14:0] 	pix_bin;	// input pixel values in binary format
wire [14:0] 	pix_in_mask; // input pixel values after getting masked

wire [4:0] 		pixel_1bit;  // the binarified pixel value




// State parameters list

localparam IDLE = 0;

// Dedicated to 1-bit mode
localparam PUSH = 1;
localparam WAIT = 2;
localparam ALARM = 3;

// For 3-bit mode
localparam PUSH3 = 4;
localparam WAIT3 = 5;
localparam ALARM3 = 6;



always @(posedge clk40m)
begin
	pix_valid_x_1 <= pix_valid;
end


assign pix_valid_rise = pix_valid & (~pix_valid_x_1);



// pixel pre-processing

function [2:0] gray_to_binary;
    input [2:0] gray;
    begin
        gray_to_binary[2] = gray[2];
        gray_to_binary[1] = gray[2] ^ gray[1];
        gray_to_binary[0] = gray[2] ^ gray[1] ^ gray[0];
    end
endfunction


// Convert the gray back to binary and also generate the 
genvar i;

generate
    for (i = 0; i < 5; i = i + 1) begin : GEN_PIXEL

    	// Gray → binary
        assign pix_bin[i*3 +: 3] = gray_to_binary(pix_gray[i*3 +: 3]);

        // Apply pixel mask
        assign pix_in_mask [i*3 +: 3] = pix_mask[i] ? pix_bin[i*3 +: 3]: 3'b111; 

        // Binary classification
        assign pixel_1bit[i] = (pix_in_mask[i*3 +: 3] > 3'b100);
    end
endgenerate


// routine state register update

always @(posedge clk40m or negedge rstn)
begin
	if (!rstn) begin
		current_state <= IDLE;
	end
	else 
	begin
		current_state <= next_state;
	end
end



// registers update for each state


always @(posedge clk40m or negedge rstn)
begin
	if (!rstn) begin
		// reset all the possible registers
		repeating_pattern <= 0;
		acc_counter <= 0;
		acc_temp_pattern <= 0;
		silence_counter <= 0;
		data_flag <= 0;
		first_push <= 1;
		wake_up_flag <= 0;
	end
	else begin
		
	case (current_state)
	
		IDLE: 
		begin
			mode <= one_bit;
			
			if (EN) begin // module enabled
				if (pix_valid_rise) begin // and it is a data valid high
					if (mode) begin // if this is one bit mode, we will shift binarised data in and increment the count by 1
							acc_counter <= acc_counter +1;
							acc_temp_pattern <= {acc_temp_pattern[4:0], pixel_1bit};
						end
					else	// this is just normal 3-bit mode
						begin
							repeating_pattern <= pix_in_mask;
							data_flag <= 1;
						end
				end
			end
			
		end

		PUSH: 
		begin
			if (EN) begin // module is enbaled and actively accumulate-push
				if (wake_up_flag) begin
					wake_up_flag <= 0;
					silence_counter <= 0;
				end
				else begin
				if (pix_valid_rise) begin // there is valid data coming through
					if (acc_counter < 2) begin // accumulated less than 2 words, acc_cnt = 0, 1. We keep on accumulating
						acc_counter <= acc_counter +1;
						acc_temp_pattern <= {acc_temp_pattern[4:0], pixel_1bit}; // left shift by 5 << 5
					end
					else begin 			// accumulated exactly 2 words, now we have the third one
						acc_counter <= 0;  // clear up the accumulation
						acc_temp_pattern <= 0;
						if (first_push) begin // very first round of push, we push the data out anyway
							data_flag <= 1;
							repeating_pattern <= {acc_temp_pattern, pixel_1bit};
							first_push <= 0;
						end
					  	else begin
					  		if ({acc_temp_pattern, pixel_1bit} != repeating_pattern ) begin // if the new 3 cycle data does not match the repeating pattern
					  			data_flag <= 1;
					  			repeating_pattern <= {acc_temp_pattern, pixel_1bit};
					  		end
					  		else begin // if the new 3 cycles data matches the repeating pattern, we jump into wait state, and we start incrementing the counter
					  			 data_flag <= 0;
					  			 silence_counter <= silence_counter +1;
					  			end
					  			
					  		end
					  		
					  	end  	
							
					end
						
					end
				end
				else if (data_flag) begin
					data_flag <= 0;
				end
				end
			end
			else begin // module disbaled, we clear up the registeres we used
				repeating_pattern <= 0;
				acc_counter <= 0;
				data_flag <= 0;
				acc_temp_pattern <= 0;
				first_push <= 1;

			end

			
		end

		WAIT: 
		begin
			// if the module is enabled
			if (EN) begin
				if (pix_valid_rise) begin // on the valid data 
					if (acc_counter < 2) begin // if we accumulated less than 2 words, we keep accumulating
						acc_counter <= acc_counter + 1;
						acc_temp_pattern <= {acc_temp_pattern[4:0], pixel_1bit};
					end
					else begin // we have accumulated 2 words, now we evaluate
						acc_counter <= 0;
						acc_temp_pattern <= 0;

						if ({acc_temp_pattern, pixel_1bit} != repeating_pattern) begin 
						// the pattern has changed, we need to jump back to push state and 
						// update the pattern and set up the flags
						wake_up_flag <= 1;
						data_flag <= 1;
						repeating_pattern <= {acc_temp_pattern, pixel_1bit};
						end
						else begin
						// pattern has not changed, we keep on incrementing the counter
						silence_counter <= silence_counter +1; // n -> n+1
							
						end
						
					end
				end
				else begin // othere cycles that data is not valid
					data_flag <= 0;
				end
				
			end
			else begin // if the module is disabled, we need to export the pattern and where we are at the silence count
				data_flag <= 1;
			end
			
		end

		ALARM: 
		begin
			
		end

		PUSH3: // 3-bit mode where we only consider if it matches or not
		begin
			if (EN) begin // when module is enabled
			// check if we just switched back from WAIT3
				if (wake_up_flag)
					begin
					wake_up_flag <= 0;
					silence_counter <= 0; // clear silence count
					end
				else
					begin
					// push new data in the buffer if the input data is valid but different
					if (pix_valid_rise ) begin
						if (repeating_pattern != pix_in_mask) begin // if the pattern is not repeating
							repeating_pattern <= pix_in_mask;
							data_flag <= 1;
						end
						else begin // if the pattern is repeating, first time ever in this tate, start incrementing the silence count
							data_flag <= 0;
							silence_counter <= silence_counter +1;	// 0 -> 1		
						end	
					end
					// if the input is not valid we do nothing
					// but we need to flip the data_flag
					else if (data_flag) begin
						data_flag <= 0;
					end

				end
			else begin // module is disabled, we will jump back to IDLE next cycle, clean up the used registers
				repeating_pattern <= 0;
				wake_up_flag <= 0;
				silence_counter <= 0;
				data_flag <= 0;				
			end
		end

		WAIT3: 
		begin
			// if the module is enabled
			if (EN) begin
				// we only operate when there is valid data coming through
				if(pix_valid_rise)
				begin
					if (repeating_pattern != pix_in_mask) begin // the pattern is broken, new pattern formed, exit silence
						repeating_pattern <= pix_in_mask;
						data_flag <= 1;
						wake_up_flag <= 1;  
					end
					else // pattern is repeating, we increment the silence count 
						begin
							silence_counter <= silence_counter +1; // n -> n+1
							data_flag <= 0;
						end
					
				end
				else 
				begin
					data_flag <= 0;
				end
			
			end
			else // if module is disabled while in silence, we switch back to push3 to push the pattern out
				begin
					data_flag <= 1;

				end

		end

		ALARM3: 
		begin
			
		end
		default : /* default */;
	endcase

	end
end





// State transition

always @(*)
begin
	next_state = current_state;
	enc_data = 0;
	enc_ready = 0;

	case (current_state)

		IDLE: 
		begin
			if (EN) begin
				if (pix_valid_rise) begin
					if (one_bit) begin
						next_state = PUSH;
					end
					else begin
						next_state = PUSH3;	
					end
					
				end
			end
		end

		/**
		 *  One bit mode states
		 */
		PUSH: 
		begin
			if (wake_up_flag) begin
				enc_data = {1'b1, silence_counter};
				enc_ready = 1;
			end
			else if (data_flag) begin
				enc_data = {1'b0, repeating_pattern};
				enc_ready = 1;
			end

			// next state logic
			if (EN) begin
				/* when module is enabled */
				if (pix_valid_rise && (acc_counter == 2'b10)) begin 
				// if we have accumulated 2 words and now seeing the third one
					if ({acc_temp_pattern, pixel_1bit} == repeating_pattern) begin
					// if the accumulated words matches the pattern, we jump into wait state
						next_state = WAIT; 
					end
				
				end
			
			end
			else begin
				// module is disabled while in push state
				next_state = IDLE;
			end
			
		end

		WAIT: 
		begin
			// silent mode 
			if (EN) begin
				/* module is still enabled */
				if (pix_valid_rise && (acc_counter == 2'b10)) begin
					/* if we have accumulated 2 words and now having a third */
					if ({acc_temp_pattern, pixel_1bit} != repeating_pattern) begin
						// pattern breaks
						next_state = PUSH;
					end
					else if (silence_counter == 15'h7fff) begin
						// silence counter is 32767
						next_state = ALARM;
					end
				end
			end
			else begin
				// module is disabled, we export the silence counter and jump back to push to ease back in
				enc_ready = 1;
				enc_data = {1'b1, silence_counter};
				next_state = PUSH;
			end
			
		end

		ALARM: 
		begin
			next_state = WAIT;
			enc_data = 16'h8000;
			enc_ready = 1;
		end

		/**
		 * Full 3-bit mode operating states
		 */

		PUSH3:
		begin
			// if it just switches from Wait, we need to export both the counter and data
			// priority is timer
			if (wake_up_flag) // just switched back from silence
				begin
					enc_data = {1'b1, silence_counter};
					enc_ready = 1;
				end
			else if (data_flag) begin
				enc_ready = 1;
				enc_data = {1'b0, repeating_pattern};
			end

			// next state logic
			if (EN) begin
				if (pix_valid_rise && (pix_in_mask == repeating_pattern)) begin // only switch when pattern repeats
				next_state = WAIT3;
				end
			end
			else begin
				next_state = IDLE;
			end
			
			
		end

		WAIT3: 
		begin
			// Do not export anything in this state
			// next state logic to either go back to push or go to alarm
			// if the pattern is different now
			if (EN) begin
				if (pix_valid_rise && (pix_in_mask != repeating_pattern)) begin
					next_state = PUSH3;
				end
				else if (silence_counter == 15'h7fff) begin // if silence counter has reached limit
					next_state = ALARM3;
				end
			end
			else begin // if module was disabled at this state, we switch back to push3 state to export pattern, but we will export the 
				// silence counter remained
				enc_data = {1'b1, silence_counter};
				enc_ready = 1;
				next_state = PUSH3;
			end
			
			
		end

		ALARM3: 
		begin
			// only assert a single clock cycle of alarm
			enc_data = 16'h8000;
			enc_ready = 1;
			next_state = WAIT3;
		end
	
		default : /* default */;
	endcase

end



endmodule