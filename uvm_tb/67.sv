// Out-of-Order Scoreboard by Transaction ID

// ─────────────────────────────────────────────────────────────
// Transaction class
// ─────────────────────────────────────────────────────────────
class ooo_transaction extends uvm_sequence_item;
    `uvm_object_utils(ooo_transaction)

    rand int unsigned transaction_id;   // unique key used for matching
    rand int unsigned data;             // payload field compared on match
    rand int unsigned addr;             // additional payload field

    function new(string name = "ooo_transaction");
        super.new(name);
    endfunction

    // Deep-copy compare used by the scoreboard
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        ooo_transaction rhs_t;
        if (!$cast(rhs_t, rhs)) return 0;
        return (data == rhs_t.data) && (addr == rhs_t.addr);
    endfunction

    virtual function string convert2string();
        return $sformatf("id=%0d data=0x%0h addr=0x%0h",
                         transaction_id, data, addr);
    endfunction
endclass

// ─────────────────────────────────────────────────────────────
// Analysis-imp macros need a unique suffix per port.
// Declare them BEFORE the class body.
// ─────────────────────────────────────────────────────────────
`uvm_analysis_imp_decl(_expected)
`uvm_analysis_imp_decl(_actual)

// ─────────────────────────────────────────────────────────────
// Out-of-Order Scoreboard
// ─────────────────────────────────────────────────────────────
class ooo_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(ooo_scoreboard)

    // ── Analysis ports ──────────────────────────────────────
    uvm_analysis_imp_expected #(ooo_transaction, ooo_scoreboard) imp_expected;
    uvm_analysis_imp_actual   #(ooo_transaction, ooo_scoreboard) imp_actual;

    // ── Storage: associative arrays keyed by transaction_id ─
    ooo_transaction expected_q[int unsigned];
    ooo_transaction actual_q  [int unsigned];

    // ── Counters for reporting ───────────────────────────────
    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    // ── Constructor ─────────────────────────────────────────
    function new(string name = "ooo_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ── Build phase: create ports ────────────────────────────
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp_expected = new("imp_expected", this);
        imp_actual   = new("imp_actual",   this);
    endfunction

    // ════════════════════════════════════════════════════════
    // write_expected – called when predictor sends a transaction
    // ════════════════════════════════════════════════════════
    virtual function void write_expected(ooo_transaction trans);
        int unsigned tid = trans.transaction_id;

        `uvm_info("SCB_EXP",
            $sformatf("Received EXPECTED: %s", trans.convert2string()), UVM_HIGH)

        // ── Duplicate expected ID ────────────────────────────
        if (expected_q.exists(tid)) begin
            `uvm_error("DUPLICATE_EXP",
                $sformatf("Duplicate expected transaction_id=%0d. Overwriting.", tid))
        end

        // ── Actual already waiting? → compare immediately ───
        if (actual_q.exists(tid)) begin
            compare_transactions(trans, actual_q[tid]);
            actual_q.delete(tid);
        end else begin
            // Park in expected queue until actual arrives
            expected_q[tid] = trans;
        end
    endfunction

    // ════════════════════════════════════════════════════════
    // write_actual – called when monitor captures a response
    // ════════════════════════════════════════════════════════
    virtual function void write_actual(ooo_transaction trans);
        int unsigned tid = trans.transaction_id;

        `uvm_info("SCB_ACT",
            $sformatf("Received ACTUAL: %s", trans.convert2string()), UVM_HIGH)

        // ── Duplicate actual ID ──────────────────────────────
        if (actual_q.exists(tid)) begin
            `uvm_error("DUPLICATE_ACT",
                $sformatf("Duplicate actual transaction_id=%0d. Overwriting.", tid))
        end

        // ── Expected already waiting? → compare immediately ─
        if (expected_q.exists(tid)) begin
            compare_transactions(expected_q[tid], trans);
            expected_q.delete(tid);
        end else begin
            // Park in actual queue until expected arrives
            actual_q[tid] = trans;
        end
    endfunction

    // ════════════════════════════════════════════════════════
    // compare_transactions – field-by-field comparison
    // ════════════════════════════════════════════════════════
    protected function void compare_transactions(
        ooo_transaction exp_t,
        ooo_transaction act_t
    );
        if (exp_t.do_compare(act_t, null)) begin
            match_count++;
            `uvm_info("SCB_MATCH",
                $sformatf("MATCH  id=%0d | exp: %s | act: %s",
                    exp_t.transaction_id,
                    exp_t.convert2string(),
                    act_t.convert2string()), UVM_MEDIUM)
        end else begin
            mismatch_count++;
            `uvm_error("MISMATCH",
                $sformatf("MISMATCH id=%0d | exp: %s | act: %s",
                    exp_t.transaction_id,
                    exp_t.convert2string(),
                    act_t.convert2string()))
        end
    endfunction

    // ═══════════════════════════════════════════════════��════
    // check_transactions – can be called mid-test if desired
    // ════════════════════════════════════════════════════════
    task check_transactions();
        // Iterate over any transactions that arrived out-of-order
        // and may now be matchable (useful if called periodically).
        // Because matching happens eagerly in write_*, this task
        // primarily serves as an explicit sweep / hook point.
        foreach (expected_q[tid]) begin
            if (actual_q.exists(tid)) begin
                compare_transactions(expected_q[tid], actual_q[tid]);
                expected_q.delete(tid);
                actual_q.delete(tid);
            end
        end
    endtask

    // ════════════════════════════════════════════════════════
    // check_phase – end-of-test unmatched transaction audit
    // ════════════════════════════════════════════════════════
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        // Run any remaining sweep
        foreach (expected_q[tid]) begin
            if (actual_q.exists(tid)) begin
                compare_transactions(expected_q[tid], actual_q[tid]);
                expected_q.delete(tid);
                actual_q.delete(tid);
            end
        end

        // Report orphaned expected transactions
        if (expected_q.size() != 0) begin
            foreach (expected_q[tid]) begin
                `uvm_error("UNMATCHED_EXP",
                    $sformatf("Unmatched EXPECTED transaction: %s",
                        expected_q[tid].convert2string()))
            end
        end

        // Report orphaned actual transactions
        if (actual_q.size() != 0) begin
            foreach (actual_q[tid]) begin
                `uvm_error("UNMATCHED_ACT",
                    $sformatf("Unmatched ACTUAL transaction: %s",
                        actual_q[tid].convert2string()))
            end
        end

        `uvm_info("SCB_SUMMARY",
            $sformatf("Scoreboard Summary: matches=%0d mismatches=%0d unmatched_exp=%0d unmatched_act=%0d",
                match_count, mismatch_count,
                expected_q.size(), actual_q.size()), UVM_LOW)
    endfunction

endclass

// ─────────────────────────────────────────────────────────────
// Helper: build a transaction with given id / data / addr
// ─────────────────────────────────────────────────────────────
function automatic ooo_transaction make_trans(
    int unsigned id,
    int unsigned data,
    int unsigned addr
);
    ooo_transaction t = new("t");
    t.transaction_id = id;
    t.data           = data;
    t.addr           = addr;
    return t;
endfunction

// ─────────────────────────────────────────────────────────────
// Testbench module – exercises all 6 test cases
// ─────────────────────────────────────────────────────────────
module tb_ooo_scoreboard;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ── Instantiate scoreboard directly (no full UVM env needed) ──
    ooo_scoreboard scb;

    initial begin
        uvm_top.finish_on_completion = 0;   // we call $finish manually

        // Build the scoreboard
        scb = ooo_scoreboard::type_id::create("scb", null);
        uvm_top.run_test("");   // triggers build_phase automatically
                                // (works in standalone sim; adapt for full env)

        // ══════════════════════════════════════════════════
        // Test Case 1 – In-Order Match
        // Expected arrives first, then actual with same ID.
        // ══════════════════════════════════════════════════
        $display("\n=== TC1: In-Order Match ===");
        begin
            ooo_transaction e1 = make_trans(10, 32'hAABB, 32'h0100);
            ooo_transaction a1 = make_trans(10, 32'hAABB, 32'h0100);
            scb.write_expected(e1);
            scb.write_actual(a1);
            // Both queues must be empty after match
            assert(scb.expected_q.size() == 0 && scb.actual_q.size() == 0)
                else $error("TC1 FAIL: queues not empty after match");
            $display("TC1 PASS: matched in-order id=10");
        end

        // ══════════════════════════════════════════════════
        // Test Case 2 – Out-of-Order (Actual First)
        // Actual stored, then expected triggers match.
        // ══════════════════════════════════════════════════
        $display("\n=== TC2: Out-of-Order (Actual First) ===");
        begin
            ooo_transaction a2 = make_trans(20, 32'hCAFE, 32'h0200);
            ooo_transaction e2 = make_trans(20, 32'hCAFE, 32'h0200);
            scb.write_actual(a2);
            assert(scb.actual_q.size() == 1)
                else $error("TC2 FAIL: actual_q should hold 1 entry");
            scb.write_expected(e2);
            assert(scb.expected_q.size() == 0 && scb.actual_q.size() == 0)
                else $error("TC2 FAIL: queues not empty after match");
            $display("TC2 PASS: matched out-of-order id=20");
        end

        // ══════════════════════════════════════════════════
        // Test Case 3 – Multiple Transactions (mixed ordering)
        // Arrival: E1, A2, E3, A1, E2, A3  (IDs 1,2,3)
        // ══════════════════════════════════════════════════
        $display("\n=== TC3: Multiple Transactions Mixed Order ===");
        begin
            // All transactions carry matching payload
            ooo_transaction e_t1 = make_trans(1, 32'h0001, 32'hA001);
            ooo_transaction e_t2 = make_trans(2, 32'h0002, 32'hA002);
            ooo_transaction e_t3 = make_trans(3, 32'h0003, 32'hA003);
            ooo_transaction a_t1 = make_trans(1, 32'h0001, 32'hA001);
            ooo_transaction a_t2 = make_trans(2, 32'h0002, 32'hA002);
            ooo_transaction a_t3 = make_trans(3, 32'h0003, 32'hA003);

            scb.write_expected(e_t1);   // E1 – parked in expected_q
            scb.write_actual(a_t2);     // A2 – parked in actual_q
            scb.write_expected(e_t3);   // E3 – parked in expected_q
            scb.write_actual(a_t1);     // A1 – matches E1 → cleared
            scb.write_expected(e_t2);   // E2 – matches A2 → cleared
            scb.write_actual(a_t3);     // A3 – matches E3 → cleared

            assert(scb.expected_q.size() == 0 && scb.actual_q.size() == 0)
                else $error("TC3 FAIL: queues not empty after all matches");
            $display("TC3 PASS: all 3 transactions matched correctly");
        end

        // ══════════════════════════════════════════════════
        // Test Case 4 – Mismatch Detection
        // Same ID, different data → `uvm_error expected.
        // ══════════════════════════════════════════════════
        $display("\n=== TC4: Mismatch Detection ===");
        begin
            ooo_transaction e4 = make_trans(40, 32'h1111, 32'hF000);
            ooo_transaction a4 = make_trans(40, 32'h2222, 32'hF000); // data differs
            scb.write_expected(e4);
            scb.write_actual(a4);   // triggers MISMATCH uvm_error
            assert(scb.mismatch_count > 0)
                else $error("TC4 FAIL: mismatch_count should be > 0");
            $display("TC4 PASS: mismatch detected for id=40 (uvm_error issued above)");
        end

        // ══════════════════════════════════════════════════
        // Test Case 5 – Missing Transaction (orphan)
        // Expected never gets a matching actual.
        // Verified via check_phase at end.
        // ══════════════════════════════════════════════════
        $display("\n=== TC5: Missing Actual (orphan expected) ===");
        begin
            ooo_transaction e5 = make_trans(50, 32'hDEAD, 32'h5000);
            scb.write_expected(e5); // actual never arrives
            $display("TC5: orphan expected id=50 queued – uvm_error fires in check_phase");
        end

        // ══════════════════════════════════════════════════
        // Test Case 6 – Duplicate Transaction ID
        // Same transaction_id sent twice on expected port.
        // ══════════════════════════════════════════════════
        $display("\n=== TC6: Duplicate Transaction ID ===");
        begin
            ooo_transaction e6a = make_trans(60, 32'hBEEF, 32'h6000);
            ooo_transaction e6b = make_trans(60, 32'hFACE, 32'h6000); // duplicate id
            scb.write_expected(e6a);
            scb.write_expected(e6b); // triggers DUPLICATE_EXP uvm_error, overwrites
            $display("TC6: duplicate id=60 handled (uvm_error issued above)");
            // Clean up so check_phase only complains about TC5 orphan
            begin
                ooo_transaction a6 = make_trans(60, 32'hFACE, 32'h6000);
                scb.write_actual(a6);
            end
        end

        // ── Trigger end-of-test audit ──────────────────────
        $display("\n=== check_phase audit ===");
        begin
            uvm_phase dummy_phase; // placeholder; check_phase logic runs inline
            scb.check_phase(dummy_phase);
        end

        $display("\n=== Testbench Complete ===");
        $finish;
    end

endmodule
