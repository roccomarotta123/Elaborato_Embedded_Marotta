// File: match_engine_tb.sv

`timescale 1ns / 1ps



module simple_match_engine_v2_tb; // Ho mantenuto il nome del tuo TB di riferimento



    // =====================================================================

    // PARAMETRI DEL TESTBENCH

    // =====================================================================

    parameter CLK_PERIOD = 10ns;; // Periodo di clock per ~100 MHz



    // =====================================================================

    // IMPORT DEL PACKAGE GLOBALE

    // =====================================================================

    import traffic_manager_pkg::*;



    // =====================================================================

    // SEGNALI DI INTERFACCIA CON IL DUT (Design Under Test)

    // =====================================================================

    logic clk;

    logic reset_n;



    logic [AXI_STREAM_DATA_WIDTH-1:0] pkt_data_in;

    logic [AXI_STREAM_KSTRB_WIDTH-1:0] pkt_kstrb_in;

    logic                                pkt_last_in;

    logic                                pkt_valid_in;

    logic                                pkt_ready_out;



    rule_entry_t rules_in [NUM_RULES-1:0]; // Array delle regole da passare al DUT



    logic [NUM_RULES-1:0]        tx_match_valid_out;

    logic [NUM_RULES-1:0][31:0] tx_packet_addr_list_out;

    logic [$clog2(NUM_RULES+1)-1:0] tx_num_matches_out;



    // Segnali per la logica AND/OR

    logic [NUM_RULES-1:0] rule_logic_mask_and_in;

    logic [NUM_RULES-1:0] rule_logic_mask_or_in;

    logic final_match_logic_enable_in;

    logic res_mask_and;

    logic [NUM_RULES-1:0] res_mask_or;



    // Segnali per la logica SOP

    logic [MAX_SOP_TERMS-1:0][NUM_RULES-1:0] sop_term_masks_in;

    logic [MAX_SOP_TERMS-1:0] sop_term_enable_in;

    logic sop_logic_enable_in;

    logic final_sop_match_out;



    // =====================================================================

    // VARIABILI TEMPORANEE PER LA COSTRUZIONE DEI BEAT

    // =====================================================================

    logic [AXI_STREAM_DATA_WIDTH-1:0] test_data_beat;

    logic [AXI_STREAM_KSTRB_WIDTH-1:0] test_kstrb_beat;

    // Configura la logica SOP: (R0 AND R1) OR (R2 AND R3) OR (R4)

    logic [MAX_SOP_TERMS-1:0][NUM_RULES-1:0] sop_masks;

    logic [MAX_SOP_TERMS-1:0] sop_enables;



    // =====================================================================

    // ISTANZIAZIONE DEL DUT

    // =====================================================================

    match_engine #(

        .PKT_DATA_WIDTH(AXI_STREAM_DATA_WIDTH),

        .PKT_KSTRB_WIDTH(AXI_STREAM_KSTRB_WIDTH)

    ) dut (

        .clk(clk),

        .reset_n(reset_n),

        .pkt_data_in(pkt_data_in),

        .pkt_kstrb_in(pkt_kstrb_in),

        .pkt_last_in(pkt_last_in),

        .pkt_valid_in(pkt_valid_in),

        .pkt_ready_out(pkt_ready_out),

        .rules_in(rules_in),

        .tx_match_valid_out(tx_match_valid_out),

        .tx_packet_addr_list_out(tx_packet_addr_list_out),

        .tx_num_matches_out(tx_num_matches_out),

        .rule_logic_mask_and_in(rule_logic_mask_and_in),

        .rule_logic_mask_or_in(rule_logic_mask_or_in),

        .final_match_logic_enable_in(final_match_logic_enable_in),

        .res_mask_and(res_mask_and),

        .res_mask_or(res_mask_or),

        .sop_term_masks_in(sop_term_masks_in),

        .sop_term_enable_in(sop_term_enable_in),

        .sop_logic_enable_in(sop_logic_enable_in),

        .final_sop_match_out(final_sop_match_out)

    );



    // =====================================================================

    // GENERAZIONE DEL CLOCK

    // =====================================================================

    always #(CLK_PERIOD/2) clk = ~clk;



    // =====================================================================

    // TASK PER INVIARE UN BEAT

    // =====================================================================

    task automatic send_single_beat(

        input logic [AXI_STREAM_DATA_WIDTH-1:0] data,

        input logic [AXI_STREAM_KSTRB_WIDTH-1:0] kstrb,

        input logic last

    );

        pkt_data_in = data;

        pkt_kstrb_in = kstrb;

        pkt_last_in = last;

        pkt_valid_in = 1'b1;

        @(posedge clk);

        while (!pkt_ready_out) begin // Attendi che il DUT sia pronto

            @(posedge clk);

        end

        pkt_valid_in = 1'b0; // Abbassa valid dopo l'handshake

    endtask



    // Task per configurare una singola regola

    task automatic set_rule(input int idx, input int addr, input byte val,

                            input compare_symbol_e sym, input logic enable, input int tx_addr);

        if (idx < NUM_RULES) begin

            rules_in[idx].addr = addr;

            rules_in[idx].value = val;

            rules_in[idx].symbol = sym;

            rules_in[idx].enable = enable;

            rules_in[idx].packet_tx_addr = tx_addr;

            $display("TIME %0t: Regola %0d configurata: Addr=%0d, Val=0x%0h, Sym=%s, Enable=%b, TxAddr=0x%0h",

                     $time, idx, addr, val, sym.name(), enable, tx_addr);

        end else begin

            $error("TIME %0t: Indice regola %0d fuori range (max %0d)", $time, idx, NUM_RULES-1);

        end

    endtask



    // Task per configurare i termini SOP

    task automatic set_sop_terms(input logic [MAX_SOP_TERMS-1:0][NUM_RULES-1:0] masks,

                                 input logic [MAX_SOP_TERMS-1:0] enables,

                                 input logic sop_enable);

        sop_term_masks_in = masks;

        sop_term_enable_in = enables;

        sop_logic_enable_in = sop_enable;

        $display("TIME %0t: Logica SOP configurata. SOP Enable: %b", $time, sop_enable);

        for (int i=0; i<MAX_SOP_TERMS; i++) begin

            if (enables[i]) begin

                $display("  Termine SOP %0d (Abilitato): Maschera = %b", i, masks[i]);

            end else begin

                $display("  Termine SOP %0d (Disabilitato): Maschera = %b", i, masks[i]);

            end

        end

    endtask



    // =====================================================================

    // SEQUENZA DI TEST PRINCIPALE

    // =====================================================================

    initial begin

        // Inizializzazione dei segnali

        clk = 1'b0;

        reset_n = 1'b0;

        pkt_data_in = '0;

        pkt_kstrb_in = '0;

        pkt_last_in = 1'b0;

        pkt_valid_in = 1'b0;

        rule_logic_mask_and_in = '0;

        rule_logic_mask_or_in = '0;

        final_match_logic_enable_in = 1'b0;

        sop_term_masks_in = '0;

        sop_term_enable_in = '0;

        sop_logic_enable_in = 1'b0;



        // Inizializza tutte le regole a disabilitate per default e indirizzi a 0

        for (int i = 0; i < NUM_RULES; i++) begin

            rules_in[i] = '{

                addr:           '0,

                value:          '0,

                symbol:         EQ,

                packet_tx_addr: '0,

                enable:         1'b0

            };

        end



        $display("----------------------------------------------");

        $display("Inizio della simulazione");

        $display("----------------------------------------------");



        // Rilascio del reset

        repeat (2) @(posedge clk);

        reset_n = 1'b1;

        $display("Reset completato.");

        @(posedge clk);



        // =================================================================

        // CONFIGURAZIONE DELLE REGOLE

        // =================================================================

        set_rule(0, 0, 8'hAA, EQ, 1'b1, 32'h100); // R0: Byte 0 == 0xAA

        set_rule(1, 1, 8'hBB, EQ, 1'b1, 32'h101); // R1: Byte 1 == 0xBB

        set_rule(2, 2, 8'hCC, EQ, 1'b1, 32'h102); // R2: Byte 2 == 0xCC

        set_rule(3, 3, 8'hDD, EQ, 1'b1, 32'h103); // R3: Byte 3 == 0xDD

        set_rule(4, 4, 8'hEE, EQ, 1'b1, 32'h104); // R4: Byte 4 == 0xEE

        set_rule(5, 5, 8'hFF, EQ, 1'b1, 32'h105); // R5: Byte 5 == 0xFF

        set_rule(6, 6, 8'h11, EQ, 1'b1, 32'h106); // R6: Byte 6 == 0x11

        set_rule(7, 7, 8'h22, EQ, 1'b1, 32'h107); // R7: Byte 7 == 0x22



        repeat (2) @(posedge clk);



        // --- Scenario 1: Test Logica AND/OR ---

        $display("\n--- SCENARIO 1: Test Logica AND/OR ---");

        // Configura la maschera AND: R0 AND R1

        rule_logic_mask_and_in = (1'b1 << 0) | (1'b1 << 1); // Maschera per R0 e R1

        // Configura la maschera OR: R2 OR R3

        rule_logic_mask_or_in = (1'b1 << 2) | (1'b1 << 3);   // Maschera per R2 e R3

        final_match_logic_enable_in = 1'b1; // Abilita la logica AND/OR

        sop_logic_enable_in = 1'b0; // Disabilita la logica SOP per questo test

        #10;



        // Pacchetto 1: R0 e R1 matchano (AND group OK), R2 e R3 matchano (OR group OK)

        // (R0 AND R1) OR (R2 OR R3) -> (True) OR (True) -> True

        $display("TIME %0t: Invio Pacchetto 1 (R0, R1, R2, R3 match) ...", $time);

        // Beat 0: Contiene AA, BB, CC, DD

        test_data_beat = '0; // Inizializza a zero

        test_data_beat[0*8 +: 8] = 8'hAA;

        test_data_beat[1*8 +: 8] = 8'hBB;

        test_data_beat[2*8 +: 8] = 8'hCC;

        test_data_beat[3*8 +: 8] = 8'hDD;

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1); // Single beat packet

        @(posedge clk); // Attendi un ciclo per la propagazione dell'output

        @(posedge clk);

        @(posedge clk);

        $display("TIME %0t: Check risultati S1-P1:", $time);

        $display("  tx_match_valid_out: %b (Atteso: ...001111)", tx_match_valid_out); // Dovrebbe essere ...001111

        $display("  res_mask_and: %b (Atteso: 1)", res_mask_and); // Atteso: 1

        $display("  res_mask_or (solo i bit rilevanti): %b (Atteso: ...001100)", res_mask_or); // Atteso: ...001100

        $display("  final_sop_match_out: %b (Atteso: 0, disabilitato)", final_sop_match_out); // Atteso: 0





        // Pacchetto 2: R0 match, R1 NON match (AND group NOT OK), R2 match (OR group OK)

        // (R0 AND R1) OR (R2 OR R3) -> (False) OR (True) -> True

        $display("TIME %0t: Invio Pacchetto 2 (R0, R2 match) ...", $time);

        test_data_beat = '0; // Inizializza a zero

        test_data_beat[0*8 +: 8] = 8'hAA;

        test_data_beat[2*8 +: 8] = 8'hCC;

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1);

        @(posedge clk);

        @(posedge clk);

        @(posedge clk);

        $display("TIME %0t: Check risultati S1-P2:", $time);

        $display("  tx_match_valid_out: %b (Atteso: ...000101)", tx_match_valid_out); // Dovrebbe essere ...000101

        $display("  res_mask_and: %b (Atteso: 0)", res_mask_and); // Atteso: 0

        $display("  res_mask_or (solo i bit rilevanti): %b (Atteso: ...000100)", res_mask_or); // Atteso: ...000100

        $display("  final_sop_match_out: %b (Atteso: 0, disabilitato)", final_sop_match_out); // Atteso: 0

        #20;



        // Pacchetto 3: Nessun match per AND/OR group

        // (R0 AND R1) OR (R2 OR R3) -> (False) OR (False) -> False

        $display("TIME %0t: Invio Pacchetto 3 (Nessun match rilevante) ...", $time);

        test_data_beat = '0; // Inizializza a zero

        test_kstrb_beat = '0; // Kstrb a zero per indicare nessun byte valido

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1); // Pacchetto vuoto o non rilevante

        @(posedge clk);

        @(posedge clk);

        @(posedge clk);

        $display("TIME %0t: Check risultati S1-P3:", $time);

        $display("  tx_match_valid_out: %b (Atteso: 0)", tx_match_valid_out); // Dovrebbe essere 0

        $display("  res_mask_and: %b (Atteso: 0)", res_mask_and); // Atteso: 0

        $display("  res_mask_or (solo i bit rilevanti): %b (Atteso: 0)", res_mask_or); // Atteso: 0

        $display("  final_sop_match_out: %b (Atteso: 0, disabilitato)", final_sop_match_out); // Atteso: 0

        #20;



        // --- Scenario 2: Test Logica SOP ---

        $display("\n--- SCENARIO 2: Test Logica SOP ---");

        // Disabilita la logica AND/OR esistente

        final_match_logic_enable_in = 1'b0;



        sop_masks = '0;

        sop_enables = '0;



        // Termine 0: R0 AND R1

        sop_masks[0] = (1'b1 << 0) | (1'b1 << 1);

        sop_enables[0] = 1'b1;



        // Termine 1: R2 AND R3

        sop_masks[1] = (1'b1 << 2) | (1'b1 << 3);

        sop_enables[1] = 1'b1;



        // Termine 2: R4

        sop_masks[2] = (1'b1 << 4);

        sop_enables[2] = 1'b1;



        set_sop_terms(sop_masks, sop_enables, 1'b1); // Abilita la logica SOP

        #10;



        // Pacchetto 4: R0, R1, R2, R3, R4 matchano

        // SOP: (R0 AND R1) OR (R2 AND R3) OR (R4) -> (True) OR (True) OR (True) -> True

        $display("TIME %0t: Invio Pacchetto 4 (R0, R1, R2, R3, R4 match) ...", $time);

        test_data_beat = '0; // Inizializza a zero

        test_data_beat[0*8 +: 8] = 8'hAA;

        test_data_beat[1*8 +: 8] = 8'hBB;

        test_data_beat[2*8 +: 8] = 8'hCC;

        test_data_beat[3*8 +: 8] = 8'hDD;

        test_data_beat[4*8 +: 8] = 8'hEE;

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1);

        @(posedge clk);

        @(posedge clk);

        @(posedge clk);

        $display("TIME %0t: Check risultati S2-P4:", $time);

        $display("  tx_match_valid_out: %b (Atteso: ...011111)", tx_match_valid_out); // Dovrebbe essere ...011111

        $display("  final_sop_match_out: %b (Atteso: 1)", final_sop_match_out); // Atteso: 1

        #20;



        // Pacchetto 5: R0 match, R1 NO match, R2 match, R3 NO match, R4 match

        // SOP: (R0 AND R1) OR (R2 AND R3) OR (R4) -> (False) OR (False) OR (True) -> True

        $display("TIME %0t: Invio Pacchetto 5 (R0, R2, R4 match) ...", $time);

        test_data_beat = '0; // Inizializza a zero

        test_data_beat[0*8 +: 8] = 8'hAA;

        test_data_beat[2*8 +: 8] = 8'hCC;

        test_data_beat[4*8 +: 8] = 8'hEE;

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1);

        @(posedge clk);

        @(posedge clk);

        @(posedge clk);

        $display("TIME %0t: Check risultati S2-P5:", $time);

        $display("  tx_match_valid_out: %b (Atteso: ...010101)", tx_match_valid_out); // Dovrebbe essere ...010101

        $display("  final_sop_match_out: %b (Atteso: 1)", final_sop_match_out); // Atteso: 1

        #20;



        // Pacchetto 6: R0 match, R1, R2, R3, R4 NO match

        // SOP: (R0 AND R1) OR (R2 AND R3) OR (R4) -> (False) OR (False) OR (False) -> False

        $display("TIME %0t: Invio Pacchetto 6 (Solo R0 match) ...", $time);

        test_data_beat = '0; // Inizializza a zero

        test_data_beat[0*8 +: 8] = 8'hAA;

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1);

        @(posedge clk);

        @(posedge clk);

        @(posedge clk);

        $display("TIME %0t: Check risultati S2-P6:", $time);

        $display("  tx_match_valid_out: %b (Atteso: ...000001)", tx_match_valid_out); // Dovrebbe essere ...000001

        $display("  final_sop_match_out: %b (Atteso: 0)", final_sop_match_out); // Atteso: 0

        #20;



        // --- Scenario 3: Disabilita Logica SOP ---

        $display("\n--- SCENARIO 3: Disabilita Logica SOP ---");

        set_sop_terms('0, '0, 1'b0); // Disabilita tutti i termini SOP e la logica SOP

        #10;



        // Pacchetto 7: Nonostante i match, SOP dovrebbe essere 0

        $display("TIME %0t: Invio Pacchetto 7 (R0, R1, R2, R3, R4 match) ...", $time);

        test_data_beat = '0; // Inizializza a zero

        test_data_beat[0*8 +: 8] = 8'hAA;

        test_data_beat[1*8 +: 8] = 8'hBB;

        test_data_beat[2*8 +: 8] = 8'hCC;

        test_data_beat[3*8 +: 8] = 8'hDD;

        test_data_beat[4*8 +: 8] = 8'hEE;

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1);

        @(posedge clk);

        @(posedge clk);

        @(posedge clk);

        $display("TIME %0t: Check risultati S3-P7:", $time);

        $display("  tx_match_valid_out: %b (Atteso: ...011111)", tx_match_valid_out); // Dovrebbe essere ...011111

        $display("  final_sop_match_out: %b (Atteso: 0)", final_sop_match_out); // Atteso: 0

        #20;



        $display("\nSimulazione completata.");

        $finish;

    end



    // Visualizzazione delle transizioni di stato FSM (Opzionale, richiede che il DUT esponga lo stato)

    // initial begin

    //     $monitor("TIME %0t: State: %s, pkt_valid_in=%b, pkt_ready_out=%b, r_pkt_last=%b, current_beat_start_byte_offset=%0d",

    //              $time, dut.current_state.name(), pkt_valid_in, pkt_ready_out, dut.r_pkt_last, dut.current_beat_start_byte_offset);

    // end



endmodule