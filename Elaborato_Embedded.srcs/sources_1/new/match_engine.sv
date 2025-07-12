// File: match_engine.sv

`timescale 1ns / 1ps // Definizione della risoluzione temporale (1ns per unità di tempo, 1ps per precisione)

import traffic_manager_pkg::*; // Importa il package con i parametri e i tipi di dati globali

module match_engine #(
    parameter PKT_DATA_WIDTH = AXI_STREAM_DATA_WIDTH,
    parameter PKT_KSTRB_WIDTH = AXI_STREAM_KSTRB_WIDTH
) (
    input logic clk,
    input logic reset_n,

    input logic [PKT_DATA_WIDTH-1:0] pkt_data_in,
    input logic [PKT_KSTRB_WIDTH-1:0] pkt_kstrb_in,
    input logic                        pkt_last_in,
    input logic                        pkt_valid_in,
    output logic                       pkt_ready_out,

    input rule_entry_t rules_in [NUM_RULES-1:0],

    // Nuove uscite per match multipli
    output logic [NUM_RULES-1:0]      tx_match_valid_out,      // Vettore di validità: tx_match_valid_out[i] è alto se rules_in[i] ha matchato
    output logic [NUM_RULES-1:0][31:0] tx_packet_addr_list_out, // Array degli indirizzi delle regole
    output logic [$clog2(NUM_RULES+1)-1:0] tx_num_matches_out       // Contatore del numero di match trovati
);

    // =====================================================================
    // PARAMETRI LOCALI
    // =====================================================================
    localparam IDX_WIDTH = $clog2(NUM_RULES + 1); // Larghezza necessaria per contare fino a NUM_RULES match

    // =====================================================================
    // TIPI DI DATO LOCALI (per la FSM)
    // =====================================================================
    typedef enum logic [1:0] {
        STATE_IDLE,         // Attesa di un nuovo pacchetto
        STATE_PROCESSING,   // Elaborazione di tutti i beat del pacchetto
        STATE_WAIT_ACC,     // Aggiornamento registri di accumulo
        STATE_REPORT_MATCH  // Segnalazione dei match finali dopo l'elaborazione completa del pacchetto
    } fsm_state_e;

    // =====================================================================
    // SEGNALI INTERNI REGISTRATI (Sincroni)
    // =====================================================================
    fsm_state_e current_state, next_state;

    logic [PKT_DATA_WIDTH-1:0] r_pkt_data;
    logic [PKT_KSTRB_WIDTH-1:0] r_pkt_kstrb;
    logic                        r_pkt_last;

    // L'offset del primo byte del beat corrente all'interno del pacchetto
    logic [$clog2(PACKET_MAX_SIZE)-1:0] current_beat_start_byte_offset;

    // Registri per accumulare i match trovati su tutti i beat del pacchetto
    // Dato che ogni regola matcha al massimo una volta per pacchetto,
    // questi registri sono direttamente gli accumuli finali.
    logic [NUM_RULES-1:0]      accum_match_valid_reg;
    logic [NUM_RULES-1:0][31:0] accum_packet_addr_list_reg;

    // Registri per gli output finali (validi solo in STATE_REPORT_MATCH)
    // Saranno semplicemente copie degli accumuli in STATE_REPORT_MATCH
    logic [NUM_RULES-1:0]      tx_match_valid_reg;
    logic [NUM_RULES-1:0][31:0] tx_packet_addr_list_reg;
    logic [IDX_WIDTH-1:0]      tx_num_matches_reg; // Calcolato dai match validi

    // =====================================================================
    // SEGNALI INTERNI COMBINATORI (Asincroni)
    // =====================================================================
    // Questi sono i match trovati nel *beat corrente* (combinatorio)
    logic [NUM_RULES-1:0] match_found_per_rule_comb;
    logic [NUM_RULES-1:0][31:0] matched_tx_addr_per_rule_comb;
    // total_match_found_in_beat_comb non è più strettamente necessario, ma può aiutare la leggibilità
    // logic total_match_found_in_beat_comb; // Indica se almeno una regola ha matchato NEL BEAT CORRENTE

    // =====================================================================
    // REGISTRI SINCRONI E AGGIORNAMENTO OFFSET
    // =====================================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin // Reset asincrono attivo basso
            current_state <= STATE_IDLE;
            r_pkt_data <= '0;
            r_pkt_kstrb <= '0;
            r_pkt_last <= 1'b0;
            current_beat_start_byte_offset <= '0;

            accum_match_valid_reg <= '0;
            accum_packet_addr_list_reg <= '0;

            tx_match_valid_reg <= '0;
            tx_packet_addr_list_reg <= '0;
            tx_num_matches_reg <= '0;
        end else begin
            current_state <= next_state; // Aggiornamento dello stato FSM

                // Cattura i dati in ingresso solo se il beat è stato accettato (handshake)
                if ((pkt_valid_in && pkt_ready_out) || pkt_last_in) begin
                    r_pkt_data  <= pkt_data_in;
                    r_pkt_kstrb <= pkt_kstrb_in;
                    r_pkt_last  <= pkt_last_in;
                
    
                    // Aggiorna i registri di accumulo dei match se siamo in STATE_PROCESSING
                    if (current_state == STATE_PROCESSING) begin
                        // Aggiorna i match accumulati con i match del beat corrente
                        // Data che una regola matcha al massimo 1 volta per pacchetto,
                        // basta un OR logico per accumulare la segnalazione.
                        accum_match_valid_reg <= accum_match_valid_reg | match_found_per_rule_comb;
        
                        // Per gli indirizzi, semplicemente li accumuliamo se la regola ha matchato
                        // e l'indirizzo per quella regola non è ancora stato registrato (o era 0).
                        // Essendo il match unico, basterebbe anche solo match_found_per_rule_comb.
                        for (int j = 0; j < NUM_RULES; j++) begin
                            if (match_found_per_rule_comb[j]) begin
                                accum_packet_addr_list_reg[j] <= matched_tx_addr_per_rule_comb[j];
                            end
                        end
    
                    // Aggiornamento dell'offset del beat corrente per il prossimo beat
                    current_beat_start_byte_offset <= current_beat_start_byte_offset + PKT_KSTRB_WIDTH;
                end
            end

            // Logica per il caricamento degli output finali (tx_*)

            if (next_state == STATE_REPORT_MATCH) begin
                tx_match_valid_reg      <= accum_match_valid_reg;
                tx_packet_addr_list_reg <= accum_packet_addr_list_reg;
                tx_num_matches_reg      <= $countones(accum_match_valid_reg); // Il conteggio è basato sull'accumulatore finale
            end else begin
                // In tutti gli altri stati, o se non si transita in REPORT_MATCH, resettiamo gli output finali
                tx_match_valid_reg      <= '0;
                tx_packet_addr_list_reg <= '0;
                tx_num_matches_reg      <= '0;
            end

            // Reset degli accumuli e dell'offset all'inizio di un nuovo pacchetto
            if (current_state == STATE_IDLE && next_state == STATE_PROCESSING) begin // Solo quando si sta per entrare in processing
                accum_match_valid_reg <= '0;
                accum_packet_addr_list_reg <= '0;
                // accum_num_matches_reg non serve resettarlo qui, viene ricalcolato dal $countones
                current_beat_start_byte_offset <= '0;
            end
        end
    end

    // =====================================================================
    // MACCHINA A STATI (FSM) E LOGICA DI MATCHING COMBINATORIA PER IL BEAT CORRENTE
    // =====================================================================
    always_comb begin
        next_state = current_state;
        pkt_ready_out = 1'b0; // Default a non pronto

        // Reset combinatorio delle variabili di match per il beat corrente
        match_found_per_rule_comb = '0;
        matched_tx_addr_per_rule_comb = '0;
        // total_match_found_in_beat_comb non è strettamente usato per la logica di stato, ma calcolato comunque se serve per debug
        // total_match_found_in_beat_comb = 1'b0;

        case (current_state)
            STATE_IDLE: begin
                pkt_ready_out = 1'b1; // Sempre pronto a ricevere il primo beat del pacchetto
                if (pkt_valid_in) begin
                    next_state = STATE_PROCESSING; // Inizia a processare il pacchetto
                end
            end

            STATE_PROCESSING: begin
                // Sempre pronto a ricevere il prossimo beat
                pkt_ready_out = 1'b1;

                
                

                // Loop attraverso tutte le regole definite per il BEAT CORRENTE
                for (int i = 0; i < NUM_RULES; i++) begin
                    if (rules_in[i].enable) begin // Solo se la regola è abilitata
                        automatic logic [$clog2(PACKET_MAX_SIZE)-1:0] rule_absolute_addr = rules_in[i].addr; // Indirizzo assoluto della regola
                        // Calcola l'indirizzo assoluto dell'ultimo byte in questo beat
                        automatic logic [$clog2(PACKET_MAX_SIZE)-1:0] current_beat_end_byte_offset = current_beat_start_byte_offset + PKT_KSTRB_WIDTH - 1;

                        // Controlla se l'indirizzo della regola rientra nel beat corrente
                        // E se non ha già matchato (ottimizzazione per evitare ricalcoli inutili, ma non strettamente necessaria)
                        if ((rule_absolute_addr >= current_beat_start_byte_offset) &&
                            (rule_absolute_addr <= current_beat_end_byte_offset) &&
                            (!accum_match_valid_reg[i])) begin // Aggiunta questa condizione per evitare ricalcoli di match già trovati

                            // Calcola l'offset del byte all'interno del beat
                            automatic logic [$clog2(PKT_KSTRB_WIDTH)-1:0] relative_byte_addr = rule_absolute_addr - current_beat_start_byte_offset;

                            // Verifica se il byte è valido (non mascherato da kstrb)
                            if (r_pkt_kstrb[relative_byte_addr]) begin
                                automatic logic [7:0] packet_byte = r_pkt_data[(relative_byte_addr * 8) +: 8]; // Estrae il byte

                                automatic logic current_rule_matches; // Flag temporaneo per il match di questa regola

                                // Esegui il confronto basato sul simbolo della regola
                                case (rules_in[i].symbol)
                                    EQ: current_rule_matches = (packet_byte == rules_in[i].value);
                                    GT: current_rule_matches = (packet_byte > rules_in[i].value);
                                    LT: current_rule_matches = (packet_byte < rules_in[i].value);
                                    GE: current_rule_matches = (packet_byte >= rules_in[i].value);
                                    LE: current_rule_matches = (packet_byte <= rules_in[i].value);
                                    default: current_rule_matches = 1'b0; // Simbolo non riconosciuto o errore
                                endcase

                                // Se questa regola ha matchato nel beat corrente, registra il match combinatorio
                                if (current_rule_matches) begin
                                    match_found_per_rule_comb[i] = 1'b1;
                                    matched_tx_addr_per_rule_comb[i] = rules_in[i].packet_tx_addr;
                                end
                            end // if r_pkt_kstrb
                        end // if rule_absolute_addr within beat range and not already matched
                    end // if rules_in[i].enable
                end // for loop regole

                // Non è necessario ricalcolare total_match_found_in_beat_comb per la FSM,
                // ma per coerenza lo manteniamo come commento se un giorno dovesse servire per il debug.
                // total_match_found_in_beat_comb = |match_found_per_rule_comb;

                // Logica di transizione
                if (pkt_valid_in  && pkt_ready_out && r_pkt_last) begin
                    // Se l'ultimo beat del pacchetto è stato accettato, passa allo stato di segnalazione
                    next_state = STATE_WAIT_ACC;
                end else begin
                    // Altrimenti, continua a processare il prossimo beat del pacchetto
                    next_state = STATE_PROCESSING;
                end
            end // STATE_PROCESSING
            
            
            STATE_WAIT_ACC: begin
                next_state = STATE_REPORT_MATCH;
            end
            
            

            STATE_REPORT_MATCH: begin
                // Questo stato è dedicato a mantenere gli output finali validi per un ciclo.
                // Dopo un ciclo, si torna in IDLE per aspettare nuovi pacchetti.
                next_state = STATE_IDLE;
                pkt_ready_out = 1'b1; // Deve essere pronto per un nuovo pacchetto subito dopo la segnalazione
            end

            default: next_state = STATE_IDLE; // Stato di fallback per sicurezza
        endcase
    end

    // =====================================================================
    // ASSEGNAZIONI DEGLI OUTPUT FINALI
    // I valori registrati vengono assegnati direttamente alle porte di output.
    // =====================================================================
    assign tx_match_valid_out = tx_match_valid_reg;
    assign tx_packet_addr_list_out = tx_packet_addr_list_reg;
    assign tx_num_matches_out = tx_num_matches_reg;

endmodule