`include "global_header.svh"

/*************************NORTH CAROLINA STATE UNIVERSITY***********************
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

module LDX_path_structured (
                            input                                                     clk,
                            input                                                     reset,
                            input                                                     resetRams_i,

`ifdef SCRATCH_PAD  
                            input                                                     dataScratchPadEn_i,
                            input [`DEBUG_DATA_RAM_LOG+`DEBUG_DATA_RAM_WIDTH_LOG-1:0] dataScratchAddr_i ,
                            input [7:0]                                               dataScratchWrData_i ,
                            input                                                     dataScratchWrEn_i ,
                            output [7:0]                                              dataScratchRdData_o ,
`endif  
`ifdef DYNAMIC_CONFIG
                            input [`STRUCT_PARTS_LSQ-1:0]                             lsqPartitionActive_i,
`endif

`ifdef DATA_CACHE
                            input                                                     dataCacheBypass_i,
                            input                                                     dcScratchModeEn_i,

                            // cache-to-memory interface for Loads
                            output [`DCACHE_BLOCK_ADDR_BITS-1:0]                      dc2memLdAddr_o, // memory read address
                            output reg                                                dc2memLdValid_o, // memory read enable

                            // memory-to-cache interface for Loads
                            input [`DCACHE_TAG_BITS-1:0]                              mem2dcLdTag_i, // tag of the incoming datadetermine
                            input [`DCACHE_INDEX_BITS-1:0]                            mem2dcLdIndex_i, // index of the incoming data
                            input [`DCACHE_BITS_IN_LINE-1:0]                          mem2dcLdData_i, // requested data
                            input                                                     mem2dcLdValid_i, // indicates the requested data is ready

                            // cache-to-memory interface for stores
                            output [`DCACHE_ST_ADDR_BITS-1:0]                         dc2memStAddr_o, // memory read address
                            output [`SIZE_DATA-1:0]                                   dc2memStData_o, // memory read address
                            output [`SIZE_DATA_BYTE-1:0]                              dc2memStByteEn_o, // memory read address
                            output reg                                                dc2memStValid_o, // memory read enable

                            // memory-to-cache interface for stores
                            input                                                     mem2dcStComplete_i,
                            input                                                     mem2dcStStall_i ,

                            output                                                    stallStCommit_o,

                            input [`DCACHE_INDEX_BITS+`DCACHE_BYTES_IN_LINE_LOG-1:0]  dcScratchWrAddr_i,
                            input                                                     dcScratchWrEn_i,
                            input [7:0]                                               dcScratchWrData_i,
                            output [7:0]                                              dcScratchRdData_o,

                            input                                                     dcFlush_i,
                            output                                                    dcFlushDone_o,
`endif

                            output                                                    ldMiss_o,
                            output                                                    stMiss_o,

                            input                                                     recoverFlag_i,
                            input                                                     dispatchReady_i,

                            input                                                     lsqPkt lsqPacket_i [0:`DISPATCH_WIDTH-1],

                            input [`COMMIT_WIDTH_LOG:0]                               commitLdCount_i,
                            input [`SIZE_LSQ_LOG:0]                                   stqCount_i,

                            //input  memPkt                       memPacket_i,
                            input                                                     memPkt ldPacket_i,
                            input                                                     memPkt stPacket_i,

                            input                                                     commitSt_i,
                            input [`SIZE_LSQ_LOG-1:0]                                 stqHead_i,
                            input [`SIZE_LSQ_LOG-1:0]                                 stqTail_i,
                            input [`SIZE_LSQ-1:0]                                     stqAddrValid_on_recover_i,
                            output [`SIZE_VIRT_ADDR-1:0]                              stCommitAddr_o,

                            input [`SIZE_LSQ_LOG-1:0]                                 ldqID_i [0:`DISPATCH_WIDTH-1],
                            input [`SIZE_LSQ_LOG-1:0]                                 commitLdIndex_i [0:`COMMIT_WIDTH-1],

                            input [`SIZE_LSQ_LOG-1:0]                                 lastSt_i [0:`DISPATCH_WIDTH-1],

                            output                                                    ldVioPkt ldxVioPacket_o,
                            output                                                    exceptionPkt memExcptPacket_o,
                            output [`SIZE_DATA-1:0]                                   loadData_o,
                            output reg                                                loadDataValid_o,

                            /* To memory */
                            output [`SIZE_PC-1:0]                                     ldAddr_o,
                            input [`SIZE_DATA-1:0]                                    ldData_i,
                            input                                                     ldDataValid_i,
                            output                                                    ldEn_o,
                            input                                                     exceptionPkt ldException_i,

                            output [`SIZE_PC-1:0]                                     stAddr_o,
                            output [`SIZE_DATA-1:0]                                   stData_o,
                            output [7:0]                                              stEn_o,
                            input                                                     exceptionPkt stException_i,

                            output [1:0]                                              ldStSize_o,
                            output                                                    stqRamReady_o 
                            );


  reg [`SIZE_LSQ-1:0]                                                                 stqAddrValid;                       /* Part of Store Queue */

  reg [`SIZE_LSQ_LOG-1:0]                                                             lastSt_mem     [`SIZE_LSQ-1:0];   /* Part of Load Queue */
  reg [`SIZE_LSQ-1:0]                                                                 lastStValid_mem;                  /* Part of Load Queue */
  reg [`SIZE_LSQ-1:0]                                                                 ldqPredViolate;                   /* Part of Load Queue */

  reg [`SIZE_LSQ-1:0]                                                                 lastStValid_t;                    

  wire [`SIZE_LSQ-1:0]                                                                addr1MatchVector;
  wire [`SIZE_LSQ-1:0]                                                                addr2MatchVector;
  wire [`SIZE_LSQ-1:0]                                                                sizeMismatchVector;
  reg                                                                                 partialStMatch;
  reg                                                                                 stqHit;
  reg [`SIZE_LSQ_LOG-1:0]                                                             lastMatch;
  wire                                                                                predViolate;
  wire [`SIZE_DATA-1:0]                                                               stqHitData;
  wire [`SIZE_VIRT_ADDR-1:0]                                                          stqHitAddr;
  wire [`LDST_TYPES_LOG-1:0]                                                          stqHitSize;

  wire [`SIZE_VIRT_ADDR-1:`SIZE_DATA_BYTE_OFFSET]                                     commitWordAddr;
  wire [`SIZE_DATA_BYTE_OFFSET-1:0]                                                   commitByteAddr;
  wire [`SIZE_VIRT_ADDR-1:0]                                                          stCommitAddr;
  wire [`SIZE_DATA-1:0]                                                               stCommitData;
  wire [`LDST_TYPES_LOG-1:0]                                                          stCommitSize;

  wire                                                                                readHit;
  wire [`SIZE_DATA-1:0]                                                               dcacheData;
  wire                                                                                writeHit;

  reg [`SIZE_DATA-1:0]                                                                loadData;
  reg [`SIZE_DATA-1:0]                                                                loadData_t;

  exeFlgs                                 ldPacket_flags;
  exeFlgs                                 stPacket_flags;

  assign ldPacket_flags                 = ldPacket_i.flags;
  assign stPacket_flags                 = stPacket_i.flags;


  assign ldxVioPacket_o.seqNo           = ldPacket_i.seqNo;
  assign ldxVioPacket_o.alID            = ldPacket_i.alID;
  assign ldxVioPacket_o.valid           = partialStMatch;

  assign loadData_o                     = loadData;


  /* data cache will be accessed by loads in parallel with the STQ.
   * stores write to it when they retire. */

  L1DataCache L1dCache (
                        .clk                        (clk),
                        .reset                      (reset),
                        .recoverFlag_i              (recoverFlag_i),

`ifdef SCRATCH_PAD  
                        .dataScratchPadEn_i         (dataScratchPadEn_i),
                        .dataScratchAddr_i          (dataScratchAddr_i),
                        .dataScratchWrData_i        (dataScratchWrData_i),
                        .dataScratchWrEn_i          (dataScratchWrEn_i),
                        .dataScratchRdData_o        (dataScratchRdData_o),
`endif  

`ifdef DATA_CACHE
                        //.dataCacheBypass_i (dataCacheBypass_i  ),
                        .dataCacheBypass_i          (1'b0  ),  //Forcing to 0 to avoid problems in ANYCORE chip
                        .dcScratchModeEn_i          (dcScratchModeEn_i  ),  //Forcing to 0 to avoid problems in ANYCORE chip
                        
                        .dc2memLdAddr_o             (dc2memLdAddr_o     ), // memory read address
                        .dc2memLdValid_o            (dc2memLdValid_o    ), // memory read enable
                        
                        .mem2dcLdTag_i              (mem2dcLdTag_i      ), // tag of the incoming datadetermine
                        .mem2dcLdIndex_i            (mem2dcLdIndex_i    ), // index of the incoming data
                        .mem2dcLdData_i             (mem2dcLdData_i     ), // requested data
                        .mem2dcLdValid_i            (mem2dcLdValid_i    ), // indicates the requested data is ready
                        
                        .dc2memStAddr_o             (dc2memStAddr_o     ), // memory read address
                        .dc2memStData_o             (dc2memStData_o     ), // memory read address
                        .dc2memStByteEn_o           (dc2memStByteEn_o   ), // memory read address
                        .dc2memStValid_o            (dc2memStValid_o    ), // memory read enable
                        
                        .mem2dcStComplete_i         (mem2dcStComplete_i ),
                        .mem2dcStStall_i            (mem2dcStStall_i    ),

                        .stallStCommit_o            (stallStCommit_o),

                        .dcScratchWrAddr_i          (dcScratchWrAddr_i),
                        .dcScratchWrEn_i            (dcScratchWrEn_i  ),
                        .dcScratchWrData_i          (dcScratchWrData_i),
                        .dcScratchRdData_o          (dcScratchRdData_o),

                        .dcFlush_i                  (dcFlush_i),
                        .dcFlushDone_o              (dcFlushDone_o),
`endif    
                        
                        .ldMiss_o                   (ldMiss_o),
                        .stMiss_o                   (stMiss_o),

                        .rdEn_i                     (ldPacket_flags.destValid), //agenLoad_i),
                        .rdAddr_i                   (ldPacket_i.address),
                        .ldSize_i                   (ldPacket_i.ldstSize),
                        .ldSign_i                   (ldPacket_i.flags.ldSign),
                        .rdHit_o                    (readHit),
                        .rdData_o                   (dcacheData),

                        .wrEn_i                     (commitSt_i),
                        .wrAddr_i                   (stCommitAddr),
                        .wrData_i                   (stCommitData),
                        .stSize_i                   (stCommitSize),
                        .wrHit_o                    (writeHit),

                        .ldAddr_o                   (ldAddr_o),
                        .ldData_i                   (ldData_i),
                        .ldDataValid_i              (ldDataValid_i),
                        .ldEn_o                     (ldEn_o),

                        .stAddr_o                   (stAddr_o),
                        .stData_o                   (stData_o),
                        .stEn_o                     (stEn_o),
                        .ldStSize_o                 (ldStSize_o)
                        );


  // When a load or store packet has a valid address, do the translation.
  // Do not expose the read or write to the memory system
  // TODO: Write DPI functions for address translation.

  memPkt                            memPacket;
  logic [`SIZE_DATA-1:0]                                                              phyAddress;
  wire [7:0]                                                                          exception;
  reg [`SIZE_DATA_BYTE_OFFSET-1:0]                                                    memAccessBytes;

  always_comb
    begin
      case({stPacket_i.valid,ldPacket_i.valid})
        2'b00:memPacket = 0;
        2'b01:memPacket = ldPacket_i;
        2'b10:memPacket = stPacket_i;
        2'b11:memPacket = 'bx; //Invalid scenario
      endcase
      case(memPacket.ldstSize)
        2'b00: memAccessBytes = 1;
        2'b01: memAccessBytes = 2;
        2'b10: memAccessBytes = 4;
        2'b11: memAccessBytes = 4;
      endcase
    end

  // MMU in parallel with cache access.
  // Need to figure out whether a load/store
  // excepts. This is even more critical for stores
  // as we must figure out before exposing the store to the
  // cache hierarchy.
  MMU mmu
    (
     .clk            (clk),
     .virtAddress_i  (memPacket.address),
     .numBytes_i     (memAccessBytes),
     .ldAccess_i     (ldPacket_i.valid),
     .stAccess_i     (stPacket_i.valid),
     .instAccess_i   (1'b0),
     .exception_o    (exception)
     );

  always_comb
    begin
      memExcptPacket_o.seqNo            = memPacket.seqNo;
      memExcptPacket_o.alID             = memPacket.alID; 
      memExcptPacket_o.exceptionCause   = exception; 
      memExcptPacket_o.exception        = (exception != 0); // If exception = 0, then no exception
      memExcptPacket_o.valid            = (exception != 0) & memPacket.valid;
    end


  assign stqRamReady_o = 1'b1;

`ifdef DYNAMIC_CONFIG
  STQ_CAM_PARTITIONED #(
`else
                        STQ_CAM #(
`endif
                                  .RPORT       (1),
                                  .WPORT       (1),
                                  .DEPTH       (`SIZE_LSQ),
                                  .INDEX       (`SIZE_LSQ_LOG),
                                  .WIDTH       (`SIZE_VIRT_ADDR-`SIZE_DATA_BYTE_OFFSET)
                                  )

                        addr1Cam (

                                  .tag0_i      (ldPacket_i.address[`SIZE_VIRT_ADDR-1:`SIZE_DATA_BYTE_OFFSET]),
                                  .vect0_o     (addr1MatchVector),

                                  .addr0wr_i   (stPacket_i.lsqID),
                                  .data0wr_i   (stPacket_i.address[`SIZE_VIRT_ADDR-1:`SIZE_DATA_BYTE_OFFSET]),
                                  .we0_i       (~stPacket_flags.destValid & stPacket_i.valid),

                                  //.wrAddr1_i   (stqHead_i),
                                  //.wrData1_i   ({`SIZE_VIRT_ADDR-`SIZE_DATA_BYTE_OFFSET{1'b0}}),
                                  //.we1_i       (commitSt_i),

`ifdef DYNAMIC_CONFIG    
                                  .lsqPartitionActive_i  (lsqPartitionActive_i),
`endif    

                                  .clk         (clk)
                                  //.reset       (reset)
                                  );

`ifdef DYNAMIC_CONFIG
                        STQ_CAM_PARTITIONED #(
`else
                                              STQ_CAM #(
`endif
                                                        .RPORT       (1),
                                                        .WPORT       (1),
                                                        .DEPTH       (`SIZE_LSQ),
                                                        .INDEX       (`SIZE_LSQ_LOG),
                                                        .WIDTH       (`SIZE_DATA_BYTE_OFFSET)
                                                        )

                                              addr2Cam (

                                                        .tag0_i      (ldPacket_i.address[`SIZE_DATA_BYTE_OFFSET-1:0]),
                                                        .vect0_o     (addr2MatchVector),

                                                        .addr0wr_i   (stPacket_i.lsqID),
                                                        .data0wr_i   (stPacket_i.address[`SIZE_DATA_BYTE_OFFSET-1:0]),
                                                        .we0_i       (~stPacket_flags.destValid & stPacket_i.valid),

                                                        //.wrAddr1_i   (stqHead_i),
                                                        //.wrData1_i   ({`SIZE_DATA_BYTE_OFFSET{1'b0}}),
                                                        //.we1_i       (commitSt_i),

`ifdef DYNAMIC_CONFIG    
                                                        .lsqPartitionActive_i  (lsqPartitionActive_i),
`endif    

                                                        .clk         (clk)
                                                        //.reset       (reset)
                                                        );

                                              localparam EQUAL_TO  = 0;
                                              localparam GREATER_THAN = 1;

`ifdef DYNAMIC_CONFIG
                                              STQ_CAM_PARTITIONED #(
`else
                                                                    STQ_CAM #(
`endif
                                                                              .RPORT       (1),
                                                                              .WPORT       (1),
                                                                              .DEPTH       (`SIZE_LSQ),
                                                                              .INDEX       (`SIZE_LSQ_LOG),
                                                                              .WIDTH       (`LDST_TYPES_LOG),
                                                                              .FUNCTION    (GREATER_THAN)
                                                                              )

                                                                    stqSizeCam (

                                                                                .tag0_i      (ldPacket_i.ldstSize),
                                                                                .vect0_o     (sizeMismatchVector),

                                                                                .addr0wr_i   (stPacket_i.lsqID),
                                                                                .data0wr_i   (stPacket_i.ldstSize),
                                                                                .we0_i       (~stPacket_flags.destValid & stPacket_i.valid),

                                                                                //.wrAddr1_i   (stqHead_i),
                                                                                //.wrData1_i   ({`LDST_TYPES_LOG{1'b0}}),
                                                                                //.we1_i       (commitSt_i),

`ifdef DYNAMIC_CONFIG    
                                                                                .lsqPartitionActive_i  (lsqPartitionActive_i),
`endif    

                                                                                .clk         (clk)
                                                                                //.reset       (reset)
                                                                                );

`ifdef DYNAMIC_CONFIG
                                                                    STQ_RAM_PARTITIONED #(
`else
                                                                                          STQ_RAM #(
`endif
                                                                                                    .RPORT       (2),
                                                                                                    .WPORT       (1),
                                                                                                    .DEPTH       (`SIZE_LSQ),
                                                                                                    .INDEX       (`SIZE_LSQ_LOG),
                                                                                                    .WIDTH       (`SIZE_DATA+`SIZE_VIRT_ADDR+`LDST_TYPES_LOG)
                                                                                                    )

                                                                                          dataRam  (

                                                                                                    .addr0_i     (stqHead_i),
                                                                                                    .data0_o     ({stCommitData,commitWordAddr,commitByteAddr,stCommitSize}),

                                                                                                    .addr1_i     (lastMatch),
                                                                                                    .data1_o     ({stqHitData,stqHitAddr,stqHitSize}),

                                                                                                    .addr0wr_i   (stPacket_i.lsqID),
                                                                                                    .data0wr_i   ({stPacket_i.src2Data,stPacket_i.address,stPacket_i.ldstSize}),
                                                                                                    .we0_i       (~stPacket_flags.destValid & stPacket_i.valid),

                                                                                                    //.addr1wr_i   (stqHead_i),
                                                                                                    //.data1wr_i   ({(`SIZE_DATA+`SIZE_VIRT_ADDR+`LDST_TYPES_LOG){1'b0}}),
                                                                                                    //.we1_i       (commitSt_i),


`ifdef DYNAMIC_CONFIG    
                                                                                                    .lsqPartitionActive_i  (lsqPartitionActive_i),
                                                                                                    .stqRamReady_o         (),
`endif    

                                                                                                    .clk         (clk)
                                                                                                    //.reset       (reset)
                                                                                                    );


                                                                                          /* Read out the Address, Data, and size of next store */
                                                                                          assign stCommitAddr     = {commitWordAddr,commitByteAddr};
                                                                                          assign stCommitAddr_o   = stCommitAddr;


                                                                                          /* In case of a load read the corresponding ldqPredViolate entry to determine 
                                                                                           * whether to stall this load or allow it to execute if any of the prior
                                                                                           * store's address is not computed till then
                                                                                           */
`ifdef ENABLE_LD_VIOLATION_PRED
                                                                                          assign predViolate     = ldqPredViolate[ldPacket_i.lsqID];
`else
                                                                                          assign predViolate     = 1'b0;
`endif


                                                                                          /* Load disambiguation logic.
                                                                                           * Loads check the store queue
                                                                                           */
                                                                                          always_comb
                                                                                          begin:LD_DISAMBIGUATION
                                                                                          reg [`SIZE_LSQ_LOG-1:0]               lastSt;
                                                                                          reg                                   lastStValid;
                                                                                          reg [`SIZE_LSQ_LOG-1:0]               index;
                                                                                          reg                                   stqWrap;
                                                                                          reg [`SIZE_LSQ-1:0]                   vulnerableStVector;
                                                                                          reg [`SIZE_LSQ-1:0]                   vulnerableStVector_t1;
                                                                                          reg [`SIZE_LSQ-1:0]                   vulnerableStVector_t2;
                                                                                          reg                                   disambigStall;
                                                                                          reg [`SIZE_LSQ-1:0]                   forwardVector1;
                                                                                          reg [`SIZE_LSQ-1:0]                   forwardVector2;
                                                                                          int i;

                                                                                          //Default to avoid latch
                                                                                          //RBRC: 07/12/2013
                                                                                          index = {`SIZE_LSQ_LOG{1'b0}};

                                                                                          /* Get the index of the 1st store older than this load */
                                                                                          lastSt                = lastSt_mem[ldPacket_i.lsqID];

                                                                                          /* Know whether the STQ wraps or not */
                                                                                          stqWrap               = (stqHead_i   > lastSt);

                                                                                          /* Ensure lastSt is a valid index */
                                                                                          // The second compare takes care of stq full conditon.
                                                                                          // One must make sure that the empty case is excluded as
                                                                                          // the condition for full and empty cases are the same.
                                                                                          lastStValid           = ((stqHead_i <  stqTail_i)  && (lastSt    >= stqHead_i)  && (lastSt    <  stqTail_i)) || 
                                                                                          ((stqTail_i <= stqHead_i) && !(stqCount_i == 0)  && ((lastSt   <  stqTail_i)  || (lastSt   >= stqHead_i))); //Only if stq not empty


                                                                                          /* vulnerableStVector: Stores between stqHead and lastSt. These are vulnerable
                                                                                           * to store-load forwardingi. 
                                                                                           * t1: vector when the STQ doesn't wrap.
                                                                                           * t2: vector when the STQ wraps. */
                                                                                          for (i = 0; i < `SIZE_LSQ; i = i + 1)
                                                                                          begin
                                                                                          if ((i >= stqHead_i) && (i <= lastSt))
                                                                                          begin
                                                                                          vulnerableStVector_t1[i] = 1'b1;
                                                                                          end

                                                                                          else
                                                                                          begin
                                                                                          vulnerableStVector_t1[i] = 1'b0;
                                                                                          end

                                                                                          if ((i <= lastSt) || (i >= stqHead_i))
                                                                                          begin
                                                                                          vulnerableStVector_t2[i] = 1'b1;
                                                                                          end
                                                                                          
                                                                                          else
                                                                                          begin
                                                                                          vulnerableStVector_t2[i] = 1'b0;
                                                                                          end
                                                                                          end

                                                                                          if (stqWrap && lastStValid)
                                                                                          begin
                                                                                          vulnerableStVector  =  vulnerableStVector_t2;
                                                                                          end

                                                                                          else if (lastStValid)
                                                                                          begin
                                                                                          vulnerableStVector  = vulnerableStVector_t1;
                                                                                          end
                                                                                          
                                                                                          else
                                                                                          begin
                                                                                          vulnerableStVector = 0;
                                                                                          end
                                                                                          
                                                                                          
                                                                                          /* addrMatchVector: Stores whose address matches the load's address. 
                                                                                           * addr1MatchVector: Word address matches.
                                                                                           * addr2MatchVector: byte offset matches.
                                                                                           * sizeMismatchVector: Stores with a smaller data size than the load */

                                                                                          /* forwardVector1: Stores that are valid, older than the load, and match the
                                                                                           *                 load's address.
                                                                                           * forwardVector2: Stores that are valid and older than the load but either
                                                                                           *                 writes different bytes or not enough bytes. */
                                                                                          forwardVector1        = stqAddrValid & vulnerableStVector & addr1MatchVector & addr2MatchVector;
                                                                                          forwardVector2        = stqAddrValid & vulnerableStVector & addr1MatchVector & (~addr2MatchVector | sizeMismatchVector);

                                                                                          stqHit                = 0;
                                                                                          lastMatch             = 0;
                                                                                          partialStMatch        = 0;
                                                                                          disambigStall         = 0;

                                                                                          if (ldPacket_flags.destValid && ldPacket_i.valid && lastStValid_mem[ldPacket_i.lsqID])
                                                                                          begin
                                                                                          for (i = 0; i < `SIZE_LSQ; i = i + 1)
                                                                                          begin
                                                                                          index = stqHead_i + i;

                                                                                          /* Check for any store-to-load forwarding */
                                                                                          if (forwardVector1[index])
                                                                                          begin
                                                                                          stqHit            = 1'h1;
                                                                                          lastMatch         = index;
                                                                                          partialStMatch    = 1'h0;
                                                                                          end

                                                                                          /* Check for any partial store-load match case.
                                                                                           * Note: The load is marked as violated in this case */
                                                                                          if (forwardVector2[index])
                                                                                          begin
                                                                                          partialStMatch    = 1'h1;
                                                                                          end

                                                                                          /* Check if there are any stores in vulnerability window whose address 
                                                                                           * is unknown. If the load was predicted to violate then stall it. */
                                                                                          if (predViolate && vulnerableStVector[index] && !stqAddrValid[index])
                                                                                          begin
                                                                                          disambigStall     = 1'h1;
                                                                                          end
                                                                                          end
                                                                                          end

                                                                                          /* data for the load comes either from STQ (store-load forwarding) or from the
                                                                                           * data cache */
                                                                                          // If it is bypass from the load fill pipeline, use that as valid 
                                                                                          loadDataValid_o         = (readHit | stqHit) && !disambigStall;
                                                                                          loadData                = (stqHit) ? stqHitData : dcacheData; // dcacheData can be from RAM or from load fill
                                                                                          end


                                                                                          //always_comb
                                                                                          //begin:SELF_EVALUATION
                                                                                          //    if (ldPacket_i.ldstSize == `LDST_BYTE)
                                                                                          //    begin
                                                                                          //            if (ldPacket_flags.ldSign)
                                                                                          //            begin
                                                                                          //                    loadData = {{24{loadData_t[7]}}, loadData_t[7:0]};
                                                                                          //            end
                                                                                          //
                                                                                          //            else
                                                                                          //            begin
                                                                                          //                    loadData = {24'h000000, loadData_t[7:0]};
                                                                                          //            end
                                                                                          //    end
                                                                                          //
                                                                                          //    else if (ldPacket_i.ldstSize == `LDST_HALF_WORD)
                                                                                          //    begin
                                                                                          //            if (ldPacket_flags.ldSign)
                                                                                          //            begin
                                                                                          //                    loadData  = {{16{loadData_t[15]}}, loadData_t[15:0]};
                                                                                          //            end
                                                                                          //
                                                                                          //            else
                                                                                          //            begin
                                                                                          //                    loadData  = {16'h0000, loadData_t[15:0]};
                                                                                          //            end
                                                                                          //    end
                                                                                          //
                                                                                          //    else
                                                                                          //    begin
                                                                                          //            loadData  = loadData_t;
                                                                                          //    end
                                                                                          //end


                                                                                          /* Invalidate the preceding store entries that exists for each load 
                                                                                           * entry in the load queue if that store commits to data cache. 
                                                                                           * This load queue structure has been placed here as it is a part 
                                                                                           * of load execution path and loads needs to read the last store from it */
                                                                                          always_comb
                                                                                          begin:INVALIDATE_PRECEDE_ST_ON_COMMIT
                                                                                          // RBRC: 07/12/2013 Should just be a binary flag
                                                                                          reg stqEmpty;
                                                                                          int i;

                                                                                          stqEmpty             = ((stqCount_i - commitSt_i) == 0);

                                                                                          if (commitSt_i)
                                                                                          begin
                                                                                          for (i = 0; i < `SIZE_LSQ; i = i + 1)
                                                                                          begin
                                                                                          if (lastSt_mem[i] == stqHead_i)
                                                                                          begin
                                                                                          lastStValid_t[i] = 1'b0;
                                                                                          end

                                                                                          else
                                                                                          begin
                                                                                          lastStValid_t[i] = lastStValid_mem[i];
                                                                                          end
                                                                                          end
                                                                                          end

                                                                                          else
                                                                                          begin
                                                                                          lastStValid_t = lastStValid_mem;
                                                                                          end

                                                                                          if (dispatchReady_i)
                                                                                          begin
                                                                                          if (lsqPacket_i[0].isLoad && !stqEmpty)
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[0]] = 1'h1;
                                                                                          end

`ifdef DISPATCH_TWO_WIDE
                                                                                          if (lsqPacket_i[1].isLoad && (!stqEmpty || lsqPacket_i[0].isStore))
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[1]] = 1'h1;
                                                                                          end
`endif

`ifdef DISPATCH_THREE_WIDE
                                                                                          if (lsqPacket_i[2].isLoad && (!stqEmpty || lsqPacket_i[1].isStore
                                                                                                                        || lsqPacket_i[0].isStore))
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[2]] = 1'h1;
                                                                                          end
`endif

`ifdef DISPATCH_FOUR_WIDE
                                                                                          if (lsqPacket_i[3].isLoad && (!stqEmpty || lsqPacket_i[2].isStore
                                                                                                                        || lsqPacket_i[1].isStore
                                                                                                                        || lsqPacket_i[0].isStore))
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[3]] = 1'h1;
                                                                                          end
`endif

`ifdef DISPATCH_FIVE_WIDE
                                                                                          if (lsqPacket_i[4].isLoad && (!stqEmpty || lsqPacket_i[3].isStore
                                                                                                                        || lsqPacket_i[2].isStore
                                                                                                                        || lsqPacket_i[1].isStore
                                                                                                                        || lsqPacket_i[0].isStore))
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[4]] = 1'h1;
                                                                                          end
`endif

`ifdef DISPATCH_SIX_WIDE
                                                                                          if (lsqPacket_i[5].isLoad && (!stqEmpty || lsqPacket_i[4].isStore
                                                                                                                        || lsqPacket_i[3].isStore
                                                                                                                        || lsqPacket_i[2].isStore
                                                                                                                        || lsqPacket_i[1].isStore
                                                                                                                        || lsqPacket_i[0].isStore))
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[5]] = 1'h1;
                                                                                          end
`endif

`ifdef DISPATCH_SEVEN_WIDE
                                                                                          if (lsqPacket_i[6].isLoad && (!stqEmpty || lsqPacket_i[5].isStore
                                                                                                                        || lsqPacket_i[4].isStore
                                                                                                                        || lsqPacket_i[3].isStore
                                                                                                                        || lsqPacket_i[2].isStore
                                                                                                                        || lsqPacket_i[1].isStore
                                                                                                                        || lsqPacket_i[0].isStore))
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[6]] = 1'h1;
                                                                                          end
`endif

`ifdef DISPATCH_EIGHT_WIDE
                                                                                          if (lsqPacket_i[7].isLoad && (!stqEmpty || lsqPacket_i[6].isStore
                                                                                                                        || lsqPacket_i[5].isStore
                                                                                                                        || lsqPacket_i[4].isStore
                                                                                                                        || lsqPacket_i[3].isStore
                                                                                                                        || lsqPacket_i[2].isStore
                                                                                                                        || lsqPacket_i[1].isStore
                                                                                                                        || lsqPacket_i[0].isStore))
                                                                                          begin
                                                                                          lastStValid_t[ldqID_i[7]] = 1'h1;
                                                                                          end
`endif

                                                                                          end
                                                                                          end


                                                                                          // TODO: Partition these flip flops
                                                                                          /* Incoming stores update store queue payload that includes following structures
                                                                                           * StqAddress
                                                                                           * StqData
                                                                                           * Stq size of Store
                                                                                           * StqAddressValid */

                                                                                          always_ff @(posedge clk or posedge reset)
                                                                                          begin:STQ_UPDATE
                                                                                          int i;

                                                                                          if (reset)
                                                                                          begin
                                                                                          stqAddrValid            <= 0;
                                                                                          end

                                                                                          else if (recoverFlag_i)
                                                                                          begin
                                                                                          stqAddrValid                      <= stqAddrValid_on_recover_i;
                                                                                          end

                                                                                          else
                                                                                          begin
                                                                                          if (commitSt_i) 
                                                                                          begin
                                                                                          stqAddrValid[stqHead_i]         <= 0;
                                                                                          end

                                                                                          /* Update during execute - if the instruction sent by agen is a store */
                                                                                          if (~stPacket_flags.destValid && stPacket_i.valid) //agenStore_i)
                                                                                          begin
                                                                                          stqAddrValid[stPacket_i.lsqID] <= 1'b1;
                                                                                          end
                                                                                          end
                                                                                          end


                                                                                          // TODO: Partition these structures
                                                                                          /* update stq structures - preceding store, preceding st valid and ldqpreviolate
                                                                                           * These are part of load execution path */

                                                                                          //`ifdef DYNAMIC_CONFIG
                                                                                          always_ff @(posedge clk or posedge reset)
                                                                                          begin:LDQ_UPDATE
                                                                                          int i;

                                                                                          if (reset)
                                                                                          begin
                                                                                          lastStValid_mem                <= 0;
                                                                                          end

                                                                                          else if (recoverFlag_i)
                                                                                          begin
                                                                                          lastStValid_mem                <= 0;
                                                                                          end
                                                                                          else
                                                                                          begin
                                                                                          lastStValid_mem                <= lastStValid_t;

                                                                                          if (dispatchReady_i)
                                                                                          begin
                                                                                          if (lsqPacket_i[0].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[0]]     <= lastSt_i[0];
                                                                                          ldqPredViolate[ldqID_i[0]] <= lsqPacket_i[0].predLoadVio;
                                                                                          end
                                                                                          
`ifdef DISPATCH_TWO_WIDE
                                                                                          if (lsqPacket_i[1].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[1]]     <= lastSt_i[1];
                                                                                          ldqPredViolate[ldqID_i[1]] <= lsqPacket_i[1].predLoadVio;
                                                                                          end
`endif
                                                                                          
`ifdef DISPATCH_THREE_WIDE
                                                                                          if (lsqPacket_i[2].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[2]]     <= lastSt_i[2];
                                                                                          ldqPredViolate[ldqID_i[2]] <= lsqPacket_i[2].predLoadVio;
                                                                                          end
`endif
                                                                                          
`ifdef DISPATCH_FOUR_WIDE
                                                                                          if (lsqPacket_i[3].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[3]]     <= lastSt_i[3];
                                                                                          ldqPredViolate[ldqID_i[3]] <= lsqPacket_i[3].predLoadVio;
                                                                                          end
`endif
                                                                                          
`ifdef DISPATCH_FIVE_WIDE
                                                                                          if (lsqPacket_i[4].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[4]]     <= lastSt_i[4];
                                                                                          ldqPredViolate[ldqID_i[4]] <= lsqPacket_i[4].predLoadVio;
                                                                                          end
`endif
                                                                                          
`ifdef DISPATCH_SIX_WIDE
                                                                                          if (lsqPacket_i[5].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[5]]     <= lastSt_i[5];
                                                                                          ldqPredViolate[ldqID_i[5]] <= lsqPacket_i[5].predLoadVio;
                                                                                          end
`endif
                                                                                          
`ifdef DISPATCH_SEVEN_WIDE
                                                                                          if (lsqPacket_i[6].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[6]]     <= lastSt_i[6];
                                                                                          ldqPredViolate[ldqID_i[6]] <= lsqPacket_i[6].predLoadVio;
                                                                                          end
`endif
                                                                                          
`ifdef DISPATCH_EIGHT_WIDE
                                                                                          if (lsqPacket_i[7].isLoad)
                                                                                          begin
                                                                                          lastSt_mem[ldqID_i[7]]     <= lastSt_i[7];
                                                                                          ldqPredViolate[ldqID_i[7]] <= lsqPacket_i[7].predLoadVio;
                                                                                          end
`endif
                                                                                          end

                                                                                          /* Update at retire */

`ifdef SIM
                                                                                          case (commitLdCount_i)
                                                                                          3'd1:
                                                                                          begin
                                                                                          lastSt_mem[commitLdIndex_i[0]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[0]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[0]]    <= 0;
                                                                                          end

                                                                                          3'd2:
                                                                                          begin
                                                                                          lastSt_mem[commitLdIndex_i[0]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[0]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[0]]    <= 0;

                                                                                          lastSt_mem[commitLdIndex_i[1]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[1]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[1]]    <= 0;
                                                                                          end
 `ifdef COMMIT_THREE_WIDE
                                                                                          3'd3:
                                                                                          begin
                                                                                          lastSt_mem[commitLdIndex_i[0]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[0]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[0]]    <= 0;

                                                                                          lastSt_mem[commitLdIndex_i[1]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[1]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[1]]    <= 0;

                                                                                          lastSt_mem[commitLdIndex_i[2]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[2]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[2]]    <= 0;
                                                                                          end
 `endif 

 `ifdef COMMIT_FOUR_WIDE
                                                                                          3'd4:
                                                                                          begin
                                                                                          lastSt_mem[commitLdIndex_i[0]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[0]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[0]]    <= 0;

                                                                                          lastSt_mem[commitLdIndex_i[1]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[1]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[1]]    <= 0;

                                                                                          lastSt_mem[commitLdIndex_i[2]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[2]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[2]]    <= 0;

                                                                                          lastSt_mem[commitLdIndex_i[3]]        <= 0;
                                                                                          lastStValid_mem[commitLdIndex_i[3]]   <= 0;
                                                                                          ldqPredViolate[commitLdIndex_i[3]]    <= 0;
                                                                                          end
 `endif
                                                                                          default:
                                                                                          begin 
                                                                                          end
                                                                                          endcase
`endif
                                                                                          end
                                                                                          end

                                                                                          //`else  
                                                                                          //
                                                                                          //STQ_FOLLOWINGLD_RAM #(
                                                                                          //
                                                                                          //    /* Parameters */
                                                                                          //    .DEPTH(`SIZE_LSQ),
                                                                                          //    .INDEX(`SIZE_LSQ_LOG),
                                                                                          //    .WIDTH(`SIZE_LSQ_LOG)
                                                                                          //    ) lastStRam (
                                                                                          //
                                                                                          //    .addr0_i(ldPacket_i.lsqID),
                                                                                          //    .data0_o(lastSt),
                                                                                          //
                                                                                          //    .addr0wr_i(ldqID_i[0]),
                                                                                          //    .data0wr_i(lastSt_i[0]),
                                                                                          //    .we0_i(dispatchReady_i & lsqPacket_i[0].isLoad),
                                                                                          //
                                                                                          //`ifdef DISPATCH_TWO_WIDE
                                                                                          //    .addr1wr_i(ldqID_i[1]),
                                                                                          //    .data1wr_i(lastSt_i[1]),
                                                                                          //    .we1_i(dispatchReady_i & lsqPacket_i[1].isLoad),
                                                                                          //`endif
                                                                                          //
                                                                                          //`ifdef DISPATCH_THREE_WIDE
                                                                                          //    .addr2wr_i(ldqID_i[2]),
                                                                                          //    .data2wr_i(lastSt_i[2]),
                                                                                          //    .we2_i(dispatchReady_i & lsqPacket_i[2].isLoad),
                                                                                          //`endif
                                                                                          //
                                                                                          //`ifdef DISPATCH_FOUR_WIDE
                                                                                          //    .addr3wr_i(ldqID_i[3]),
                                                                                          //    .data3wr_i(lastSt_i[3]),
                                                                                          //    .we3_i(dispatchReady_i & lsqPacket_i[3].isLoad),
                                                                                          //`endif
                                                                                          //
                                                                                          //`ifdef DISPATCH_FIVE_WIDE
                                                                                          //    .addr4wr_i(ldqID_i[4]),
                                                                                          //    .data4wr_i(lastSt_i[4]),
                                                                                          //    .we4_i(dispatchReady_i & lsqPacket_i[4].isLoad),
                                                                                          //`endif
                                                                                          //
                                                                                          //`ifdef DISPATCH_SIX_WIDE
                                                                                          //    .addr5wr_i(ldqID_i[5]),
                                                                                          //    .data5wr_i(lastSt_i[5]),
                                                                                          //    .we5_i(dispatchReady_i & lsqPacket_i[5].isLoad),
                                                                                          //`endif
                                                                                          //
                                                                                          //`ifdef DISPATCH_SEVEN_WIDE
                                                                                          //    .addr6wr_i(ldqID_i[6]),
                                                                                          //    .data6wr_i(lastSt_i[6]),
                                                                                          //    .we6_i(dispatchReady_i & lsqPacket_i[6].isLoad),
                                                                                          //`endif
                                                                                          //
                                                                                          //`ifdef DISPATCH_EIGHT_WIDE
                                                                                          //    .addr7wr_i(ldqID_i[7]),
                                                                                          //    .data7wr_i(lastSt_i[7]),
                                                                                          //    .we7_i(dispatchReady_i & lsqPacket_i[7].isLoad),
                                                                                          //`endif
                                                                                          //
                                                                                          //`ifdef DYNAMIC_CONFIG
                                                                                          //  .dispatchLaneActive_i(dispatchLaneActive_i),
                                                                                          //  .lsqPartitionActive_i(lsqPartitionActive_i),
                                                                                          //  .commitLaneActive_i  (commitLaneActive_i),
                                                                                          //  .ldqRamReady_o(),
                                                                                          //`endif
                                                                                          //
                                                                                          //    .clk(clk),
                                                                                          //    .reset(reset | recoverFlag_i)
                                                                                          //);
                                                                                          //
                                                                                          //
                                                                                          //
                                                                                          //`endif  

                                                                                          endmodule
