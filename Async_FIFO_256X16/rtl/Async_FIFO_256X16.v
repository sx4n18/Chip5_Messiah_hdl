/////////////////////////////////////////////////////////////////////////
// This is the async FIFO module that is built on top of FSAOA_C_DPSRAM
// AkA the dual port sram with data depth of 256, and data width of 16-bit
// 
//
// Macro definitions:
// - IDEAL_DPRAM: enable the behavioural level of dual port ram
// - REG_FILE_IP: enable register file (1W1R) IP implementation of the Async FIFO
// - NEXT_CYCLE_READ: the read data will be available next clock cycle instead of right now (prefetch FIFO)
// 
// By default, the DPRAM used in this implementation is a real Dual-Port RAM (2W2R)
//
// TODO: The async fifo is a prefetch FIFO, therefore the DOB of the dual-port RAM always outputs
// 		 data that is pointed by the read_ptr.
//		 But the actual output depends on POP signal.
//
// assign DATAOUT = POP? DOB: 16'd0;
// This design is a little dumb and may bring extra latency to DATAOUT.
//
//    CARR_ARB( .(POP)) | ---->  ASYNC_FIFO -> update read_ptr
//                      |              |  
//						|			   V
//						|<<<<<DATAOUT<----DOB 
//__________________________________________________
// The future version should change this design so that Async_FIFO should always be a prefetch FIFO, POP should only update the read pointer
//
// Ver 1.0
// In this version, we fixed the following known bugs:
// + register FULL_REG is assigned on the write-side clock and therefore should be reset by WRSTN instead of RRSTN
// Added new features:
// + Change this design into a real prefetch async FIFO to connect the data output to the RAM port.
// + Added a new port to output empty signal from 40 Mhz clock domain


module Async_FIFO_256X16 (


		// write side ports.

		input 			CLK40M,         // writing clock at 40 MHz, effectively on 20 MHz
		input [15:0] 	DATAIN,			// writing side of the FIFO, 16-bit data input
		input 			PUSH,			// Data will be pushed into the FIFO when PUSH is asserted
		input 			WRSTN,			// active low reset on the write side 

		output			FULL_40M,     		// Full flag for the write logic, this will be in 40 MHz domain

		// read side ports

		input 			CLK75M, 		// Read side clock will be 75 MHz, effectively 37.5 MHz.
		input 			POP,  			// Simple pop signal to pop the data out of the FIFO.
		input 			RRSTN,			// Active low reset for read

		output 			ALMOST_FULL_75M,	// This is the almost full flag that should be synced to 75MHz
		output			EMPTY_75M, 			// Naturally the EMPTY_75M flag that works at the read side, 75 MHz
		// new port added to output empty signals from 40 Mhz clock domain
		output          EMPTY_40M, 
		output [15:0]	DATAOUT			// Popped data from FIFO.


	);



// This is the simple 8-bit gray code to binary 

function automatic reg [8:0] Gray2Bin (input [8:0] GrayVal);
	integer i;
	reg [8:0] Conv_Bin;
	begin 
		Conv_Bin[8] = GrayVal[8];
		for ( i = 7; i >= 0; i=i-1) begin
			Conv_Bin[i] = Conv_Bin[i+1] ^ GrayVal[i];
		end
	end
	return Conv_Bin;
endfunction


// This is the simple 8-bit binary to gray code function

function automatic reg [8:0]  Bin2Gray (input [8:0] BinVal);
	reg [8:0] GrayVal;
	begin 
		GrayVal = BinVal ^(BinVal>>1);
	end
	return GrayVal;
endfunction 


reg [8:0] write_prt_bin, read_prt_bin;
reg [8:0] write_prt_gray, read_prt_gray;
reg [8:0] write_prt_gray_sync_1, write_prt_gray_sync_2;
reg [8:0] read_prt_gray_sync_1, read_prt_gray_sync_2;

reg [8:0] next_write_gray, next_read_gray;


reg [8:0] read_prt_W, write_prt_R;


reg [8:0] fifo_fill_level;

reg FULL_REG;


wire PUSH_OK, POP_OK;

// generate gray code from binary value
assign write_prt_gray = Bin2Gray(write_prt_bin);
assign read_prt_gray = Bin2Gray(read_prt_bin);
assign PUSH_OK = PUSH && ~FULL_40M;
assign POP_OK = POP && ~EMPTY_75M;
assign next_write_gray = Bin2Gray(write_prt_bin+ PUSH_OK);
assign next_read_gray = Bin2Gray(read_prt_bin+ POP_OK);


// cross clock domain crossing

// cross from write to read, write at 40M, read at 75M
always @(posedge CLK75M or negedge RRSTN)
if (!RRSTN) begin
	write_prt_gray_sync_1 <= 0;
	write_prt_gray_sync_2 <= 0;
end
else
// Sync the Gray write pointer to read clock
begin 
	write_prt_gray_sync_1 <= write_prt_gray;
	write_prt_gray_sync_2 <=  write_prt_gray_sync_1;
end

always @(posedge CLK40M or negedge WRSTN)
if(!WRSTN)
begin 
	read_prt_gray_sync_1 <= 0;
	read_prt_gray_sync_2 <= 0;
end
else
// Sync the Gray read pointer to write clock
begin
	read_prt_gray_sync_1 <= read_prt_gray;
	read_prt_gray_sync_2 <=  read_prt_gray_sync_1;
end





// write clock domain
always @(posedge CLK40M or negedge WRSTN) 
begin
	if(~WRSTN) begin
		write_prt_bin <= 0;
	end else begin
		// if push is asserted, increment the writing pointer
		if (PUSH && !FULL_40M) begin
			// use this line when running behavioural level simulation for afifo
			// real DPRAM IP + behavioural level external circuitry
			 write_prt_bin <= #1 write_prt_bin +1;
			// 
			// use the following line when running synthesis.
			//write_prt_bin <= write_prt_bin +1;
		end
		
	end
end

// read pointer at the write clock domain of 40 MHz

assign read_prt_W = Gray2Bin(read_prt_gray_sync_2);
// added new empty signal in 40 Mhz
assign EMPTY_40M = (write_prt_gray == read_prt_gray_sync_2);

// register full flag

always @(posedge CLK40M or negedge WRSTN) 
begin 
	if(~WRSTN) begin
		FULL_REG <= 0;
	end else begin
		FULL_REG <= (next_write_gray == {~read_prt_gray_sync_2[8:7], read_prt_gray_sync_2[6:0]}) ;
	end
end

assign FULL_40M = FULL_REG;


// read clock domain

always @(posedge CLK75M or negedge RRSTN) 
begin 
	if(~RRSTN) begin
		read_prt_bin <= 0;
	end else begin
		// if POP is asserted, increment the reading pointer
		if (POP && !EMPTY_75M) begin 
			// use this line when running behavioural level simulation for afifo
			// real DPRAM IP + behavioural level external circuitry
			read_prt_bin <= #1 read_prt_bin +1;
			// 
			// use the following line when running synthesis.
			//read_prt_bin <= read_prt_bin +1;
		end

	end
end

// write pointer at the read clock domain of 75 MHz

assign write_prt_R = Gray2Bin(write_prt_gray_sync_2);

assign EMPTY_75M = (write_prt_gray_sync_2 == read_prt_gray);

assign fifo_fill_level = write_prt_R - read_prt_bin;

assign ALMOST_FULL_75M = (fifo_fill_level >= (256-8));  // Set the margin of 8


// unconnected wires

wire [15:0] DIB;

wire [15:0] DOA;


// optional declaration

wire [15:0] DOB;


// my own version of DPRAM design

// instantiated DPSRAM to be made into FIFO, 256 X 16-bit
// A side will be the write side; 
// B side will be the read side;

`ifdef IDEAL_DPRAM

FSA0A_C_DPSRAM DPRAM_inst (
	.A   (write_prt_bin[7:0]   ),
	.B   (read_prt_bin[7:0]   ),
	.DIA (DATAIN ),	// write data into FIFO
	.DIB (DIB ),	// DO NOT CONNECT
	.OEA (1'b0 ), // side A always 0, do not output
	.OEB (1'b1 ),	// side B always 1, always do output
	.CKA (CLK40M ),	// write clock of 40M
	.CKB (CLK75M ),	// read clock of 75M
	.CSA (PUSH_OK ),

	`ifdef NEXT_CYCLE_READ
	.CSB (POP_OK ),		// next cycle read
	`else 
	.CSB (1'b1),	//simply consume the data.
	`endif 

	.WEAN(2'b00), // always write on side A
	.WEBN(2'b11), // always read on side B
	.DOA (DOA ),  // side A data out unconnected
	.DOB (DOB )	// Read side of data out
);


// the real verilog from the front end design file.

`elsif REG_FILE_IP

	
SZ180_256X16X1CM4 i_SZ180_256X16X1CM4 (
	.DO0 (DOB[0] ),
	.DO1 (DOB[1] ),
	.DO2 (DOB[2] ),
	.DO3 (DOB[3] ),
	.DO4 (DOB[4] ),
	.DO5 (DOB[5] ),
	.DO6 (DOB[6] ),
	.DO7 (DOB[7] ),
	.DO8 (DOB[8] ),
	.DO9 (DOB[9] ),
	.DO10(DOB[10]),
	.DO11(DOB[11]),
	.DO12(DOB[12]),
	.DO13(DOB[13]),
	.DO14(DOB[14]),
	.DO15(DOB[15]),
	.DI0 (DATAIN[0] ),
	.DI1 (DATAIN[1] ),
	.DI2 (DATAIN[2] ),
	.DI3 (DATAIN[3] ),
	.DI4 (DATAIN[4] ),
	.DI5 (DATAIN[5] ),
	.DI6 (DATAIN[6] ),
	.DI7 (DATAIN[7] ),
	.DI8 (DATAIN[8] ),
	.DI9 (DATAIN[9] ),
	.DI10(DATAIN[10]),
	.DI11(DATAIN[11]),
	.DI12(DATAIN[12]),
	.DI13(DATAIN[13]),
	.DI14(DATAIN[14]),
	.DI15(DATAIN[15]),
	.A0  (read_prt_bin[0]  ),
	.A1  (read_prt_bin[1]  ),
	.A2  (read_prt_bin[2]  ),
	.A3  (read_prt_bin[3]  ),
	.A4  (read_prt_bin[4]  ),
	.A5  (read_prt_bin[5]  ),
	.A6  (read_prt_bin[6]  ),
	.A7  (read_prt_bin[7]  ),
	.B0  (write_prt_bin[0]  ),
	.B1  (write_prt_bin[1]  ),
	.B2  (write_prt_bin[2]  ),
	.B3  (write_prt_bin[3]  ),
	.B4  (write_prt_bin[4]  ),
	.B5  (write_prt_bin[5]  ),
	.B6  (write_prt_bin[6]  ),
	.B7  (write_prt_bin[7]  ),
	.WEB (~PUSH_OK ),
	.CKA (CLK75M ),
	.CKB (CLK40M ),
	.CSAN(1'b0),
	.CSBN(1'b0)
);



`else  


SJ180_256X16X1CM4 DPRAM_inst (
	.DOA0 (DOA[0] ),
	.DOA1 (DOA[1]  ),
	.DOA2 (DOA[2]  ),
	.DOA3 (DOA[3]  ),
	.DOA4 (DOA[4]  ),
	.DOA5 (DOA[5]  ),
	.DOA6 (DOA[6]  ),
	.DOA7 (DOA[7]  ),
	.DOA8 (DOA[8]  ),
	.DOA9 (DOA[9]  ),
	.DOA10(DOA[10] ),
	.DOA11(DOA[11] ),
	.DOA12(DOA[12] ),
	.DOA13(DOA[13] ),
	.DOA14(DOA[14] ),
	.DOA15(DOA[15] ),
	.DOB0 (DOB[0] ),
	.DOB1 (DOB[1] ),
	.DOB2 (DOB[2] ),
	.DOB3 (DOB[3] ),
	.DOB4 (DOB[4] ),
	.DOB5 (DOB[5] ),
	.DOB6 (DOB[6] ),
	.DOB7 (DOB[7] ),
	.DOB8 (DOB[8] ),
	.DOB9 (DOB[9] ),
	.DOB10(DOB[10]),
	.DOB11(DOB[11]),
	.DOB12(DOB[12]),
	.DOB13(DOB[13]),
	.DOB14(DOB[14]),
	.DOB15(DOB[15]),
	.DIA0 (DATAIN[0] ),
	.DIA1 (DATAIN[1] ),
	.DIA2 (DATAIN[2] ),
	.DIA3 (DATAIN[3] ),
	.DIA4 (DATAIN[4] ),
	.DIA5 (DATAIN[5] ),
	.DIA6 (DATAIN[6] ),
	.DIA7 (DATAIN[7] ),
	.DIA8 (DATAIN[8] ),
	.DIA9 (DATAIN[9] ),
	.DIA10(DATAIN[10]),
	.DIA11(DATAIN[11]),
	.DIA12(DATAIN[12]),
	.DIA13(DATAIN[13]),
	.DIA14(DATAIN[14]),
	.DIA15(DATAIN[15]),
	.DIB0 (DIB[0] ),
	.DIB1 (DIB[1] ),
	.DIB2 (DIB[2] ),
	.DIB3 (DIB[3] ),
	.DIB4 (DIB[4] ),
	.DIB5 (DIB[5] ),
	.DIB6 (DIB[6] ),
	.DIB7 (DIB[7] ),
	.DIB8 (DIB[8] ),
	.DIB9 (DIB[9] ),
	.DIB10(DIB[10]),
	.DIB11(DIB[11]),
	.DIB12(DIB[12]),
	.DIB13(DIB[13]),
	.DIB14(DIB[14]),
	.DIB15(DIB[15]),
	.A0   (write_prt_bin[0]   ),
	.A1   (write_prt_bin[1]   ),
	.A2   (write_prt_bin[2]   ),
	.A3   (write_prt_bin[3]   ),
	.A4   (write_prt_bin[4]   ),
	.A5   (write_prt_bin[5]   ),
	.A6   (write_prt_bin[6]   ),
	.A7   (write_prt_bin[7]   ),
	.B0   (read_prt_bin[0]   ),
	.B1   (read_prt_bin[1]   ),
	.B2   (read_prt_bin[2]   ),
	.B3   (read_prt_bin[3]   ),
	.B4   (read_prt_bin[4]   ),
	.B5   (read_prt_bin[5]   ),
	.B6   (read_prt_bin[6]   ),
	.B7   (read_prt_bin[7]   ),
	.OEA  (1'b0  ),
	.OEB  (1'b1  ),
	.WEAN (1'b0 ),
	.WEBN (1'b1 ),
	.CKA  (CLK40M  ),
	.CKB  (CLK75M  ),
	.CSA  (PUSH_OK  ),
	`ifdef NEXT_CYCLE_READ
	.CSB (POP_OK )		// next cycle read
	`else 
	.CSB (1'b1)	//simply consume the data.
	`endif 
);


`endif

/*
`ifdef NEXT_CYCLE_READ
	assign DATAOUT = DOB;
`else 
	assign DATAOUT = POP? DOB: 16'd0;
`endif
*/

assign DATAOUT = DOB;

endmodule




