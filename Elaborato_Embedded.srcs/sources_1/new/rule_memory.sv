`timescale 1ns / 1ps 

import traffic_manager_pkg::*;

module rule_memory #(
    // Questi parametri ora definiscono solo le dimensioni delle interfacce interne
    // del modulo, non i dettagli AXI.
    parameter ADDR_WIDTH = RULE_ADDR_WIDTH, // Larghezza per selezionare una regola
    parameter DATA_WIDTH = AXI_LITE_DATA_WIDTH // Larghezza dei dati per ogni parola di regola
) (
    input logic clk,
    input logic reset_n,

    // Interfaccia semplificata per la scrittura delle regole (dal wrapper AXI esterno)
    input logic                 s_write_en,        // Abilitazione alla scrittura
    input logic [ADDR_WIDTH-1:0] s_write_rule_idx, // Indice della regola da scrivere
    input logic                 s_write_word_idx,  // Indice della parola (0 per Word 0, 1 per Word 1)
    input logic [DATA_WIDTH-1:0] s_write_data,      // Dati da scrivere

    // Interfaccia semplificata per la lettura delle regole (dal wrapper AXI esterno)
    input logic                 s_read_en,         // Abilitazione alla lettura
    input logic [ADDR_WIDTH-1:0] s_read_rule_idx,  // Indice della regola da leggere
    input logic                 s_read_word_idx,   // Indice della parola (0 per Word 0, 1 per Word 1)
    output logic [DATA_WIDTH-1:0] s_read_data,       // Dati letti

    // Output delle regole intere per il Match Engine
    output rule_entry_t rules_out [NUM_RULES-1:0]
);

    // Memoria interna per memorizzare le regole.
    // Ogni 'rule_entry_t' (56 bit) è memorizzata come 2 parole a 'DATA_WIDTH' bit.
    logic [DATA_WIDTH-1:0] rules_internal_mem [NUM_RULES-1:0][1:0];

    // Logica di scrittura nella memoria interna
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (int i = 0; i < NUM_RULES; i++) begin
                rules_internal_mem[i][0] <= '0;
                rules_internal_mem[i][1] <= '0;
            end
        end else begin
            if (s_write_en) begin
           
           
                if (s_write_rule_idx < NUM_RULES) begin
                    rules_internal_mem[s_write_rule_idx][s_write_word_idx] <= s_write_data;
                end
            end
        end
    end

    // Logica di lettura dalla memoria interna (combinatoria per accesso immediato)
    assign s_read_data = (s_read_en && (s_read_rule_idx < NUM_RULES)) ?
                         rules_internal_mem[s_read_rule_idx][s_read_word_idx] : '0;

    // =====================================================================
    // LOGICA DI PACKING/UNPACKING PER rules_out
    // Converte le parole interne (rules_internal_mem) nella struttura 'rule_entry_t'
    // per l'utilizzo da parte del Match Engine.
    // Questa logica rimane invariata, in quanto è la parte funzionale del modulo.
    // =====================================================================
    always_comb begin
        for (int i = 0; i < NUM_RULES; i++) begin
            // Unpacking della Word 0 nei campi della rule_entry_t
            // Mappatura: { (8'b0), addr[11:0], value[7:0], symbol[2:0], enable[0:0] }
            rules_out[i].enable = rules_internal_mem[i][0][0];
            rules_out[i].symbol = compare_symbol_e'(rules_internal_mem[i][0][3:1]);
            rules_out[i].value  = rules_internal_mem[i][0][11:4];
            rules_out[i].addr   = rules_internal_mem[i][0][23:12];

            // Unpacking della Word 1 nel campo 'packet_tx_addr'
            rules_out[i].packet_tx_addr = rules_internal_mem[i][1];
        end
    end

endmodule