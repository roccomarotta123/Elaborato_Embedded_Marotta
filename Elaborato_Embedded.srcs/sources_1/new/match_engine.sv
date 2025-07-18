// File: match_engine.sv



`timescale 1ns / 1ps



import traffic_manager_pkg::*; //package con i parametri e i tipi di dati globali



module match_engine #(

    parameter PKT_DATA_WIDTH = AXI_STREAM_DATA_WIDTH,

    parameter PKT_KSTRB_WIDTH = AXI_STREAM_KSTRB_WIDTH

) (

    input logic clk,

    input logic reset_n,



    input logic [PKT_DATA_WIDTH-1:0] pkt_data_in,

    input logic [PKT_KSTRB_WIDTH-1:0] pkt_kstrb_in,

    input logic                       pkt_last_in,

    input logic                       pkt_valid_in,

    output logic                      pkt_ready_out,



    input rule_entry_t rules_in [NUM_RULES-1:0],



    // Nuove uscite per match multipli

    output logic [NUM_RULES-1:0]      tx_match_valid_out,      // Vettore di validità: tx_match_valid_out[i] è alto se rules_in[i] ha matchato

    output logic [NUM_RULES-1:0][31:0] tx_packet_addr_list_out, // Array degli indirizzi delle regole

    output logic [$clog2(NUM_RULES+1)-1:0] tx_num_matches_out,      // Contatore del numero di match trovati



    // =====================================================================

    // NUOVI INPUT PER LA LOGICA BOOELANA DELLE REGOLE

    // =====================================================================

    input logic [NUM_RULES-1:0]                 rule_logic_mask_and_in,    // Maschera per le regole che devono essere combinate in AND

    input logic [NUM_RULES-1:0]                 rule_logic_mask_or_in,     // Maschera per le regole che devono essere combinate in OR

    input logic                                 final_match_logic_enable_in, // Abilita/disabilita la logica booleana finale

    output logic                                res_mask_and,               // se alto la maschera di regole in and ha avuto successo

    output logic [NUM_RULES-1:0]                res_mask_or,                 // viene specificate quale regole in or matcha nel pacchetto

    

        // Input per la logica SOP

    input logic [MAX_SOP_TERMS-1:0][NUM_RULES-1:0] sop_term_masks_in, // Matrice di maschere: sop_term_masks_in[j] definisce il j-esimo termine AND

    input logic [MAX_SOP_TERMS-1:0] sop_term_enable_in, // Abilita/disabilita ogni termine AND

    input logic sop_logic_enable_in, // Abilita/disabilita l'intera logica SOP

    output logic final_sop_match_out // Risultato finale della logica SOP

    );



    // =====================================================================

    // PARAMETRI LOCALI

    // =====================================================================

    localparam IDX_WIDTH = $clog2(NUM_RULES + 1); // Larghezza necessaria per contare fino a NUM_RULES match



    // =====================================================================

    // TIPI DI DATO LOCALI (per la FSM)

    // =====================================================================

    typedef enum logic [1:0] {

        STATE_IDLE,          // Attesa di un nuovo pacchetto

        STATE_PROCESSING,    // Elaborazione di tutti i beat del pacchetto

        STATE_WAIT_ACC,      // Aggiornamento registri di accumulo beat finale

        STATE_REPORT_MATCH   // Segnalazione dei match finali dopo l'elaborazione completa del pacchetto

    } fsm_state_e;



    // =====================================================================

    // SEGNALI INTERNI REGISTRATI (Sincroni)

    // =====================================================================

    fsm_state_e current_state, next_state;



    logic [PKT_DATA_WIDTH-1:0] r_pkt_data;

    logic [PKT_KSTRB_WIDTH-1:0] r_pkt_kstrb;

    logic                       r_pkt_last;



    // L'offset del primo byte del beat corrente all'interno del pacchetto

    logic [$clog2(PACKET_MAX_SIZE)-1:0] current_beat_start_byte_offset;



    // Registri per accumulare i match trovati su tutti i beat del pacchetto

    logic [NUM_RULES-1:0]      accum_match_valid_reg;

    logic [NUM_RULES-1:0][31:0] accum_packet_addr_list_reg;



    // Registri per gli output finali (validi solo in STATE_REPORT_MATCH)

    logic [NUM_RULES-1:0]      tx_match_valid_reg;

    logic [NUM_RULES-1:0][31:0] tx_packet_addr_list_reg;

    logic [IDX_WIDTH-1:0]      tx_num_matches_reg;



    // =====================================================================

    // SEGNALI INTERNI COMBINATORI (Asincroni)

    // =====================================================================

    logic [NUM_RULES-1:0] match_found_per_rule_comb;

    logic [NUM_RULES-1:0][31:0] matched_tx_addr_per_rule_comb;



    // Nuovi segnali per la logica booleana finale

    logic matched_and_group_comb; // Risultato AND delle regole selezionate

    logic [NUM_RULES-1:0] matched_or_group_comb;  // Risultato OR delle regole selezionate

    

    // Segnali interni combinatori

    logic [MAX_SOP_TERMS-1:0] individual_sop_term_results_comb; // Risultato di ogni singolo termine AND

    logic sop_final_result_comb; // Risultato OR finale di tutti i termini AND





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

            

            

            res_mask_and <= '0;

            res_mask_or <= '0;

            final_sop_match_out <= '0;



        end else begin

            current_state <= next_state; // Aggiornamento dello stato FSM



            // Cattura i dati in ingresso solo se il beat è stato accettato (handshake)

            if ((pkt_valid_in && pkt_ready_out) || pkt_last_in) begin // Removed pkt_last_in from OR, it's just about valid data transfer

                                                                    // The logic for r_pkt_last ensures 'last' is captured anyway

                r_pkt_data  <= pkt_data_in;

                r_pkt_kstrb <= pkt_kstrb_in;

                r_pkt_last  <= pkt_last_in; // Ensure r_pkt_last captures the last beat's status





                // Aggiorna i registri di accumulo dei match se siamo in STATE_PROCESSING

                if (current_state == STATE_PROCESSING) begin

                    accum_match_valid_reg <= accum_match_valid_reg | match_found_per_rule_comb;



                    for (int j = 0; j < NUM_RULES; j++) begin

                        // Solo se la regola ha matchato ora E non aveva matchato prima

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

                tx_match_valid_reg       <= accum_match_valid_reg;

                tx_packet_addr_list_reg <= accum_packet_addr_list_reg;

                tx_num_matches_reg       <= $countones(accum_match_valid_reg);

                

                // Aggiorna gli output finali per la logica booleana

                res_mask_and <=  matched_and_group_comb;

                res_mask_or <=  matched_or_group_comb;

                final_sop_match_out <= sop_final_result_comb;





            end else begin

                // In tutti gli altri stati, o se non si transita in REPORT_MATCH, resettiamo gli output finali

                tx_match_valid_reg       <= '0;

                tx_packet_addr_list_reg <= '0;

                tx_num_matches_reg       <= '0;

                

                res_mask_and <= '0;

                res_mask_or <= '0;

                final_sop_match_out <= '0;

            end



            // Reset degli accumuli e dell'offset all'inizio di un nuovo pacchetto

            // Questo reset deve avvenire quando si *entra* in PROCESSING dallo stato IDLE

            if (current_state == STATE_IDLE && next_state == STATE_PROCESSING) begin

                accum_match_valid_reg <= '0;

                accum_packet_addr_list_reg <= '0;

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



        // Reset combinatorio per la logica booleana (default)

        matched_and_group_comb = 1'b1; // Inizializza a 1 per l'AND

        matched_or_group_comb = 1'b0;  // Inizializza a 0 per l'OR



        case (current_state)

            STATE_IDLE: begin

                pkt_ready_out = 1'b1; // Sempre pronto a ricevere il primo beat del pacchetto

                if (pkt_valid_in) begin

                    next_state = STATE_PROCESSING; // Inizia a processare il pacchetto

                end

            end



            STATE_PROCESSING: begin

                pkt_ready_out = 1'b1; // Sempre pronto a ricevere il prossimo beat



                // Loop attraverso tutte le regole definite per il BEAT CORRENTE

                for (int i = 0; i < NUM_RULES; i++) begin

                    if (rules_in[i].enable) begin // Solo se la regola è abilitata

                        automatic logic [$clog2(PACKET_MAX_SIZE)-1:0] rule_absolute_addr = rules_in[i].addr;

                        automatic logic [$clog2(PACKET_MAX_SIZE)-1:0] current_beat_end_byte_offset = current_beat_start_byte_offset + PKT_KSTRB_WIDTH - 1;



                        if ((rule_absolute_addr >= current_beat_start_byte_offset) &&

                            (rule_absolute_addr <= current_beat_end_byte_offset) &&

                            (!accum_match_valid_reg[i])) begin // Aggiunta questa condizione per evitare ricalcoli di match già trovati



                            automatic logic [$clog2(PKT_KSTRB_WIDTH)-1:0] relative_byte_addr = rule_absolute_addr - current_beat_start_byte_offset;



                            if (r_pkt_kstrb[relative_byte_addr]) begin

                                automatic logic [7:0] packet_byte = r_pkt_data[(relative_byte_addr * 8) +: 8];



                                automatic logic current_rule_matches;



                                case (rules_in[i].symbol)

                                    EQ: current_rule_matches = (packet_byte == rules_in[i].value);

                                    GT: current_rule_matches = (packet_byte > rules_in[i].value);

                                    LT: current_rule_matches = (packet_byte < rules_in[i].value);

                                    GE: current_rule_matches = (packet_byte >= rules_in[i].value);

                                    LE: current_rule_matches = (packet_byte <= rules_in[i].value);

                                    default: current_rule_matches = 1'b0;

                                endcase



                                if (current_rule_matches) begin

                                    match_found_per_rule_comb[i] = 1'b1;

                                    matched_tx_addr_per_rule_comb[i] = rules_in[i].packet_tx_addr;

                                end

                            end

                        end

                    end

                end



                // Logica di transizione

                if (pkt_ready_out && r_pkt_last) begin

                    next_state = STATE_WAIT_ACC;

                end else begin

                    next_state = STATE_PROCESSING;

                end

            end // STATE_PROCESSING



            STATE_WAIT_ACC: begin

                next_state = STATE_REPORT_MATCH;

            end



            STATE_REPORT_MATCH: begin

                next_state = STATE_IDLE;

                pkt_ready_out = 1'b1;

            end



            default: next_state = STATE_IDLE;

        endcase



        // =====================================================================

        // LOGICA BOOLEANA FINALE (CALCOLATA COMBINATORIAMENTE SULL'ACCUMULO FINALE)

        // Questa logica viene calcolata in tutti gli stati, ma è significativa

        // solo nello stato STATE_REPORT_MATCH quando gli accum_match_valid_reg

        // contengono i risultati finali per il pacchetto.

        // =====================================================================

        if (final_match_logic_enable_in) begin

            // Calcolo del gruppo AND: tutte le regole nella maschera AND devono aver matchato

            matched_and_group_comb = (rule_logic_mask_and_in & accum_match_valid_reg) == rule_logic_mask_and_in;





            // Calcolo del gruppo OR: almeno una delle regole nella maschera OR deve aver matchato

            matched_or_group_comb = rule_logic_mask_or_in & accum_match_valid_reg;



        end

        

        // Inizializzazione per la logica SOP

    sop_final_result_comb = 1'b0; // Default a falso per l'OR finale



    if (sop_logic_enable_in) begin

        // Calcola il risultato di ogni termine AND

        for (int j = 0; j < MAX_SOP_TERMS; j++) begin

            if (sop_term_enable_in[j]) begin

                // Un termine AND è vero se tutte le regole specificate nella sua maschera hanno matchato

                individual_sop_term_results_comb[j] =

                    (sop_term_masks_in[j] & accum_match_valid_reg) == sop_term_masks_in[j];

            end else begin

                individual_sop_term_results_comb[j] = 1'b0; // Termine disabilitato non contribuisce all'OR

            end

        end

        // Esegui l'OR logico di tutti i risultati dei termini AND

        sop_final_result_comb = |individual_sop_term_results_comb; // Riduzione OR bit-a-bit

    end else begin

        sop_final_result_comb = 1'b0; // Se la logica SOP è disabilitata, il risultato è falso

    end

        end



    // =====================================================================

    // ASSEGNAZIONI DEGLI OUTPUT FINALI

    // I valori registrati vengono assegnati direttamente alle porte di output.

    // =====================================================================

    assign tx_match_valid_out = tx_match_valid_reg;

    assign tx_packet_addr_list_out = tx_packet_addr_list_reg;

    assign tx_num_matches_out = tx_num_matches_reg;



endmodule