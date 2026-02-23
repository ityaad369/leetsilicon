// Scoreboard for OOO Router

class ooo_router_sb extends uvm_scoreboard;
    uvm_component_utils(ooo_router_sb)

    // TODO: Declare structures to track input streams

    function new(string name="ooo_router_sb", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    task check_routed_packets();
        // TODO: Match output to expected input using transaction_id/tags
        // TODO: Report mismatches
    endtask
endclass

module tb_ooo_router;
    initial begin
        // TODO: Instantiate scoreboard
        // TODO: Send input transactions and verify output
        $finish;
    end
endmodule
