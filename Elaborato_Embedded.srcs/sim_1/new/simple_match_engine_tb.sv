// File: match_engine_tb.sv
`timescale 1ns / 1ps 

module simple_match_engine_tb;

    // =====================================================================
    // PARAMETRI DEL TESTBENCH
    // =====================================================================
    parameter CLK_PERIOD = 10ns; // Periodo di clock per 100 MHz (10ns)

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

    logic [NUM_RULES-1:0]      tx_match_valid_out;
    logic [NUM_RULES-1:0][31:0] tx_packet_addr_list_out;
    logic [$clog2(NUM_RULES+1)-1:0] tx_num_matches_out;

    // =====================================================================
    // VARIABILI TEMPORANEE PER LA COSTRUZIONE DEI BEAT
    // =====================================================================
    logic [AXI_STREAM_DATA_WIDTH-1:0] test_data_beat;
    logic [AXI_STREAM_KSTRB_WIDTH-1:0] test_kstrb_beat;

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
        .tx_num_matches_out(tx_num_matches_out)
    );

    // =====================================================================
    // GENERAZIONE DEL CLOCK
    // =====================================================================
    always #(CLK_PERIOD/2) clk = ~clk;

    // =====================================================================
    // TASK PER INVIARE UN BEAT 
    // =====================================================================
    task send_single_beat(
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

        // Inizializza tutte le regole a disabilitate per default e indirizzi a 0
        for (int i = 0; i < NUM_RULES; i++) begin
            rules_in[i] = '{
                addr:         '0,
                value:        '0,
                symbol:       EQ,
                packet_tx_addr: '0,
                enable:       1'b0
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
        // Regola 0: Cerca byte 0xAA all'indirizzo 10 (primo beat)
        // Questo dovrebbe matchare nel primo beat
        rules_in[0] = '{
            addr:         10, // Indirizzo 10 del pacchetto
            value:        8'hAA,
            symbol:       EQ,
            packet_tx_addr: 32'h1000_0001,
            enable:       1'b1
        };
        $display("Regola 0 configurata: Cerca 0xAA all'indirizzo 10, TX_ADDR=0x10000001.");

        // Regola 1: Cerca byte 0xBB all'indirizzo 20 (primo beat)
        // Questo non dovrebbe matchare nel nostro esempio di dati
        rules_in[1] = '{
            addr:         20, // Indirizzo 20 del pacchetto (sempre nel primo beat)
            value:        8'hBB,
            symbol:       EQ,
            packet_tx_addr: 32'h1000_0002,
            enable:       1'b1
        };
        $display("Regola 1 configurata: Cerca 0xBB all'indirizzo 20, TX_ADDR=0x10000002.");

        // Regola 2: Cerca byte 0xCC all'indirizzo 70 (secondo beat)
        // Assumendo PKT_KSTRB_WIDTH = 64 (512/8), il secondo beat inizia a offset 64.
        // L'indirizzo 70 è nell'offset 6 (70-64) del secondo beat.
        // Questo dovrebbe matchare nel secondo beat del primo e del secondo pacchetto
        rules_in[2] = '{
            addr:         70, // Indirizzo 70 del pacchetto (offset 6 nel secondo beat)
            value:        8'hCC,
            symbol:       EQ,
            packet_tx_addr: 32'h2000_0003,
            enable:       1'b1
        };
        $display("Regola 2 configurata: Cerca 0xCC all'indirizzo 70, TX_ADDR=0x20000003.");

        repeat (2) @(posedge clk); 

        // =================================================================
        // SCENARIO 1: Pacchetto con 2 beat
        // =================================================================
        $display("----------------------------------------------");
        $display("Invio Pacchetto 1 (2 beat)");
        $display("----------------------------------------------");

        // --- Beat 0 (primo beat del pacchetto) ---
        // Dati: 0xAA al byte 10
        // kstrb: tutti validi
        test_data_beat = '0; // Inizializza tutti i 512 bit a 0
        test_data_beat[10*8 +: 8] = 8'hAA; // Imposta il byte 10 a 0xAA
        test_data_beat[20*8 +: 8] = 8'h11; // Imposta il byte 20 a 0x11 (per non matchare con Regola 1)

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}}; // Tutti i bit a 1 (tutti i byte validi)

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b0); // Non è l'ultimo beat
        $display("Inviato Beat 0.");
        @(posedge clk); // Un ciclo per lasciare che il match_engine processi

        // --- Beat 1 (secondo e ultimo beat del pacchetto) ---
        // Dati: 0xCC al byte 6 (relativo a questo beat, che è indirizzo 70 globale)
        // kstrb: tutti validi
        test_data_beat = '0; // Inizializza tutti i 512 bit a 0
        // L'indirizzo 70 è PKT_KSTRB_WIDTH (64) + 6. Quindi il byte 6 di questo beat.
        test_data_beat[6*8 +: 8] = 8'hCC; // Imposta il byte 6 di questo beat a 0xCC

        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}}; // Tutti i bit a 1 (tutti i byte validi)

        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1); // È l'ultimo beat
        $display("Inviato Beat 1 (ultimo beat).");
        @(posedge clk); // Un ciclo per lasciare che il match_engine processi

//        // Aspetta che il match_engine vada in STATE_REPORT_MATCH e poi torni in IDLE
//        // Il risultato è valido per 1 ciclo (in STATE_REPORT_MATCH)
        @(posedge clk); 
        $display("----------------------------------------------");
        $display("Risultati Pacchetto 1:");
        $display("tx_num_matches_out = %0d", tx_num_matches_out);
        for (int i = 0; i < NUM_RULES; i++) begin
            if (tx_match_valid_out[i]) begin
                $display("  Regola %0d: Match trovato! Packet TX Addr: 0x%H", i, tx_packet_addr_list_out[i]);
            end else begin
                $display("  Regola %0d: Nessun match.", i);
            end
        end
        $display("----------------------------------------------");
        @(posedge clk); // Attendiamo il ciclo in cui il match_engine torna in IDLE

        // =================================================================
        // SCENARIO 2: Pacchetto con match solo nell'ultimo beat
        // =================================================================
        $display("\n----------------------------------------------");
        $display("Invio Pacchetto 2 (2 beat, match all'interno dell'ultimo beat con regola 2)");
        $display("----------------------------------------------");

        // --- Beat 0 ---
        test_data_beat = '0;
        test_data_beat[10*8 +: 8] = 8'hFF; // Nessun match per Regola 0
        test_data_beat[20*8 +: 8] = 8'hEE; // Nessun match per Regola 1
        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};
        send_single_beat(test_data_beat, test_kstrb_beat, 1'b0);
        $display("Inviato Beat 0.");
        @(posedge clk);

        // --- Beat 1 ---
        test_data_beat = '0;
        test_data_beat[6*8 +: 8] = 8'hCC;
        test_kstrb_beat = {AXI_STREAM_KSTRB_WIDTH{1'b1}};
        send_single_beat(test_data_beat, test_kstrb_beat, 1'b1);
        $display("Inviato Beat 1 (ultimo beat).");
        @(posedge clk);
        
        @(posedge clk);
        $display("----------------------------------------------");
        $display("Risultati Pacchetto 2:");
        $display("tx_num_matches_out = %0d", tx_num_matches_out);
        for (int i = 0; i < NUM_RULES; i++) begin
            if (tx_match_valid_out[i]) begin
                $display("  Regola %0d: Match trovato! Packet TX Addr: 0x%H", i, tx_packet_addr_list_out[i]);
             end else begin
                $display("  Regola %0d: Nessun match.", i);
            end
        end
        $display("----------------------------------------------");
        @(posedge clk);

        $display("Simulazione completata.");
        $finish; // Termina la simulazione
    end

endmodule