// The simplest behaviour verilog of the dualport ram imagined.

module FSA0A_C_DPSRAM_PARAM #(parameter int FIFO_DEPTH = 512)(
    input  [$clog2(FIFO_DEPTH)-1:0]  A,
    input  [$clog2(FIFO_DEPTH)-1:0]  B,
    input  [15:0] DIA,
    input  [15:0] DIB,
    input         OEA,
    input         OEB,
    input         CKA,
    input         CKB,
    input         CSA,
    input         CSB,
    input  [1:0]  WEAN,   // active low
    input  [1:0]  WEBN,
    output [15:0] DOA,
    output [15:0] DOB
);

    // FIFO_DEPTH x 16 memory
    reg [15:0] mem [0:FIFO_DEPTH-1];

    // Internal read data registers
    reg [15:0] doa_reg;
    reg [15:0] dob_reg;

    //--------------------------------------------------
    // PORT A
    //--------------------------------------------------
    always @(posedge CKA) begin
        if (CSA) begin

            // Byte write enables (active low)
            if (!WEAN[0])
                mem[A][7:0]  <= DIA[7:0];

            if (!WEAN[1])
                mem[A][15:8] <= DIA[15:8];

            // Synchronous read
            doa_reg <= mem[A];
        end
    end

    // Tri-state output
    assign DOA = (CSA && OEA) ? doa_reg : 16'hZZZZ;


    //--------------------------------------------------
    // PORT B
    //--------------------------------------------------
    always @(posedge CKB) begin
        if (CSB) begin

            if (!WEBN[0])
                mem[B][7:0]  <= DIB[7:0];

            if (!WEBN[1])
                mem[B][15:8] <= DIB[15:8];

            dob_reg <= mem[B];
        end
    end

    assign DOB = (CSB && OEB) ? dob_reg : 16'hZZZZ;

endmodule