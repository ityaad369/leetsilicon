// Out-of-Order Scoreboard by Transaction ID

class ooo_scoreboard extends uvm_scoreboard;
    uvm_component_utils(ooo_scoreboard)

    // TODO: Declare associative arrays for expected and actual

    function new(string name="ooo_scoreboard", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    // TODO: write analysis_imp methods to collect expected/actual transactions

    task check_transactions();
        // TODO: Match transactions by transaction_id
        // TODO: Report mismatches using `uvm_error
        // TODO: Delete matched entries
    endtask
endclass

module tb_ooo_scoreboard;
    initial begin
        // TODO: Instantiate scoreboard
        // TODO: Feed transactions to scoreboard
        $finish;
    end
endmodule
