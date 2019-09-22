/*******************************************************************************
 #                        NORTH CAROLINA STATE UNIVERSITY
 #
 #                              AnyCore Project
 # 
 # AnyCore written by NCSU authors Rangeen Basu Roy Chowdhury and Eric Rotenberg.
 # 
 # AnyCore is based on FabScalar which was written by NCSU authors Niket K. 
 # Choudhary, Brandon H. Dwiel, and Eric Rotenberg.
 # 
 # AnyCore also includes contributions by NCSU authors Elliott Forbes, Jayneel 
 # Gandhi, Anil Kumar Kannepalli, Sungkwan Ku, Hiran Mayukh, Hashem Hashemi 
 # Najaf-abadi, Sandeep Navada, Tanmay Shah, Ashlesha Shastri, Vinesh Srinivasan, 
 # and Salil Wadhavkar.
 # 
 # AnyCore is distributed under the BSD license.
 *******************************************************************************/

`timescale 1ns/100ps

module LDQ_CAM #(
                 /* Parameters */
                 parameter RPORT = 1,
                 parameter WPORT = 1,
                 parameter DEPTH = 16,
                 parameter INDEX = 4,
                 parameter WIDTH = 8,
                 parameter FUNCTION    = 0  // 0 = EQUAL_TO,  1 = GREATER_THAN
                 ) (

                    input [WIDTH-1:0]      tag0_i,
                    output reg [DEPTH-1:0] vect0_o,

                    input [INDEX-1:0]      addr0wr_i,
                    input [WIDTH-1:0]      data0wr_i,
                    input                  we0_i,


                    //input                                 reset,
                    input                  clk
                    );



  //`ifndef DYNAMIC_CONFIG

`ifdef LDQ_CAM_COMPILED
  //synopsys translate_off
`endif

  /* The RAM reg */
  reg [WIDTH-1:0]                          ram [DEPTH-1:0];

  /* Read operation */
  always_comb
    begin
      int i;
      
      for (i = 0; i < DEPTH; i++)
        begin
          vect0_o[i]   = 1'h0;
          
          if (ram[i] == tag0_i)
            begin
              vect0_o[i] = 1'h1;
            end
        end

    end


  /* Write operation */
  always_ff @(posedge clk)
    begin
      int i;
      
      //if (reset)
      //begin
      //        for (i = 0; i < DEPTH; i++)
      //        begin
      //                ram[i]              <= 0;
      //        end
      //end
      
      //else
      //begin
      if (we0_i)
        begin
          ram[addr0wr_i]      <= data0wr_i;
        end
      //end
    end
  
`ifdef LDQ_CAM_COMPILED
  //synopsys translate_on
`endif


endmodule


