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

module ALNPC_RAM #(

                   /* Parameters */
                   parameter RPORT = 1,
                   parameter WPORT = `ISSUE_WIDTH,
                   parameter DEPTH = 16,
                   parameter INDEX = 4,
                   parameter WIDTH = 8
                   ) (

                      input [INDEX-1:0]  addr0_i,
                      output [WIDTH-1:0] data0_o,


                      input [INDEX-1:0]  addr0wr_i,
                      input [WIDTH-1:0]  data0wr_i,
                      input              we0_i,

                      //`ifdef ISSUE_TWO_WIDE
                      //        input  [INDEX-1:0]                addr1wr_i,
                      //        input  [WIDTH-1:0]                data1wr_i,
                      //        input                             we1_i,
                      //`endif
                      //
                      //`ifdef ISSUE_THREE_WIDE
                      //        input  [INDEX-1:0]                addr2wr_i,
                      //        input  [WIDTH-1:0]                data2wr_i,
                      //        input                             we2_i,
                      //`endif
                      //
                      //`ifdef ISSUE_FOUR_WIDE
                      //        input  [INDEX-1:0]                addr3wr_i,
                      //        input  [WIDTH-1:0]                data3wr_i,
                      //        input                             we3_i,
                      //`endif
                      //
                      //`ifdef ISSUE_FIVE_WIDE
                      //        input  [INDEX-1:0]                addr4wr_i,
                      //        input  [WIDTH-1:0]                data4wr_i,
                      //        input                             we4_i,
                      //`endif
                      //
                      //`ifdef ISSUE_SIX_WIDE
                      //        input  [INDEX-1:0]                addr5wr_i,
                      //        input  [WIDTH-1:0]                data5wr_i,
                      //        input                             we5_i,
                      //`endif
                      //
                      //`ifdef ISSUE_SEVEN_WIDE
                      //        input  [INDEX-1:0]                addr6wr_i,
                      //        input  [WIDTH-1:0]                data6wr_i,
                      //        input                             we6_i,
                      //`endif
                      //
                      //`ifdef ISSUE_EIGHT_WIDE
                      //        input  [INDEX-1:0]                addr7wr_i,
                      //        input  [WIDTH-1:0]                data7wr_i,
                      //        input                             we7_i,
                      //`endif


                      //input                             reset,
                      input              clk
                      );

  //`ifndef DYNAMIC_CONFIG

`ifdef ALNPC_RAM_COMPILED
  //synopsys translate_off
`endif

  reg [WIDTH-1:0]                        ram [DEPTH-1:0];
  
  
  /* Read operation */
  assign data0_o                    = ram[addr0_i];
  
  
  /* Write operation */
  always_ff @(posedge clk)
    begin
      int i;
      
      //if (reset)
      //begin
      //        for (i = 0; i < DEPTH; i++)
      //        begin
      //                ram[i]         <= 0;
      //        end
      //end
      // 
      //else
      //begin
      if (we0_i)
        begin
          ram[addr0wr_i] <= data0wr_i;
        end
      
      //  `ifdef ISSUE_TWO_WIDE
      //                if (we1_i)
      //                begin
      //                        ram[addr1wr_i] <= data1wr_i;
      //                end
      //  `endif
      //  
      //  `ifdef ISSUE_THREE_WIDE
      //                if (we2_i)
      //                begin
      //                        ram[addr2wr_i] <= data2wr_i;
      //                end
      //  `endif
      //  
      //  `ifdef ISSUE_FOUR_WIDE
      //                if (we3_i)
      //                begin
      //                        ram[addr3wr_i] <= data3wr_i;
      //                end
      //  `endif
      //  
      //  `ifdef ISSUE_FIVE_WIDE
      //                if (we4_i)
      //                begin
      //                        ram[addr4wr_i] <= data4wr_i;
      //                end
      //  `endif
      //  
      //  `ifdef ISSUE_SIX_WIDE
      //                if (we5_i)
      //                begin
      //                        ram[addr5wr_i] <= data5wr_i;
      //                end
      //  `endif
      //  
      //  `ifdef ISSUE_SEVEN_WIDE
      //                if (we6_i)
      //                begin
      //                        ram[addr6wr_i] <= data6wr_i;
      //                end
      //  `endif
      //  
      //  `ifdef ISSUE_EIGHT_WIDE
      //                if (we7_i)
      //                begin
      //                        ram[addr7wr_i] <= data7wr_i;
      //                end
      //  `endif
      //end
    end

`ifdef ALNPC_RAM_COMPILED
  //synopsys translate_on
`endif


endmodule

