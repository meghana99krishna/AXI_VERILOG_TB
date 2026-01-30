// axi_lite_tb_clean.sv
// Testbench paired with axi_lite_slave_clean.sv
`timescale 1ns/1ps

module axi_lite_tb_clean;

    logic clk;
    logic resetn;

    // Write Address
    logic [3:0] AWADDR;
    logic       AWVALID;
    logic       AWREADY;

    // Write Data
    logic [31:0] WDATA;
    logic        WVALID;
    logic        WREADY;

    // Write Response
    logic [1:0]  BRESP;
    logic        BVALID;
    logic        BREADY;

    // Read Address
    logic [3:0] ARADDR;
    logic       ARVALID;
    logic       ARREADY;

    // Read Data
    logic [31:0] RDATA;
    logic [1:0]  RRESP;
    logic        RVALID;
    logic        RREADY;

    logic [31:0] rdata;

    // DUT
    axi_lite_slave_clean #(.ADDR_WIDTH(4), .DATA_WIDTH(32)) dut (
        .clk(clk),
        .resetn(resetn),
        .AWADDR(AWADDR),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .WDATA(WDATA),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .BRESP(BRESP),
        .BVALID(BVALID),
        .BREADY(BREADY),
        .ARADDR(ARADDR),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .RDATA(RDATA),
        .RRESP(RRESP),
        .RVALID(RVALID),
        .RREADY(RREADY)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz-ish
    end

    // Reset
    initial begin
        resetn = 0;
        #20;
        resetn = 1;
    end

    // Initialize signals
    initial begin
        AWVALID = 0; WVALID = 0; BREADY = 0;
        ARVALID = 0; RREADY = 0;
        AWADDR = 0; ARADDR = 0; WDATA = 0;
    end

    // ---------------------------
    // Synchronous safe write task
    // ---------------------------
    task axi_write(input [3:0] addr, input [31:0] data);
    begin
        $display("[%0t] TB: START WRITE addr=%0h data=%0h", $time, addr, data);
        // drive values and hold VALIDs until handshake completes
        AWADDR = addr;
        WDATA  = data;

        AWVALID = 1;
        WVALID  = 1;
        BREADY  = 1;

        // Wait for AW handshake (sampled on posedge)
        @(posedge clk);
        while (!(AWVALID && AWREADY)) @(posedge clk);
        @(posedge clk);
        AWVALID = 0;

        // Wait for W handshake
        while (!(WVALID && WREADY)) @(posedge clk);
        @(posedge clk);
        WVALID = 0;

        // Wait for BVALID (response)
        while (!BVALID) @(posedge clk);
        @(posedge clk); // accept response on this posedge (BREADY is 1)
        $display("[%0t] TB: WRITE COMPLETE RESP=%0b", $time, BRESP);

        // stop ready for response
        BREADY = 0;
    end
    endtask

    // ---------------------------
    // Synchronous safe read task
    // ---------------------------
    task axi_read(input [3:0] addr, output [31:0] data);
    begin
        $display("[%0t] TB: START READ addr=%0h", $time, addr);
        ARADDR = addr;
        ARVALID = 1;
        RREADY = 1;

        @(posedge clk);
        while (!(ARVALID && ARREADY)) @(posedge clk);
        @(posedge clk);
        ARVALID = 0;

        // Wait for read data
        while (!RVALID) @(posedge clk);
        @(posedge clk);
        data = RDATA;
        $display("[%0t] TB: READ COMPLETE data=%0h", $time, data);

        RREADY = 0;
    end
    endtask

    // ---------------------------
    // Main stimulus
    // ---------------------------
    initial begin
        // wait for reset release
        @(posedge resetn);

        // A few writes with readback checks
        axi_write(4'h1, 32'hDEAD_BEEF);
        axi_write(4'h3, 32'h1122_3344);
        axi_write(4'h7, 32'hAABB_CCDD);

        // Reads (verify)
        axi_read(4'h1, rdata);
        if (rdata !== 32'hDEAD_BEEF) $display("[ERROR] MISMATCH @1 wrote DEAD_BEEF read %0h", rdata);
        else $display("[OK] addr1 match");

        axi_read(4'h3, rdata);
        if (rdata !== 32'h11223344) $display("[ERROR] MISMATCH @3 wrote 11223344 read %0h", rdata);
        else $display("[OK] addr3 match");

        axi_read(4'h7, rdata);
        if (rdata !== 32'hAABBCCDD) $display("[ERROR] MISMATCH @7 wrote AABBCCDD read %0h", rdata);
        else $display("[OK] addr7 match");

        #50;
        $display("TEST DONE");
        $finish;
    end
  initial 
    begin
     $dumpfile("dump.vcd");
     $dumpvars;
    end

endmodule

/////////////////////
`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

////////////////////////////////////////////////////////////
// AXI TRANSACTION
////////////////////////////////////////////////////////////
class axi_txn extends uvm_sequence_item;

  bit        is_expected;   // 1 = expected, 0 = actual
  bit [3:0]  id;
  bit [31:0] addr;
  bit [31:0] data;
  bit [1:0]  resp;

  `uvm_object_utils(axi_txn)

  function new(string name="axi_txn");
    super.new(name);
  endfunction

endclass


////////////////////////////////////////////////////////////
// AXI SCOREBOARD
////////////////////////////////////////////////////////////
class axi_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axi_scoreboard)

  // Single analysis implementation port
  uvm_analysis_imp #(axi_txn, axi_scoreboard) analysis_export;

  // Queues per ID
  axi_txn exp_q[int][$];   // expected queue
  axi_txn act_q[int][$];   // actual queue

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_export = new("analysis_export", this);
  endfunction


  ////////////////////////////////////////////////////////////
  // write() : STORE ONLY
  ////////////////////////////////////////////////////////////
  function void write(axi_txn tx);
    if (tx.is_expected) begin
      exp_q[tx.id].push_back(tx);
      `uvm_info("AXI_SB",
        $sformatf("Stored EXPECTED ID=%0d DATA=0x%0h", tx.id, tx.data),
        UVM_DEBUG)
    end
    else begin
      act_q[tx.id].push_back(tx);
      `uvm_info("AXI_SB",
        $sformatf("Stored ACTUAL ID=%0d DATA=0x%0h", tx.id, tx.data),
        UVM_DEBUG)
    end
  endfunction


  ////////////////////////////////////////////////////////////
  // run_phase : COMPARE WHEN BOTH QUEUES HAVE DATA
  ////////////////////////////////////////////////////////////
  task run_phase(uvm_phase phase);
    axi_txn exp_tx, act_tx;

    forever begin
      foreach (exp_q[id]) begin
        if (exp_q[id].size() > 0 &&
            act_q.exists(id) &&
            act_q[id].size() > 0) begin

          exp_tx = exp_q[id].pop_front();
          act_tx = act_q[id].pop_front();

          compare_txn(exp_tx, act_tx);
        end
      end

      // Prevent busy looping
      #1ns;
    end
  endtask


  ////////////////////////////////////////////////////////////
  // Compare logic
  ////////////////////////////////////////////////////////////
  function void compare_txn(axi_txn exp, axi_txn act);

    if (exp.data !== act.data || exp.resp !== act.resp) begin
      `uvm_error("AXI_SB",
        $sformatf(
          "MISMATCH ID=%0d | EXP:data=0x%0h resp=%0d | ACT:data=0x%0h resp=%0d",
          exp.id, exp.data, exp.resp,
          act.data, act.resp))
    end
    else begin
      `uvm_info("AXI_SB",
        $sformatf(
          "MATCH ID=%0d ADDR=0x%0h DATA=0x%0h",
          exp.id, exp.addr, exp.data),
        UVM_LOW)
    end

  endfunction

endclass

`endif

