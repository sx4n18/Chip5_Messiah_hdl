/*******************************************************************************

             Synchronous 2 Port Register File Compiler 

                   UMC 0.18um Generic Logic Process 
   __________________________________________________________________________


       (C) Copyright 2002-2009 Faraday Technology Corp. All Rights Reserved.

     This source code is an unpublished work belongs to Faraday Technology
     Corp.  It is considered a trade secret and is not to be divulged or
     used by parties who have not received written authorization from
     Faraday Technology Corp.

     Faraday's home page can be found at:
     http://www.faraday-tech.com/
    
________________________________________________________________________________

      Module Name       :  SZ180_256X16X1CM4  
      Word              :  256                
      Bit               :  16                 
      Byte              :  1                  
      Mux               :  4                  
      Power Ring Type   :  port               
      Power Ring Width  :  2 (um)             
      Output Loading    :  0.01 (pf)          
      Input Data Slew   :  0.5 (ns)           
      Input Clock Slew  :  0.5 (ns)           

________________________________________________________________________________

      Library          : FSA0A_C
      Memaker          : 200901.2.1
      Date             : 2026/03/03 17:53:13

________________________________________________________________________________


   Notice on usage: Fixed delay or timing data are given in this model.
                    It supports SDF back-annotation, please generate SDF file
                    by EDA tools to get the accurate timing.

 |-----------------------------------------------------------------------------|

   Warning : If customer's design viloate the set-up time or hold time criteria 
   of synchronous SRAM, it's possible to hit the meta-stable point of 
   latch circuit in the decoder and cause the data loss in the memory bitcell.
   So please follow the memory IP's spec to design your product.

 |-----------------------------------------------------------------------------|

                Library          : FSA0A_C
                Memaker          : 200901.2.1
                Date             : 2026/03/03 17:53:13

 *******************************************************************************/

`resetall
`timescale 10ps/1ps


module SZ180_256X16X1CM4 (A0,A1,A2,A3,A4,A5,A6,A7,B0,B1,B2,B3,B4,B5,B6,B7,
                          DO0,DO1,DO2,DO3,DO4,DO5,DO6,DO7,DO8,DO9,DO10,
                          DO11,DO12,DO13,DO14,DO15,DI0,DI1,DI2,DI3,
                          DI4,DI5,DI6,DI7,DI8,DI9,DI10,DI11,DI12,DI13,
                          DI14,DI15,WEB,CKA,CKB,CSAN,CSBN);

  `define    TRUE                 (1'b1)              
  `define    FALSE                (1'b0)              

  parameter  SYN_CS               = `TRUE;            
  parameter  NO_SER_TOH           = `TRUE;            
  parameter  AddressSize          = 8;                
  parameter  Bits                 = 16;               
  parameter  Words                = 256;              
  parameter  Bytes                = 1;                
  parameter  AspectRatio          = 4;                
  parameter  Tr2w                 = (110:162:279);    
  parameter  Tw2r                 = (110:162:279);    
  parameter  TOH                  = (37:54:93);       

  output     DO0,DO1,DO2,DO3,DO4,DO5,DO6,DO7,DO8,
             DO9,DO10,DO11,DO12,DO13,DO14,DO15;
  input      DI0,DI1,DI2,DI3,DI4,DI5,DI6,DI7,DI8,
             DI9,DI10,DI11,DI12,DI13,DI14,DI15;
  input      A0,A1,A2,A3,A4,A5,A6,A7;
  input      B0,B1,B2,B3,B4,B5,B6,B7;
  input      WEB;                                     
  input      CKA;                                     
  input      CKB;                                     
  input      CSAN;                                    
  input      CSBN;                                    

`protect
  reg        [Bits-1:0]           Memory [Words-1:0];           

  wire       [Bytes*Bits-1:0]     DO_;                
  wire       [AddressSize-1:0]    A_;                 
  wire       [Bits-1:0]           DI_;                
  wire                            WEB_;               
  wire       [AddressSize-1:0]    B_;                 
  wire                            CKA_;               
  wire                            CKB_;               
  wire                            CSA_;               
  wire                            CSB_;               



  wire                            con_A;              
  wire                            con_DI;             
  wire                            con_B;              
  wire                            con_CKA;            
  wire                            con_CKB;            
  wire                            con_WEB;            

  reg        [AddressSize-1:0]    Latch_A;            
  reg        [Bits-1:0]           Latch_DI;           
  reg                             Latch_WEB;          
  reg        [AddressSize-1:0]    Latch_B;            
  reg                             Latch_CSA;          
  reg                             Latch_CSB;          
  reg        [AddressSize-1:0]    LastCycleRAddress;  
  reg        [AddressSize-1:0]    LastCycleWAddress;  

  reg        [AddressSize-1:0]    A_i;                
  reg        [Bits-1:0]           DI_i;               
  reg                             WEB_i;              
  reg        [AddressSize-1:0]    B_i;                
  reg                             CSA_i;              
  reg                             CSB_i;              

  reg                             n_flag_A0;          
  reg                             n_flag_A1;          
  reg                             n_flag_A2;          
  reg                             n_flag_A3;          
  reg                             n_flag_A4;          
  reg                             n_flag_A5;          
  reg                             n_flag_A6;          
  reg                             n_flag_A7;          
  reg                             n_flag_B0;          
  reg                             n_flag_B1;          
  reg                             n_flag_B2;          
  reg                             n_flag_B3;          
  reg                             n_flag_B4;          
  reg                             n_flag_B5;          
  reg                             n_flag_B6;          
  reg                             n_flag_B7;          
  reg                             n_flag_DI0;         
  reg                             n_flag_DI1;         
  reg                             n_flag_DI2;         
  reg                             n_flag_DI3;         
  reg                             n_flag_DI4;         
  reg                             n_flag_DI5;         
  reg                             n_flag_DI6;         
  reg                             n_flag_DI7;         
  reg                             n_flag_DI8;         
  reg                             n_flag_DI9;         
  reg                             n_flag_DI10;        
  reg                             n_flag_DI11;        
  reg                             n_flag_DI12;        
  reg                             n_flag_DI13;        
  reg                             n_flag_DI14;        
  reg                             n_flag_DI15;        
  reg                             n_flag_WEB;         
  reg                             n_flag_CSA;         
  reg                             n_flag_CSB;         
  reg                             n_flag_CKA_PER;     
  reg                             n_flag_CKA_MINH;    
  reg                             n_flag_CKA_MINL;    
  reg                             n_flag_CKB_PER;     
  reg                             n_flag_CKB_MINH;    
  reg                             n_flag_CKB_MINL;    
  reg                             LAST_n_flag_WEB;    
  reg                             LAST_n_flag_CSA;    
  reg                             LAST_n_flag_CSB;    
  reg                             LAST_n_flag_CKA_PER;
  reg                             LAST_n_flag_CKA_MINH;
  reg                             LAST_n_flag_CKA_MINL;
  reg                             LAST_n_flag_CKB_PER;
  reg                             LAST_n_flag_CKB_MINH;
  reg                             LAST_n_flag_CKB_MINL;
  reg        [AddressSize-1:0]    NOT_BUS_B;          
  reg        [AddressSize-1:0]    LAST_NOT_BUS_B;     
  reg        [AddressSize-1:0]    NOT_BUS_A;          
  reg        [AddressSize-1:0]    LAST_NOT_BUS_A;     
  reg        [Bits-1:0]           NOT_BUS_DI;         
  reg        [Bits-1:0]           LAST_NOT_BUS_DI;    

  reg        [AddressSize-1:0]    last_A;             
  reg        [AddressSize-1:0]    latch_last_A;       

  reg        [Bits-1:0]           DO_i;               

  reg                             LastClkAEdge;       
  reg                             LastClkBEdge;       

  reg                             flag_A_x;           
  reg                             flag_B_x;           
  reg                             flag_CSA_x;         
  reg                             flag_CSB_x;         
  reg                             NODELAY;            
  reg        [Bits-1:0]           DO_tmp;             
  event                           EventTOHDO;         
  event                           EventNegCS;         

  time                            Last_tc_ClkA_PosEdge;
  time                            Last_tc_ClkB_PosEdge_WEB;

  assign     DO_                  = {DO_i};
  assign     con_A                = CSA_;
  assign     con_B                = CSB_ & (!WEB_);
  assign     con_DI               = CSB_ & (!WEB_);
  assign     con_WEB              = CSB_;
  assign     con_CKA              = CSA_;
  assign     con_CKB              = CSB_;

  buf        ido0            (DO0, DO_[0]);                
  buf        ido1            (DO1, DO_[1]);                
  buf        ido2            (DO2, DO_[2]);                
  buf        ido3            (DO3, DO_[3]);                
  buf        ido4            (DO4, DO_[4]);                
  buf        ido5            (DO5, DO_[5]);                
  buf        ido6            (DO6, DO_[6]);                
  buf        ido7            (DO7, DO_[7]);                
  buf        ido8            (DO8, DO_[8]);                
  buf        ido9            (DO9, DO_[9]);                
  buf        ido10           (DO10, DO_[10]);              
  buf        ido11           (DO11, DO_[11]);              
  buf        ido12           (DO12, DO_[12]);              
  buf        ido13           (DO13, DO_[13]);              
  buf        ido14           (DO14, DO_[14]);              
  buf        ido15           (DO15, DO_[15]);              
  buf        ia0             (A_[0], A0);                  
  buf        ia1             (A_[1], A1);                  
  buf        ia2             (A_[2], A2);                  
  buf        ia3             (A_[3], A3);                  
  buf        ia4             (A_[4], A4);                  
  buf        ia5             (A_[5], A5);                  
  buf        ia6             (A_[6], A6);                  
  buf        ia7             (A_[7], A7);                  
  buf        ib0             (B_[0], B0);                  
  buf        ib1             (B_[1], B1);                  
  buf        ib2             (B_[2], B2);                  
  buf        ib3             (B_[3], B3);                  
  buf        ib4             (B_[4], B4);                  
  buf        ib5             (B_[5], B5);                  
  buf        ib6             (B_[6], B6);                  
  buf        ib7             (B_[7], B7);                  
  buf        idi_0           (DI_[0], DI0);                
  buf        idi_1           (DI_[1], DI1);                
  buf        idi_2           (DI_[2], DI2);                
  buf        idi_3           (DI_[3], DI3);                
  buf        idi_4           (DI_[4], DI4);                
  buf        idi_5           (DI_[5], DI5);                
  buf        idi_6           (DI_[6], DI6);                
  buf        idi_7           (DI_[7], DI7);                
  buf        idi_8           (DI_[8], DI8);                
  buf        idi_9           (DI_[9], DI9);                
  buf        idi_10          (DI_[10], DI10);              
  buf        idi_11          (DI_[11], DI11);              
  buf        idi_12          (DI_[12], DI12);              
  buf        idi_13          (DI_[13], DI13);              
  buf        idi_14          (DI_[14], DI14);              
  buf        idi_15          (DI_[15], DI15);              
  buf        icka            (CKA_, CKA);                  
  buf        ickb            (CKB_, CKB);                  
  not        icsa            (CSA_, CSAN);                 
  not        icsb            (CSB_, CSBN);                 
  buf        iweb0           (WEB_, WEB);                  

  initial begin
    $timeformat (-12, 0, " ps", 20);
    flag_A_x = `FALSE;
    flag_B_x = `FALSE;
    NODELAY = 1'b0;
  end

  always @(negedge CSA_) begin
    if (SYN_CS == `FALSE) begin
       ->EventNegCS;
    end
  end
  always @(posedge CSA_) begin
    if (SYN_CS == `FALSE) begin
       disable NegCS;
    end
  end


  always @(CKA_) begin
    casez ({LastClkAEdge,CKA_})
      2'b01:
         begin
           last_A = latch_last_A;
           CSA_monitor;
           pre_latch_rdata;
           read_memory_function;
           if (CSA_==1'b1) Last_tc_ClkA_PosEdge = $time;
           latch_last_A = A_;
         end
      2'b?x:
         begin
           ErrorMessage(0);
           #0 disable TOHDO;
           NODELAY = 1'b1;
           DO_i = {Bits{1'bX}};
         end
    endcase
    LastClkAEdge = CKA_;
  end


  always @(CKB_) begin
    casez ({LastClkBEdge,CKB_})
      2'b01:
         begin
           CSB_monitor;
           pre_latch_wdata;
           write_memory_function;
           if ((WEB_==1'b0)&&(CSB_==1'b1)) Last_tc_ClkB_PosEdge_WEB = $time;
         end
      2'b?x:
         begin
           ErrorMessage(0);
           if ((WEB_ !== 1'b1)&&(CSB_ !== 1'b0)) begin
              all_core_x(9999,0);
           end
         end
    endcase
    LastClkBEdge = CKB_;
  end

  always @(
           n_flag_A0 or
           n_flag_A1 or
           n_flag_A2 or
           n_flag_A3 or
           n_flag_A4 or
           n_flag_A5 or
           n_flag_A6 or
           n_flag_A7 or
           n_flag_B0 or
           n_flag_B1 or
           n_flag_B2 or
           n_flag_B3 or
           n_flag_B4 or
           n_flag_B5 or
           n_flag_B6 or
           n_flag_B7 or
           n_flag_DI0 or
           n_flag_DI1 or
           n_flag_DI2 or
           n_flag_DI3 or
           n_flag_DI4 or
           n_flag_DI5 or
           n_flag_DI6 or
           n_flag_DI7 or
           n_flag_DI8 or
           n_flag_DI9 or
           n_flag_DI10 or
           n_flag_DI11 or
           n_flag_DI12 or
           n_flag_DI13 or
           n_flag_DI14 or
           n_flag_DI15 or
           n_flag_WEB or
           n_flag_CSA or
           n_flag_CKA_PER or
           n_flag_CKA_MINH or
           n_flag_CKA_MINL or
           n_flag_CSB or
           n_flag_CKB_PER or
           n_flag_CKB_MINH or
           n_flag_CKB_MINL
          )
     begin
       timingcheck_violation;
     end


  always @(EventTOHDO) 
    begin:TOHDO 
      #TOH 
      NODELAY <= 1'b0; 
      DO_i              =  {Bits{1'bX}}; 
      DO_i              <= DO_tmp; 
  end 

  always @(EventNegCS) 
    begin:NegCS
      #TOH 
      disable TOHDO;
      NODELAY = 1'b0; 
      DO_i              =  {Bits{1'bX}}; 
  end 

  task timingcheck_violation;
    integer i;
    begin
      // READ PORT
      if ((n_flag_CKA_PER  !== LAST_n_flag_CKA_PER)  ||
          (n_flag_CKA_MINH !== LAST_n_flag_CKA_MINH) ||
          (n_flag_CKA_MINL !== LAST_n_flag_CKA_MINL)) begin
          if (CSA_ !== 1'b0) begin
           #0 disable TOHDO;
           NODELAY = 1'b1;
           DO_i = {Bits{1'bX}};
          end
      end
      else begin
          NOT_BUS_A  = {
                         n_flag_A7,
                         n_flag_A6,
                         n_flag_A5,
                         n_flag_A4,
                         n_flag_A3,
                         n_flag_A2,
                         n_flag_A1,
                         n_flag_A0};

          for (i=0; i<AddressSize; i=i+1) begin
             Latch_A[i] = (NOT_BUS_A[i] !== LAST_NOT_BUS_A[i]) ? 1'bx : Latch_A[i];
          end
          Latch_CSA  =  (n_flag_CSA  !== LAST_n_flag_CSA)  ? 1'bx : Latch_CSA;
          read_memory_function;
      end

      // WRITE PORT
      if ((n_flag_CKB_PER  !== LAST_n_flag_CKB_PER)  ||
          (n_flag_CKB_MINH !== LAST_n_flag_CKB_MINH) ||
          (n_flag_CKB_MINL !== LAST_n_flag_CKB_MINL)) begin
          if (CSB_ !== 1'b0) begin
             if (WEB_ !== 1'b1) begin
                all_core_x(9999,0);
             end
          end
      end
      else begin
          NOT_BUS_B  = {
                         n_flag_B7,
                         n_flag_B6,
                         n_flag_B5,
                         n_flag_B4,
                         n_flag_B3,
                         n_flag_B2,
                         n_flag_B1,
                         n_flag_B0};

          NOT_BUS_DI  = {
                         n_flag_DI15,
                         n_flag_DI14,
                         n_flag_DI13,
                         n_flag_DI12,
                         n_flag_DI11,
                         n_flag_DI10,
                         n_flag_DI9,
                         n_flag_DI8,
                         n_flag_DI7,
                         n_flag_DI6,
                         n_flag_DI5,
                         n_flag_DI4,
                         n_flag_DI3,
                         n_flag_DI2,
                         n_flag_DI1,
                         n_flag_DI0};

          for (i=0; i<AddressSize; i=i+1) begin
             Latch_B[i] = (NOT_BUS_B[i] !== LAST_NOT_BUS_B[i]) ? 1'bx : Latch_B[i];
          end
          for (i=0; i<Bits; i=i+1) begin
             Latch_DI[i] = (NOT_BUS_DI[i] !== LAST_NOT_BUS_DI[i]) ? 1'bx : Latch_DI[i];
          end
          Latch_CSB  =  (n_flag_CSB  !== LAST_n_flag_CSB)  ? 1'bx : Latch_CSB;
          Latch_WEB = (n_flag_WEB !== LAST_n_flag_WEB)  ? 1'bx : Latch_WEB;
          write_memory_function;
      end

      LAST_NOT_BUS_A                 = NOT_BUS_A;
      LAST_NOT_BUS_DI                = NOT_BUS_DI;
      LAST_n_flag_WEB                = n_flag_WEB;
      LAST_NOT_BUS_B                 = NOT_BUS_B;
      LAST_n_flag_CSA                = n_flag_CSA;
      LAST_n_flag_CSB                = n_flag_CSB;
      LAST_n_flag_CKA_PER            = n_flag_CKA_PER;
      LAST_n_flag_CKA_MINH           = n_flag_CKA_MINH;
      LAST_n_flag_CKA_MINL           = n_flag_CKA_MINL;
      LAST_n_flag_CKB_PER            = n_flag_CKB_PER;
      LAST_n_flag_CKB_MINH           = n_flag_CKB_MINH;
      LAST_n_flag_CKB_MINL           = n_flag_CKB_MINL;
    end
  endtask // end timingcheck_violation;

  task pre_latch_rdata;
    begin
      Latch_A                        = A_;
      Latch_CSA                      = CSA_;
    end
  endtask //end pre_latch_rdata

  task pre_latch_wdata;
    begin
      Latch_B                        = B_;
      Latch_DI                       = DI_;
      Latch_CSB                      = CSB_;
      Latch_WEB                      = WEB_;
    end
  endtask //end pre_latch_wdata

  task read_memory_function;
    begin
      A_i                            = Latch_A;
      CSA_i                          = Latch_CSA;

      if (CSA_ == 1'b1) A_monitor;

      casez(CSA_i)
        1'b1: begin
           if (AddressRangeCheck(A_i)) begin
             if ((A_i == LastCycleWAddress)&&($time-Last_tc_ClkB_PosEdge_WEB<Tw2r)) begin
                ErrorMessage(1);
                #0 disable TOHDO;
                NODELAY = 1'b1;
                DO_i = {Bits{1'bX}};
             end
             else begin
               if (NO_SER_TOH == `TRUE) begin
                 if (A_i !== last_A) begin
                    NODELAY = 1'b1;
                    DO_tmp = Memory[A_i];
                    ->EventTOHDO;
                 end else begin
                    NODELAY = 1'b0;
                    DO_tmp  = Memory[A_i];
                    DO_i    = DO_tmp;
                 end
               end else begin
                 NODELAY = 1'b1;
                 DO_tmp = Memory[A_i];
                 ->EventTOHDO;
               end
             end
           end
           else begin
                #0 disable TOHDO;
                NODELAY = 1'b1;
                DO_i = {Bits{1'bX}};
           end
           LastCycleRAddress = A_i;
        end
        1'bx: begin
                #0 disable TOHDO;
                NODELAY = 1'b1;
                DO_i = {Bits{1'bX}};
        end
      endcase
  end
  endtask //read_memory_function;


  task write_memory_function;
    begin
      B_i                            = Latch_B;
      DI_i                           = Latch_DI;
      CSB_i                          = Latch_CSB;
      WEB_i                          = Latch_WEB;

      if (CSB_ == 1'b1) B_monitor;

      casez({WEB_i,CSB_i})
        2'b01: begin
           if (AddressRangeCheck(B_i)) begin
             if ((B_i == LastCycleRAddress)&&($time-Last_tc_ClkA_PosEdge<Tr2w)) begin
                ErrorMessage(1);
                #0 disable TOHDO;
                NODELAY = 1'b1;
                DO_i = {Bits{1'bX}};
             end
             Memory[B_i] = DI_i;
           end else begin
                all_core_x(9999,0);
           end
           LastCycleWAddress = B_i;
        end
        2'b0x,
        2'bx1,
        2'bxx: begin
           if (AddressRangeCheck(B_i)) begin
                Memory[B_i] = {Bits{1'bX}};
           end else begin
                all_core_x(9999,0);
           end
        end
      endcase
  end
  endtask //write_memory_function;

  task all_core_x;
     input byte_num;
     input do_x;

     integer byte_num;
     integer do_x;
     integer LoopCount_Address;
     begin
       if (do_x == 1) begin
          #0 disable TOHDO;
          NODELAY = 1'b1;
          DO_i = {Bits{1'bX}};
       end
       LoopCount_Address=Words-1;
       while(LoopCount_Address >=0) begin
         Memory[LoopCount_Address]={Bits{1'bX}};
         LoopCount_Address=LoopCount_Address-1;
      end
    end
  endtask //end all_core_x;

  task A_monitor;
     begin
       if (^(A_) !== 1'bX) begin
          flag_A_x = `FALSE;
       end
       else begin
          if (flag_A_x == `FALSE) begin
              flag_A_x = `TRUE;
              ErrorMessage(2);
          end
       end
     end
  endtask //end A_monitor;

  task B_monitor;
     begin
       if (^(B_) !== 1'bX) begin
          flag_B_x = `FALSE;
       end
       else begin
          if (flag_B_x == `FALSE) begin
              flag_B_x = `TRUE;
              ErrorMessage(2);
          end
       end
     end
  endtask //end B_monitor;

  task CSA_monitor;
     begin
       if (^(CSA_) !== 1'bX) begin
          flag_CSA_x = `FALSE;
       end
       else begin
          if (flag_CSA_x == `FALSE) begin
              flag_CSA_x = `TRUE;
              ErrorMessage(3);
          end
       end
     end
  endtask //end CSA_monitor;

  task CSB_monitor;
     begin
       if (^(CSB_) !== 1'bX) begin
          flag_CSB_x = `FALSE;
       end
       else begin
          if (flag_CSB_x == `FALSE) begin
              flag_CSB_x = `TRUE;
              ErrorMessage(3);
          end
       end
     end
  endtask //end CSB_monitor;

  task ErrorMessage;
     input error_type;
     integer error_type;

     begin
       case (error_type)
         0: $display("** MEM_Error: Abnormal transition occurred (%t) in Clock of %m",$time);
         1: $display("** MEM_Warning: Read and Write the same Address, DO is unknown (%t) in clock of %m",$time);
         2: $display("** MEM_Error: Unknown value occurred (%t) in Address of %m",$time);
         3: $display("** MEM_Error: Unknown value occurred (%t) in ChipSelect of %m",$time);
         4: $display("** MEM_Error: Port A and B write the same Address, core is unknown (%t) in clock of %m",$time);
         5: $display("** MEM_Error: Clear all memory core to unknown (%t) in clock of %m",$time);
       endcase
     end
  endtask

  function AddressRangeCheck;
      input  [AddressSize-1:0] AddressItem;
      reg    UnaryResult;
      begin
        UnaryResult = ^AddressItem;
        if(UnaryResult!==1'bX) begin
           if (AddressItem >= Words) begin
              $display("** MEM_Error: Out of range occurred (%t) in Address of %m",$time);
              AddressRangeCheck = `FALSE;
           end else begin
              AddressRangeCheck = `TRUE;
           end
        end
        else begin
           AddressRangeCheck = `FALSE;
        end
      end
  endfunction //end AddressRangeCheck;

   specify
      specparam TAA  = (71:109:197);
      specparam TRC  = (110:162:279);
      specparam THPW = (37:54:93);
      specparam TLPW = (37:54:93);
      specparam TAS  = (43:58:97);
      specparam TAH  = (10:10:10);
      specparam TWS  = (23:29:43);
      specparam TWH  = (10:14:37);
      specparam TDS  = (47:62:95);
      specparam TDH  = (10:10:10);
      specparam TCSS = (35:48:79);
      specparam TCSH = (10:16:28);


      $setuphold ( posedge CKA &&& con_A,         posedge A0, TAS,     TAH,     n_flag_A0      );
      $setuphold ( posedge CKA &&& con_A,         negedge A0, TAS,     TAH,     n_flag_A0      );
      $setuphold ( posedge CKA &&& con_A,         posedge A1, TAS,     TAH,     n_flag_A1      );
      $setuphold ( posedge CKA &&& con_A,         negedge A1, TAS,     TAH,     n_flag_A1      );
      $setuphold ( posedge CKA &&& con_A,         posedge A2, TAS,     TAH,     n_flag_A2      );
      $setuphold ( posedge CKA &&& con_A,         negedge A2, TAS,     TAH,     n_flag_A2      );
      $setuphold ( posedge CKA &&& con_A,         posedge A3, TAS,     TAH,     n_flag_A3      );
      $setuphold ( posedge CKA &&& con_A,         negedge A3, TAS,     TAH,     n_flag_A3      );
      $setuphold ( posedge CKA &&& con_A,         posedge A4, TAS,     TAH,     n_flag_A4      );
      $setuphold ( posedge CKA &&& con_A,         negedge A4, TAS,     TAH,     n_flag_A4      );
      $setuphold ( posedge CKA &&& con_A,         posedge A5, TAS,     TAH,     n_flag_A5      );
      $setuphold ( posedge CKA &&& con_A,         negedge A5, TAS,     TAH,     n_flag_A5      );
      $setuphold ( posedge CKA &&& con_A,         posedge A6, TAS,     TAH,     n_flag_A6      );
      $setuphold ( posedge CKA &&& con_A,         negedge A6, TAS,     TAH,     n_flag_A6      );
      $setuphold ( posedge CKA &&& con_A,         posedge A7, TAS,     TAH,     n_flag_A7      );
      $setuphold ( posedge CKA &&& con_A,         negedge A7, TAS,     TAH,     n_flag_A7      );
      $setuphold ( posedge CKB &&& con_B,         posedge B0, TAS,     TAH,     n_flag_B0      );
      $setuphold ( posedge CKB &&& con_B,         negedge B0, TAS,     TAH,     n_flag_B0      );
      $setuphold ( posedge CKB &&& con_B,         posedge B1, TAS,     TAH,     n_flag_B1      );
      $setuphold ( posedge CKB &&& con_B,         negedge B1, TAS,     TAH,     n_flag_B1      );
      $setuphold ( posedge CKB &&& con_B,         posedge B2, TAS,     TAH,     n_flag_B2      );
      $setuphold ( posedge CKB &&& con_B,         negedge B2, TAS,     TAH,     n_flag_B2      );
      $setuphold ( posedge CKB &&& con_B,         posedge B3, TAS,     TAH,     n_flag_B3      );
      $setuphold ( posedge CKB &&& con_B,         negedge B3, TAS,     TAH,     n_flag_B3      );
      $setuphold ( posedge CKB &&& con_B,         posedge B4, TAS,     TAH,     n_flag_B4      );
      $setuphold ( posedge CKB &&& con_B,         negedge B4, TAS,     TAH,     n_flag_B4      );
      $setuphold ( posedge CKB &&& con_B,         posedge B5, TAS,     TAH,     n_flag_B5      );
      $setuphold ( posedge CKB &&& con_B,         negedge B5, TAS,     TAH,     n_flag_B5      );
      $setuphold ( posedge CKB &&& con_B,         posedge B6, TAS,     TAH,     n_flag_B6      );
      $setuphold ( posedge CKB &&& con_B,         negedge B6, TAS,     TAH,     n_flag_B6      );
      $setuphold ( posedge CKB &&& con_B,         posedge B7, TAS,     TAH,     n_flag_B7      );
      $setuphold ( posedge CKB &&& con_B,         negedge B7, TAS,     TAH,     n_flag_B7      );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI0, TDS,     TDH,     n_flag_DI0     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI0, TDS,     TDH,     n_flag_DI0     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI1, TDS,     TDH,     n_flag_DI1     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI1, TDS,     TDH,     n_flag_DI1     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI2, TDS,     TDH,     n_flag_DI2     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI2, TDS,     TDH,     n_flag_DI2     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI3, TDS,     TDH,     n_flag_DI3     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI3, TDS,     TDH,     n_flag_DI3     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI4, TDS,     TDH,     n_flag_DI4     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI4, TDS,     TDH,     n_flag_DI4     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI5, TDS,     TDH,     n_flag_DI5     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI5, TDS,     TDH,     n_flag_DI5     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI6, TDS,     TDH,     n_flag_DI6     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI6, TDS,     TDH,     n_flag_DI6     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI7, TDS,     TDH,     n_flag_DI7     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI7, TDS,     TDH,     n_flag_DI7     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI8, TDS,     TDH,     n_flag_DI8     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI8, TDS,     TDH,     n_flag_DI8     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI9, TDS,     TDH,     n_flag_DI9     );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI9, TDS,     TDH,     n_flag_DI9     );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI10, TDS,     TDH,     n_flag_DI10    );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI10, TDS,     TDH,     n_flag_DI10    );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI11, TDS,     TDH,     n_flag_DI11    );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI11, TDS,     TDH,     n_flag_DI11    );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI12, TDS,     TDH,     n_flag_DI12    );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI12, TDS,     TDH,     n_flag_DI12    );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI13, TDS,     TDH,     n_flag_DI13    );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI13, TDS,     TDH,     n_flag_DI13    );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI14, TDS,     TDH,     n_flag_DI14    );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI14, TDS,     TDH,     n_flag_DI14    );
      $setuphold ( posedge CKB &&& con_DI,        posedge DI15, TDS,     TDH,     n_flag_DI15    );
      $setuphold ( posedge CKB &&& con_DI,        negedge DI15, TDS,     TDH,     n_flag_DI15    );
      $setuphold ( posedge CKB &&& con_WEB,       posedge WEB, TWS,     TWH,     n_flag_WEB     );
      $setuphold ( posedge CKB &&& con_WEB,       negedge WEB, TWS,     TWH,     n_flag_WEB     );
      $setuphold ( posedge CKA,                   posedge CSAN, TCSS,    TCSH,    n_flag_CSA     );
      $setuphold ( posedge CKA,                   negedge CSAN, TCSS,    TCSH,    n_flag_CSA     );
      $setuphold ( posedge CKB,                   posedge CSBN, TCSS,    TCSH,    n_flag_CSB     );
      $setuphold ( posedge CKB,                   negedge CSBN, TCSS,    TCSH,    n_flag_CSB     );
      $period    ( posedge CKA &&& con_CKA,       TRC,                       n_flag_CKA_PER );
      $width     ( posedge CKA &&& con_CKA,       THPW,    0,                n_flag_CKA_MINH);
      $width     ( negedge CKA &&& con_CKA,       TLPW,    0,                n_flag_CKA_MINL);
      $period    ( posedge CKB &&& con_CKB,       TRC,                       n_flag_CKB_PER );
      $width     ( posedge CKB &&& con_CKB,       THPW,    0,                n_flag_CKB_MINH);
      $width     ( negedge CKB &&& con_CKB,       TLPW,    0,                n_flag_CKB_MINL);

      if (NODELAY == 0)  (posedge CKA => (DO0 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO1 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO2 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO3 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO4 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO5 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO6 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO7 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO8 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO9 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO10 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO11 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO12 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO13 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO14 :1'bx)) = TAA  ;
      if (NODELAY == 0)  (posedge CKA => (DO15 :1'bx)) = TAA  ;



   endspecify

`endprotect
endmodule
