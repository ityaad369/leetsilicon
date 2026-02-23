// Scoreboard for OOO Router
// Problem 68: 2-Input to 2-Output Router with Out-of-Order Delivery

// -----------------------------------------------------------------
// Router Transaction
// -----------------------------------------------------------------
class router_trans extends uvm_sequence_item;
    `uvm_object_utils(router_trans)

    rand int unsigned transaction_id;
    rand logic [31:0] addr;
    rand logic [31:0] data;
    int               src_port;   // 0 or 1 – which input port this came from

    function new(string name = "router_trans");
        super.new(name);
    endfunction

    // Expected output port = addr[0]
    function int expected_output_port();
        return addr[0];
    endfunction

    function string convert2string();
        return $sformatf("id=%0d addr=0x%08h data=0x%08h src_port=%0d",
                         transaction_id, addr, data, src_port);
    endfunction
endclass

// -----------------------------------------------------------------
// Scoreboard
// -----------------------------------------------------------------
class ooo_router_sb extends uvm_scoreboard;
    `uvm_component_utils(ooo_router_sb)

    // ---- Analysis Ports (inputs from monitors) ------------------
    uvm_analysis_imp_input_port0 #(router_trans, ooo_router_sb) input_port0_imp;
    uvm_analysis_imp_input_port1 #(router_trans, ooo_router_sb) input_port1_imp;
    uvm_analysis_imp_output_port0 #(router_trans, ooo_router_sb) output_port0_imp;
    uvm_analysis_imp_output_port1 #(router_trans, ooo_router_sb) output_port1_imp;

    // ---- Storage -------------------------------------------------
    // Associative array keyed on transaction_id
    router_trans expected_q[int unsigned];

    // Counters
    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;
    int unsigned extra_count    = 0;

    // ---- Constructor --------------------------------------------
    function new(string name = "ooo_router_sb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ---- Build Phase --------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        input_port0_imp  = new("input_port0_imp",  this);
        input_port1_imp  = new("input_port1_imp",  this);
        output_port0_imp = new("output_port0_imp", this);
        output_port1_imp = new("output_port1_imp", this);
    endfunction

    // ---- Input Write Callbacks ----------------------------------
    // Both inputs feed the same expected_q
    function void write_input_port0(router_trans trans);
        router_trans t;
        $cast(t, trans.clone());
        t.src_port = 0;
        if (expected_q.exists(t.transaction_id))
            `uvm_warning("SB_DUP",
                $sformatf("Duplicate transaction_id=%0d on input_port0", t.transaction_id))
        expected_q[t.transaction_id] = t;
        `uvm_info("SB_INPUT",
            $sformatf("[PORT0 IN ] %s", t.convert2string()), UVM_MEDIUM)
    endfunction

    function void write_input_port1(router_trans trans);
        router_trans t;
        $cast(t, trans.clone());
        t.src_port = 1;
        if (expected_q.exists(t.transaction_id))
            `uvm_warning("SB_DUP",
                $sformatf("Duplicate transaction_id=%0d on input_port1", t.transaction_id))
        expected_q[t.transaction_id] = t;
        `uvm_info("SB_INPUT",
            $sformatf("[PORT1 IN ] %s", t.convert2string()), UVM_MEDIUM)
    endfunction

    // ---- Output Write Callbacks ---------------------------------
    function void write_output_port0(router_trans trans);
        check_routed_packet(trans, 0);
    endfunction

    function void write_output_port1(router_trans trans);
        check_routed_packet(trans, 1);
    endfunction

    // ---- Core Matching Logic ------------------------------------
    function void check_routed_packet(router_trans out_trans, int out_port);
        int unsigned id = out_trans.transaction_id;

        // --- Extra output (no matching input) ---
        if (!expected_q.exists(id)) begin
            `uvm_error("SB_EXTRA",
                $sformatf("Output on port%0d has no matching input: id=%0d addr=0x%08h data=0x%08h",
                          out_port, id, out_trans.addr, out_trans.data))
            extra_count++;
            return;
        end

        begin
            router_trans exp = expected_q[id];
            int          expected_port = exp.expected_output_port();
            bit          port_ok = (out_port == expected_port);
            bit          data_ok = (out_trans.data == exp.data);
            bit          addr_ok = (out_trans.addr  == exp.addr);

            // --- Routing mismatch ---
            if (!port_ok) begin
                `uvm_error("SB_ROUTE_MISMATCH",
                    $sformatf("Routing mismatch id=%0d: expected_port=%0d got_port=%0d | exp: %s | got: %s",
                              id, expected_port, out_port,
                              exp.convert2string(), out_trans.convert2string()))
                mismatch_count++;
            end

            // --- Data mismatch ---
            if (!data_ok) begin
                `uvm_error("SB_DATA_MISMATCH",
                    $sformatf("Data mismatch id=%0d: expected_data=0x%08h got_data=0x%08h",
                              id, exp.data, out_trans.data))
                mismatch_count++;
            end

            // --- Address mismatch ---
            if (!addr_ok) begin
                `uvm_error("SB_ADDR_MISMATCH",
                    $sformatf("Address mismatch id=%0d: expected_addr=0x%08h got_addr=0x%08h",
                              id, exp.addr, out_trans.addr))
                mismatch_count++;
            end

            // --- All match ---
            if (port_ok && data_ok && addr_ok) begin
                `uvm_info("SB_MATCH",
                    $sformatf("MATCH id=%0d on port%0d | %s",
                              id, out_port, out_trans.convert2string()), UVM_MEDIUM)
                match_count++;
            end

            // Remove from queue (whether matched or mismatched)
            expected_q.delete(id);
        end
    endfunction

    // ---- Kept for API compatibility (called by check_phase) -----
    task check_routed_packets();
        // Delegated to check_output_phase; nothing to poll here.
    endtask

    // ---- Check Phase: detect missing outputs --------------------
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        foreach (expected_q[id]) begin
            `uvm_error("SB_MISSING",
                $sformatf("Missing output for input transaction: %s",
                          expected_q[id].convert2string()))
        end
        `uvm_info("SB_SUMMARY",
            $sformatf("Scoreboard Summary — Matches: %0d | Mismatches: %0d | Extra: %0d | Missing: %0d",
                      match_count, mismatch_count, extra_count, expected_q.num()), UVM_LOW)
    endfunction

endclass

// =================================================================
// Testbench Module (Self-Contained Directed Tests)
// =================================================================
module tb_ooo_router;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ---- Helper: build a transaction ----------------------------
    function automatic router_trans make_trans(
        int unsigned id,
        logic [31:0] addr,
        logic [31:0] data
    );
        router_trans t = new("t");
        t.transaction_id = id;
        t.addr           = addr;
        t.data           = data;
        return t;
    endfunction

    // ---- Helper: inject to scoreboard ---------------------------
    task automatic inject_input(
        ooo_router_sb sb,
        router_trans  t,
        int           port
    );
        if (port == 0) sb.write_input_port0(t);
        else           sb.write_input_port1(t);
    endtask

    task automatic inject_output(
        ooo_router_sb sb,
        router_trans  t,
        int           port
    );
        if (port == 0) sb.write_output_port0(t);
        else           sb.write_output_port1(t);
    endtask

    initial begin
        ooo_router_sb sb;
        router_trans  t;
        uvm_phase     ph = null; // dummy for check_phase

        // Construct scoreboard and manually call build_phase
        sb = new("ooo_router_sb", null);
        begin
            uvm_phase dummy;
            sb.build_phase(dummy);
        end

        $display("\n======================================================");
        $display(" TC1: Correct Routing – addr[0]=0 → output_port0");
        $display("======================================================");
        begin
            t = make_trans(10, 32'hAAA0, 32'hDEAD_0001);   // addr[0]=0 → port0
            inject_input(sb, t, 0);
            inject_output(sb, t, 0);  // correct port
        end

        $display("\n======================================================");
        $display(" TC2: Cross Routing – addr[0]=1 → output_port1");
        $display("======================================================");
        begin
            t = make_trans(20, 32'hBBB1, 32'hDEAD_0002);   // addr[0]=1 → port1
            inject_input(sb, t, 0);
            inject_output(sb, t, 1);  // correct port
        end

        $display("\n======================================================");
        $display(" TC3: Out-of-Order Outputs");
        $display("======================================================");
        begin
            router_trans i0_id1, i0_id3, i1_id2;
            i0_id1 = make_trans(1, 32'h0000_0000, 32'hAAAA_0001); // addr[0]=0 → port0
            i1_id2 = make_trans(2, 32'h0000_0001, 32'hBBBB_0002); // addr[0]=1 → port1
            i0_id3 = make_trans(3, 32'h0000_0000, 32'hCCCC_0003); // addr[0]=0 → port0

            // Inputs
            inject_input(sb, i0_id1, 0);
            inject_input(sb, i1_id2, 1);
            inject_input(sb, i0_id3, 0);

            // Outputs arrive out-of-order: id=3, id=2, id=1
            inject_output(sb, i0_id3, 0);  // id=3, port0
            inject_output(sb, i1_id2, 1);  // id=2, port1
            inject_output(sb, i0_id1, 0);  // id=1, port0
        end

        $display("\n======================================================");
        $display(" TC4: Missing Output (expect uvm_error at check_phase)");
        $display("======================================================");
        begin
            t = make_trans(99, 32'h0000_0000, 32'hDEAD_BEEF);
            inject_input(sb, t, 0);
            // Deliberately NOT sending output → will be caught in check_phase
        end

        $display("\n======================================================");
        $display(" TC5: Extra Output (no matching input)");
        $display("======================================================");
        begin
            t = make_trans(999, 32'h0000_0001, 32'hBAD_EXTRA);
            // No input injected
            inject_output(sb, t, 1);  // should trigger SB_EXTRA immediately
        end

        $display("\n======================================================");
        $display(" TC6: Wrong Port Routing Mismatch");
        $display("======================================================");
        begin
            t = make_trans(50, 32'hCCC0, 32'hDEAD_0006); // addr[0]=0 → expected port0
            inject_input(sb, t, 0);
            inject_output(sb, t, 1);  // wrong port → should trigger SB_ROUTE_MISMATCH
        end

        // ---- Trigger check_phase manually -----------------------
        $display("\n======================================================");
        $display(" CHECK PHASE (Missing output detection)");
        $display("======================================================");
        sb.check_phase(ph);

        $finish;
    end

endmodule
