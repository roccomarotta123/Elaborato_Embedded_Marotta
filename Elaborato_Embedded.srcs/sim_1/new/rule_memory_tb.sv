`timescale 1ns / 1ps

module rule_memory_tb;

    
    import traffic_manager_pkg::*;
    // ======================================================================
    // PARAMETRI DEL TESTBENCH (devono corrispondere a quelli del DUT)
    // Questi verranno recuperati dal package una volta fornito.
    localparam TB_ADDR_WIDTH = RULE_ADDR_WIDTH; // e.g., 4 per NUM_RULES=16
    localparam TB_DATA_WIDTH = AXI_LITE_DATA_WIDTH; // e.g., 32
    // ======================================================================

    // Segnali per l'interfaccia del DUT
    logic clk;
    logic reset_n;

    logic                           s_write_en;
    logic [TB_ADDR_WIDTH-1:0]       s_write_rule_idx;
    logic                           s_write_word_idx;
    logic [TB_DATA_WIDTH-1:0]       s_write_data;

    logic                           s_read_en;
    logic [TB_ADDR_WIDTH-1:0]       s_read_rule_idx;
    logic                           s_read_word_idx;
    logic [TB_DATA_WIDTH-1:0]       s_read_data;

    rule_entry_t                    rules_out [NUM_RULES-1:0];

    // DICHIARAZIONE DELLE VARIABILI EXPECTED_RULE QUI FUORI DAL BLOCCO INITIAL
    rule_entry_t expected_rule_0;
    rule_entry_t expected_rule_1;
    
    logic [TB_DATA_WIDTH-1:0] read_data_w0, read_data_w1;

    // Istanza del Device Under Test (DUT)
    rule_memory #(
        .ADDR_WIDTH(TB_ADDR_WIDTH),
        .DATA_WIDTH(TB_DATA_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .s_write_en(s_write_en),
        .s_write_rule_idx(s_write_rule_idx),
        .s_write_word_idx(s_write_word_idx),
        .s_write_data(s_write_data),
        .s_read_en(s_read_en),
        .s_read_rule_idx(s_read_rule_idx),
        .s_read_word_idx(s_read_word_idx),
        .s_read_data(s_read_data),
        .rules_out(rules_out)
    );

    // ======================================================================
    // Generazione del Clock
    // ======================================================================
    localparam CLOCK_PERIOD = 10ns;
    always # (CLOCK_PERIOD / 2) clk = ~clk;

    // ======================================================================
    // Tasks per semplificare l'interazione con il DUT
    // ======================================================================

    // Task per inizializzare i segnali di input a valori sicuri
    task init_inputs;
        begin
            s_write_en <= 0;
            s_write_rule_idx <= '0;
            s_write_word_idx <= 0;
            s_write_data <= '0;

            s_read_en <= 0;
            s_read_rule_idx <= '0;
            s_read_word_idx <= 0;
        end
    endtask

    // Task per simulare una scrittura di parola
    task write_word(input int rule_idx, input int word_idx, input logic [TB_DATA_WIDTH-1:0] data);
        $display("[%0t] TB: Writing Rule %0d, Word %0d with data 0x%h", $time, rule_idx, word_idx, data);
        s_write_en <= 1;
        s_write_rule_idx <= rule_idx;
        s_write_word_idx <= word_idx;
        s_write_data <= data;
        @(posedge clk); // Aspetta un ciclo per la scrittura
        s_write_en <= 0; // Disabilita la scrittura
        s_write_rule_idx <= '0;
        s_write_word_idx <= 0;
        s_write_data <= '0;
    endtask

    // Task per simulare una lettura di parola
    task read_word(input int rule_idx, input int word_idx, output logic [TB_DATA_WIDTH-1:0] data_read);
        $display("[%0t] TB: Reading Rule %0d, Word %0d", $time, rule_idx, word_idx);
        s_read_en <= 1;
        s_read_rule_idx <= rule_idx;
        s_read_word_idx <= word_idx;
        @(posedge clk); // Aspetta un ciclo per la propagazione combinatoria
        data_read = s_read_data;
        $display("[%0t] TB: Read data 0x%h", $time, data_read);
        s_read_en <= 0; // Disabilita la lettura
        s_read_rule_idx <= '0;
        s_read_word_idx <= 0;
    endtask

    // Task per verificare una regola completa
    task verify_rule(input int rule_idx, input rule_entry_t expected_rule); // 'expected_rule' è un argomento, quindi lo vede
        $display("[%0t] TB: Verifying Rule %0d...", $time, rule_idx);
        @(posedge clk); // Give some time for combinational logic to settle
        if (rules_out[rule_idx].enable !== expected_rule.enable) begin
            $error("ERROR: Rule %0d Enable mismatch. Expected %b, Got %b", rule_idx, expected_rule.enable, rules_out[rule_idx].enable);
        end
        if (rules_out[rule_idx].symbol !== expected_rule.symbol) begin
            // $sformatf per convertire l'enum in stringa per display più chiaro
            $error("ERROR: Rule %0d Symbol mismatch. Expected %s, Got %s", rule_idx, expected_rule.symbol.name(), rules_out[rule_idx].symbol.name());
        end
        if (rules_out[rule_idx].value !== expected_rule.value) begin
            $error("ERROR: Rule %0d Value mismatch. Expected 0x%h, Got 0x%h", rule_idx, expected_rule.value, rules_out[rule_idx].value);
        end
        if (rules_out[rule_idx].addr !== expected_rule.addr) begin
            $error("ERROR: Rule %0d Addr mismatch. Expected 0x%h, Got 0x%h", rule_idx, expected_rule.addr, rules_out[rule_idx].addr);
        end
        if (rules_out[rule_idx].packet_tx_addr !== expected_rule.packet_tx_addr) begin
            $error("ERROR: Rule %0d Packet_TX_Addr mismatch. Expected 0x%h, Got 0x%h", rule_idx, expected_rule.packet_tx_addr, rules_out[rule_idx].packet_tx_addr);
        end
        if ((rules_out[rule_idx].enable === expected_rule.enable) &&
            (rules_out[rule_idx].symbol === expected_rule.symbol) &&
            (rules_out[rule_idx].value === expected_rule.value) &&
            (rules_out[rule_idx].addr === expected_rule.addr) &&
            (rules_out[rule_idx].packet_tx_addr === expected_rule.packet_tx_addr)) begin
            $display("[%0t] TB: Rule %0d verification PASSED.", $time, rule_idx);
        end else begin
            $warning("[%0t] TB: Rule %0d verification FAILED for one or more fields. Check errors above.", $time, rule_idx);
        end
    endtask


    // ======================================================================
    // Sequenza di Test Principale
    // ======================================================================
    initial begin
        // Inizializzazione
        clk = 0;
        reset_n = 0; // Attivo il reset
        init_inputs();

        $display("[%0t] TB: Starting Testbench...", $time);
        @(posedge clk);
        reset_n = 1; // Rilascio il reset
        $display("[%0t] TB: Reset Released.", $time);
        @(posedge clk);

        // ------------------------------------------------------------------
        // SCENARIO 1: Scrittura di una regola completa (Regola 0)
        // ------------------------------------------------------------------
        $display("\n[%0t] TB: --- Scenario 1: Write Rule 0 ---", $time);
        // Regola di esempio: enable=1, symbol=EQ, value=0xAB, addr=0x123, packet_tx_addr=0xDEADC0DE
        // Word 0: { (8'b0), addr[11:0], value[7:0], symbol[2:0], enable[0:0] }
        // Word 0: { 8'h0, 12'h123, 8'hAB, 3'b000, 1'b1 } -> 0x00123AB1 (per AXI_LITE_DATA_WIDTH=32)
        // Word 1: packet_tx_addr (0xDEADC0DE)
        
        // Assegna i valori alla variabile globale (ora visibile)
        expected_rule_0.enable = 1'b1;
        expected_rule_0.symbol = compare_symbol_e'('d0); // Assumendo EQ è 0
        expected_rule_0.value = 8'hAB;
        expected_rule_0.addr = 12'h123;
        expected_rule_0.packet_tx_addr = 32'hDEADC0DE; // Assumendo 32bit

        // Scrivi Word 0 della Regola 0
        write_word(0, 0, 32'h00123AB1); // Esempio per DATA_WIDTH=32
        @(posedge clk);
        // Scrivi Word 1 della Regola 0
        write_word(0, 1, 32'hDEADC0DE);
        @(posedge clk);

        // Verifica la Regola 0 in output
        verify_rule(0, expected_rule_0);
        @(posedge clk);

        // ------------------------------------------------------------------
        // SCENARIO 2: Lettura e verifica di una regola diversa (Regola 1)
        // ------------------------------------------------------------------
        $display("\n[%0t] TB: --- Scenario 2: Write and Read Rule 1 ---", $time);
        // Assegna i valori alla variabile globale (ora visibile)
        expected_rule_1.enable = 1'b0; // Esempio di regola non abilitata
        expected_rule_1.symbol = compare_symbol_e'('d1); // Assumendo GT è 1
        expected_rule_1.value = 8'hEF;
        expected_rule_1.addr = 12'hABC;
        expected_rule_1.packet_tx_addr = 32'h12345678;

        write_word(1, 0, 32'h00ABCEF2); // Esempio per DATA_WIDTH=32 (symbol=GT -> 001)
        @(posedge clk);
        write_word(1, 1, 32'h12345678);
        @(posedge clk);

        // Leggi le singole parole per verifica
        
        read_word(1, 0, read_data_w0);
        read_word(1, 1, read_data_w1);
        @(posedge clk);

        if (read_data_w0 == 32'h00ABCEF2 && read_data_w1 == 32'h12345678) begin
            $display("[%0t] TB: Single word read for Rule 1 PASSED.", $time);
        end else begin
            $error("ERROR: Single word read for Rule 1 FAILED. Expected W0: 0x%h, Got 0x%h | Expected W1: 0x%h, Got 0x%h", 32'h0ABC_EF02, read_data_w0, 32'h12345678, read_data_w1);
        end

        // Verifica l'intera Regola 1 in output
        verify_rule(1, expected_rule_1);
        @(posedge clk);
// togliere i commenti solo nel caso in cui si setta un numero di regole che non è una potenza di due altrimenti il test
// risulta superfluo
//        // ------------------------------------------------------------------
//        // SCENARIO 3: Tentativo di scrittura/lettura fuori limite
//        // ------------------------------------------------------------------
//        $display("\n[%0t] TB: --- Scenario 3: Out-of-bounds access ---", $time);
//        write_word(22, 0, 32'hFFFFFFFF); // Indice regola fuori limite
//        @(posedge clk);
//        read_word(16, 0, read_data_w0); // Indice regola fuori limite
//        @(posedge clk);

//        // Verifica che rules_out non sia influenzato da scritture out-of-bounds
//        // e che la lettura da fuori limite produca 0 (o il valore di default del design)
//        // (La logica del DUT dovrebbe impedire queste operazioni)

//        // ------------------------------------------------------------------
//        // FINE DEI TEST
//        // ------------------------------------------------------------------
//        $display("\n[%0t] TB: Testbench Finished. Stopping Simulation...", $time);
//        $stop; // Ferma la simulazione
    end

endmodule