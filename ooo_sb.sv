class ooo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(ooo_scoreboard)

  uvm_tlm_analysis_fifo #(my_txn) exp_fifo;
  uvm_tlm_analysis_fifo #(my_txn) act_fifo;

  my_txn exp_q[int];
  my_txn act_q[int];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_fifo = new("exp_fifo", this);
    act_fifo = new("act_fifo", this);
  endfunction

  task run_phase(uvm_phase phase);
    my_txn exp_tx;
    my_txn act_tx;

    fork
      // EXPECTED PATH
      forever begin
        exp_fifo.get(exp_tx);

        if (act_q.exists(exp_tx.id)) begin
          if (exp_tx.data !== act_q[exp_tx.id].data)
            `uvm_error("OOO_SB",
              $sformatf("ID=%0d MISMATCH exp=%0d act=%0d",
                        exp_tx.id, exp_tx.data,
                        act_q[exp_tx.id].data))
          else
            `uvm_info("OOO_SB",
              $sformatf("ID=%0d MATCH data=%0d",
                        exp_tx.id, exp_tx.data),
              UVM_LOW)

          act_q.delete(exp_tx.id);
        end
        else begin
          exp_q[exp_tx.id] = exp_tx;
        end
      end

      // ACTUAL PATH
      forever begin
        act_fifo.get(act_tx);

        if (exp_q.exists(act_tx.id)) begin
          if (exp_q[act_tx.id].data !== act_tx.data)
            `uvm_error("OOO_SB",
              $sformatf("ID=%0d MISMATCH exp=%0d act=%0d",
                        act_tx.id,
                        exp_q[act_tx.id].data,
                        act_tx.data))
          else
            `uvm_info("OOO_SB",
              $sformatf("ID=%0d MATCH data=%0d",
                        act_tx.id, act_tx.data),
              UVM_LOW)

          exp_q.delete(act_tx.id);
        end
        else begin
          act_q[act_tx.id] = act_tx;
        end
      end
    join
  endtask

  function void check_phase(uvm_phase phase);
    if (exp_q.size() || act_q.size())
      `uvm_error("OOO_SB", "Unmatched transactions remain")
  endfunction
endclass
