#include <stdio.h>

// ===============================================
// PARAMETRI DEL DESIGN
// ===============================================

#define PKT_DATA_WIDTH 512       // Larghezza totale del pacchetto dati in bit (512 bit = 64 byte)
#define PKT_KSTRB_WIDTH (PKT_DATA_WIDTH / 8) // Larghezza di kstrb in byte (un byte per ogni 8 bit di PKT_DATA_WIDTH)

#define NUM_RULES 16             // Numero di regole di matching.
                                 // Assicurati che sia almeno 5 ora per includere la nuova regola.

#define RULE_ADDR_WIDTH 12       // Larghezza dell'indirizzo all'interno del pacchetto (offset in byte)
#define RULE_VALUE_WIDTH 8       // Larghezza del valore di confronto (in bit)
#define RULE_SYMBOL_WIDTH 2      // Larghezza del simbolo di confronto (EQ, LT, GT, etc.)
#define AXI_STREAM_TX_ADDR_WIDTH 32 // Larghezza dell'indirizzo di destinazione (usato per tx_packet_addr)

#define NUM_SOP_TERMS 16         // Numero massimo di termini "prodotto" per la logica SOP


// Rappresentazione del pacchetto dati (512 bit = 64 byte)
typedef unsigned char packet_data_t[PKT_DATA_WIDTH / 8]; // Array di byte (8 bit)

// Rappresentazione di kstrb (un byte per ogni 8 bit di data)
typedef unsigned char kstrb_t[PKT_KSTRB_WIDTH]; // Array di byte (8 bit)

// Simboli di confronto (enum per chiarezza)
typedef enum {
    EQ = 0, // Equal
    LT = 1, // Less Than
    GT = 2, // Greater Than
    // Aggiungi altri se ne hai nel tuo design (es. LE, GE, NE)
} compare_symbol_t;

// Struttura per definire una singola regola
typedef struct {
    unsigned short   addr;         // Indirizzo del campo da confrontare nel pacchetto (16 bit)
    unsigned char    value;        // Valore di confronto (8 bit)
    compare_symbol_t symbol;       // Simbolo di confronto (EQ, LT, GT)
    unsigned int     packet_tx_addr; // Indirizzo di destinazione del pacchetto (32 bit)
    unsigned char    enable;       // Abilita/disabilita questa regola (1 bit)
} rule_t;

// Maschere per la logica AND/OR e per i termini SOP
// Usiamo unsigned long long per garantire 64 bit su architetture a 32/64 bit
#define NUM_RULE_MASK_WORDS ((NUM_RULES + 63) / 64)
typedef unsigned long long rule_mask_t[NUM_RULE_MASK_WORDS]; // Per rule_logic_mask_and, rule_logic_mask_or, sop_term_masks

// Maschera per abilitare i termini SOP (NUM_SOP_TERMS bits)
#define NUM_SOP_ENABLE_WORDS ((NUM_SOP_TERMS + 63) / 64)
typedef unsigned long long sop_enable_mask_t[NUM_SOP_ENABLE_WORDS];

// Array per gli indirizzi dei pacchetti di output (uno per ogni possibile match)
typedef unsigned int tx_packet_addr_list_t[NUM_RULES];

// Array di flag per indicare quali regole hanno fatto match
typedef unsigned char tx_match_valid_t[NUM_RULES];

// ===============================================
// FUNZIONI DI SUPPORTO
// ===============================================

// Funzione per convertire una stringa esadecimale di 2 caratteri in un byte.
unsigned char hex_to_byte(const char* hex_str) {
    unsigned char val = 0;
    char c1 = hex_str[0];
    if (c1 >= '0' && c1 <= '9') val = (c1 - '0') << 4;
    else if (c1 >= 'a' && c1 <= 'f') val = (c1 - 'a' + 10) << 4;
    else if (c1 >= 'A' && c1 <= 'F') val = (c1 - 'A' + 10) << 4;

    char c2 = hex_str[1];
    if (c2 >= '0' && c2 <= '9') val |= (c2 - '0');
    else if (c2 >= 'a' && c2 <= 'f') val |= (c2 - 'a' + 10);
    else if (c2 >= 'A' && c2 <= 'F') val |= (c2 - 'A' + 10);

    return val;
}

// Funzione per convertire una stringa esadecimale (es. "A1B2...") in un array di byte
void hex_string_to_byte_array(const char* hex_str, unsigned char* byte_array, int num_bytes) {
    for (int i = 0; i < num_bytes; ++i) {
        byte_array[i] = hex_to_byte(hex_str + (i * 2));
    }
}

// Funzione per leggere un singolo bit da una maschera (array di unsigned long long)
unsigned char get_bit_from_mask(const unsigned long long* mask_array, int bit_idx) {
    int array_idx = bit_idx / 64;
    int bit_in_word = bit_idx % 64;
    return (unsigned char)((mask_array[array_idx] >> bit_in_word) & 0x1ULL);
}

// Funzione per impostare un singolo bit in una maschera (array di unsigned long long)
void set_bit_in_mask(unsigned long long* mask_array, int bit_idx, unsigned char value) {
    int array_idx = bit_idx / 64;
    int bit_in_word = bit_idx % 64;
    if (value) {
        mask_array[array_idx] |= (0x1ULL << bit_in_word);
    } else {
        mask_array[array_idx] &= ~(0x1ULL << bit_in_word);
    }
}

// Funzione per estrarre un campo dati (di 8 bit) da un pacchetto largo (512 bit)
// basato su un indirizzo (addr). Si assume che 'addr' sia un offset in byte.
unsigned char get_data_field_from_packet(const packet_data_t pkt_beat, unsigned short addr_relative_to_beat) {
    if (addr_relative_to_beat < PKT_DATA_WIDTH / 8) { // PKT_DATA_WIDTH / 8 è la dimensione del beat in byte
        return pkt_beat[addr_relative_to_beat];
    }
    return 0; // Indirizzo fuori dal beat corrente
}

// ===============================================
// IL MIO MODULO MATCH_ENGINE (la funzione C che simula l'HDL)
// ===============================================

// Questa funzione ora riceve anche l'offset di inizio del beat corrente
// e lo stato accumulato dei match.
void match_engine_sw(
    // Inputs
    const packet_data_t pkt_data_in,
    const kstrb_t pkt_kstrb_in,
    unsigned char pkt_last_in,
    unsigned char pkt_valid_in,
    unsigned short current_beat_start_byte_offset_in, // Nuovo input

    rule_t rules_in[NUM_RULES],
    rule_mask_t rule_logic_mask_and_in,
    rule_mask_t rule_logic_mask_or_in,
    unsigned char final_match_logic_enable_in,

    rule_mask_t sop_term_masks_in[NUM_SOP_TERMS],
    sop_enable_mask_t sop_term_enable_in,
    unsigned char sop_logic_enable_in,

    // Outputs
    unsigned char* pkt_ready_out,
    // Questi output ora rifletteranno i match accumulati e il risultato finale
    // Lo stato intermedio accum_match_valid_reg sarà gestito nel main o esternamente
    unsigned char* tx_num_matches_out,
    unsigned long long* res_mask_and_out,
    unsigned long long* res_mask_or_out,
    unsigned char* final_sop_match_out,

    // Output dello stato accumulato dei match (per persistenza esterna)
    unsigned long long* accum_match_valid_reg_out // Nuovo output
) {
    *pkt_ready_out = 0;
    *tx_num_matches_out = 0;
    *res_mask_and_out = 0ULL;
    *res_mask_or_out = 0ULL;
    *final_sop_match_out = 0;
    *accum_match_valid_reg_out = 0ULL; // Sarà sovrascritto se pkt_valid_in è 1


    if (!pkt_valid_in) {
        *pkt_ready_out = 1;
        return;
    }

    // FASE 1: Valutazione delle Singole Regole per il BEAT CORRENTE
    unsigned long long current_beat_matches_mask = 0ULL; // Match nel beat corrente
    unsigned short current_beat_end_byte_offset = current_beat_start_byte_offset_in + PKT_KSTRB_WIDTH - 1;

    for (int i = 0; i < NUM_RULES; ++i) {
        if (rules_in[i].enable) {
            unsigned short rule_absolute_addr = rules_in[i].addr;
            
            // Verifica se l'indirizzo della regola ricade nel beat corrente
            if ((rule_absolute_addr >= current_beat_start_byte_offset_in) &&
                (rule_absolute_addr <= current_beat_end_byte_offset)) {
                
                // Calcola l'indirizzo relativo all'inizio del beat per estrarre il dato
                unsigned short addr_relative_to_beat = rule_absolute_addr - current_beat_start_byte_offset_in;

                unsigned char extracted_data = get_data_field_from_packet(pkt_data_in, addr_relative_to_beat);
                
                // Verifica kstrb_in sull'indirizzo relativo
                unsigned char is_kstrb_valid = (addr_relative_to_beat < PKT_KSTRB_WIDTH && pkt_kstrb_in[addr_relative_to_beat] != 0x00);

                unsigned char rule_match_result = 0;

                if (is_kstrb_valid) {
                    switch(rules_in[i].symbol) {
                        case EQ:
                            rule_match_result = (extracted_data == rules_in[i].value);
                            break;
                        case LT:
                            rule_match_result = (extracted_data < rules_in[i].value);
                            break;
                        case GT:
                            rule_match_result = (extracted_data > rules_in[i].value);
                            break;
                        default:
                            rule_match_result = 0;
                            break;
                    }
                }
                
                // Se la regola matcha nel beat corrente, settiamo il bit corrispondente
                if (rule_match_result) {
                    set_bit_in_mask(&current_beat_matches_mask, i, 1);
                }
            }
        }
    }
    
    // Il risultato accumulato viene gestito dal chiamante (main)
    // Qui si passa solo il match del beat corrente
    *accum_match_valid_reg_out = current_beat_matches_mask; // Questo sarà OR-ato con i risultati precedenti dal main

    // Nota: tx_match_valid_out, tx_packet_addr_list_out, tx_num_matches_out,
    // res_mask_and_out, res_mask_or_out, final_sop_match_out
    // sono calcolati SOLO quando pkt_last_in è 1, dopo che tutti i beat sono stati ricevuti.
    // Questi output non sono validi ad ogni beat intermedio.
    // La logica di calcolo finale verrà spostata nel main.
    
    // match_engine_sw produce solo i match del beat corrente.
    // Il resto della logica (SOP, etc.) avverrà quando pkt_last_in è 1.

    *pkt_ready_out = 1; // Sempre pronto a ricevere il prossimo beat
}

// ===============================================
// PROGRAMMA PRINCIPALE (il mio testbench software)
// ===============================================

int main() {
    FILE *output_file = fopen("output.txt", "w");
    if (output_file == NULL) {
        perror("Errore nell'apertura del file di output");
        return 1;
    }

    fprintf(output_file, "Avvio test match_engine SW...\n");

    packet_data_t my_pkt_data_in;
    kstrb_t my_pkt_kstrb_in;
    unsigned char my_pkt_last_in;
    unsigned char my_pkt_valid_in;

    rule_t my_rules_in[NUM_RULES];
    rule_mask_t my_rule_logic_mask_and_in;
    rule_mask_t my_rule_logic_mask_or_in;
    unsigned char my_final_match_logic_enable_in = 0;

    rule_mask_t my_sop_term_masks_in[NUM_SOP_TERMS];
    sop_enable_mask_t my_sop_term_enable_in;
    unsigned char my_sop_logic_enable_in = 1;

    // Variabili per l'output di match_engine_sw per il beat corrente
    unsigned char my_pkt_ready_out;
    unsigned char temp_tx_num_matches_out; // Temp per il beat corrente
    unsigned long long temp_res_mask_and_out; // Temp per il beat corrente
    unsigned long long temp_res_mask_or_out; // Temp per il beat corrente
    unsigned char temp_final_sop_match_out; // Temp per il beat corrente
    unsigned long long current_beat_matches_mask_from_engine; // Output del match_engine per il beat

    // Variabili di STATO PERSISTENTE per il messaggio FIX completo
    unsigned long long accum_match_valid_reg = 0ULL; // Corrisponde a accum_match_valid_reg in Verilog
    unsigned short current_beat_start_byte_offset = 0; // Corrisponde a current_beat_start_byte_offset in Verilog
    
    // Questi saranno gli output finali quando pkt_last_in è 1
    tx_match_valid_t final_tx_match_valid_out;
    tx_packet_addr_list_t final_tx_packet_addr_list_out;
    unsigned char final_tx_num_matches_out;
    unsigned long long final_res_mask_and_out;
    unsigned long long final_res_mask_or_out;
    unsigned char final_final_sop_match_out;


    // --- Inizializzazione delle Regole e Logiche per il TEST ---
    for (int i = 0; i < NUM_RULES; ++i) {
        my_rules_in[i] = (rule_t){ .addr = 0, .value = 0, .symbol = EQ, .packet_tx_addr = 0, .enable = 0 };
    }

    
    // NUOVA REGOLA: MsgType 'D' (New Order Single)
    my_rules_in[0] = (rule_t){ .addr = 20, .value = 0x44, .symbol = EQ, .packet_tx_addr = 0x5000, .enable = 1 }; // 0x44 è ASCII 'D'
    // NUOVA REGOLA: Side '1' (Buy)
    my_rules_in[1] = (rule_t){ .addr = 313, .value = 0x31, .symbol = EQ, .packet_tx_addr = 0x6000, .enable = 1 }; // 0x31 è ASCII '1'
    // NUOVA REGOLA: Symbol 'BHP' (Basta controllare il primo carattere del campo)
    my_rules_in[2] = (rule_t){ .addr = 162, .value = 0x42, .symbol = EQ, .packet_tx_addr = 0x7000, .enable = 1 }; // 0x42 è ASCII 'B'
    // NUOVA REGOLA: OrderType '2' (Limit)
    my_rules_in[3] = (rule_t){ .addr = 353, .value = 0x32, .symbol = EQ, .packet_tx_addr = 0x8000, .enable = 1 }; // 0x42 è ASCII '2'

    // --- Configurazione della logica AND/OR finale ---
    // Resetta le maschere di logica AND/OR a zero
    my_rule_logic_mask_and_in[0] = 0ULL;
    my_rule_logic_mask_or_in[0] = 0ULL;

    // Configura la maschera per la logica AND: vogliamo un match
    // solo se la Regola 0 E la Regola 1 sono entrambe vere.
    // Usiamo set_bit_in_mask per impostare i bit corrispondenti alle regole.
    set_bit_in_mask(my_rule_logic_mask_and_in, 0, 1); // Abilita la Regola 0 nell'AND
    set_bit_in_mask(my_rule_logic_mask_and_in, 1, 1); // Abilita la Regola 1 nell'AND
    set_bit_in_mask(my_rule_logic_mask_and_in, 2, 1); // Abilita la Regola 1 nell'AND






    // Esempio di Logica SOP:
    for (int t = 0; t < NUM_SOP_TERMS; ++t) {
        for (int w = 0; w < NUM_RULE_MASK_WORDS; ++w) {
            my_sop_term_masks_in[t][w] = 0ULL;
        }
    }
    for (int w = 0; w < NUM_SOP_ENABLE_WORDS; ++w) {
        my_sop_term_enable_in[w] = 0ULL;
    }



        // Termine 0: (Regola 0 AND Regola 1)
    set_bit_in_mask(my_sop_term_masks_in[0], 0, 1); // Imposta il bit per la Regola 0
    set_bit_in_mask(my_sop_term_masks_in[0], 1, 1); // Imposta il bit per la Regola 1
    
    // Abilita il Termine 0
    set_bit_in_mask(my_sop_term_enable_in, 0, 1);
    
    // Termine 1: (Regola 2 AND Regola 3)
    set_bit_in_mask(my_sop_term_masks_in[1], 2, 1); // Imposta il bit per la Regola 2
    set_bit_in_mask(my_sop_term_masks_in[1], 3, 1); // Imposta il bit per la Regola 3
    
    // Abilita il Termine 1
    set_bit_in_mask(my_sop_term_enable_in, 1, 1);



    // --- Lettura input da file e Esecuzione Simulazione ---

    const char* input_filename = "packet_stream_for_match_engine.txt";
    FILE *input_file = fopen(input_filename, "r");
    if (input_file == NULL) {
        perror("Errore nell'apertura del file di input");
        fprintf(output_file, "Errore: Assicurati che '%s' sia nella stessa directory del programma eseguibile.\n", input_filename);
        fclose(output_file);
        return 1;
    }

    char line[512];
    char data_hex_str[((PKT_DATA_WIDTH / 8) * 2) + 1];
    char kstrb_hex_str[((PKT_KSTRB_WIDTH) * 2) + 1];
    int pkt_last_val_int;

    fprintf(output_file, "Inizio test match_engine SW con input da file '%s'...\n", input_filename);

    int processed_blocks = 0;
    int processed_fix_messages = 0;

    // Reset iniziale dello stato
    accum_match_valid_reg = 0ULL;
    current_beat_start_byte_offset = 0;

    while (fgets(line, sizeof(line), input_file) != NULL) {
        int i = 0;
        while (line[i] != '\0' && line[i] != '\n') {
            i++;
        }
        if (line[i] == '\n') {
            line[i] = '\0';
        }

        if (sscanf(line, "%128[^,],%128[^,],%d", data_hex_str, kstrb_hex_str, &pkt_last_val_int) != 3) {
            fprintf(output_file, "Errore di formato nella riga del file di input: %s\n", line);
            continue;
        }

        hex_string_to_byte_array(data_hex_str, my_pkt_data_in, PKT_DATA_WIDTH / 8);
        hex_string_to_byte_array(kstrb_hex_str, my_pkt_kstrb_in, PKT_KSTRB_WIDTH);
        my_pkt_last_in = (unsigned char)pkt_last_val_int;
        my_pkt_valid_in = 1;

        // Chiamata al match_engine_sw con lo stato corrente
        match_engine_sw(
            my_pkt_data_in, my_pkt_kstrb_in, my_pkt_last_in, my_pkt_valid_in,
            current_beat_start_byte_offset, // Passa l'offset corrente del beat
            my_rules_in, my_rule_logic_mask_and_in, my_rule_logic_mask_or_in,
            my_final_match_logic_enable_in, my_sop_term_masks_in, my_sop_term_enable_in,
            my_sop_logic_enable_in,
            &my_pkt_ready_out, &temp_tx_num_matches_out, &temp_res_mask_and_out,
            &temp_res_mask_or_out, &temp_final_sop_match_out,
            &current_beat_matches_mask_from_engine // Riceve i match del beat corrente
        );
        processed_blocks++;

        // Aggiorna lo stato accumulato dei match
        accum_match_valid_reg |= current_beat_matches_mask_from_engine;

        // Se è l'ultimo beat del messaggio FIX, esegui la logica finale e resetta lo stato
        if (my_pkt_last_in == 1) {
            processed_fix_messages++;
            
            // Logica finale di calcolo degli output quando il messaggio è completo
            final_tx_num_matches_out = 0;
            // Popola final_tx_match_valid_out e final_tx_packet_addr_list_out
            for (int i = 0; i < NUM_RULES; ++i) {
                if (get_bit_from_mask(&accum_match_valid_reg, i)) { // Se la regola ha matchato in qualsiasi beat
                    final_tx_match_valid_out[i] = 1;
                    if (final_tx_num_matches_out < NUM_RULES) { // Previene overflow dell'array
                        final_tx_packet_addr_list_out[final_tx_num_matches_out] = my_rules_in[i].packet_tx_addr;
                    }
                    final_tx_num_matches_out++;
                } else {
                    final_tx_match_valid_out[i] = 0;
                }
            }

            // Calcolo logica AND/OR finale (se abilitata)
            if (my_final_match_logic_enable_in) {
                unsigned long long temp_res_and_val = (accum_match_valid_reg & my_rule_logic_mask_and_in[0]) == my_rule_logic_mask_and_in[0];
                final_res_mask_and_out = temp_res_and_val ? 1ULL : 0ULL;

                unsigned long long temp_res_or_val = (accum_match_valid_reg & my_rule_logic_mask_or_in[0]) != 0ULL;
                final_res_mask_or_out = temp_res_or_val ? 1ULL : 0ULL;
            } else {
                final_res_mask_and_out = 0ULL;
                final_res_mask_or_out = 0ULL;
            }

            // Calcolo logica SOP finale
            final_final_sop_match_out = 0;
            if (my_sop_logic_enable_in) {
                unsigned char sop_final_result = 0;
                for (int t = 0; t < NUM_SOP_TERMS; ++t) {
                    if (get_bit_from_mask(my_sop_term_enable_in, t)) {
                        unsigned char term_product_result = 1;

                        unsigned char term_mask_is_empty = 1; 
                        for (int w = 0; w < NUM_RULE_MASK_WORDS; ++w) {
                            if (my_sop_term_masks_in[t][w] != 0ULL) {
                                term_mask_is_empty = 0;
                                break;
                            }
                        }

                        if (term_mask_is_empty) {
                            term_product_result = 0;
                        } else {
                            for (int r = 0; r < NUM_RULES; ++r) {
                                if (get_bit_from_mask(my_sop_term_masks_in[t], r)) {
                                    term_product_result = term_product_result && get_bit_from_mask(&accum_match_valid_reg, r); // Usa l'accumulato!
                                    if (!term_product_result) break;
                                }
                            }
                        }
                        sop_final_result = sop_final_result || term_product_result;
                        if (sop_final_result) break;
                    }
                }
                final_final_sop_match_out = sop_final_result;
            }


            // Stampa i risultati finali per il messaggio FIX completo
            fprintf(output_file, "\n--- FINE MESSAGGIO FIX %d (Blocchi: %d) ---\n", processed_fix_messages, processed_blocks);
            fprintf(output_file, "   Numero di match individuali: %d\n", final_tx_num_matches_out);
            fprintf(output_file, "   Risultato SOP finale: %s\n", final_final_sop_match_out ? "MATCH" : "NO MATCH");

            if (final_tx_num_matches_out > 0) {
                fprintf(output_file, "   Regole che hanno matchato:\n");
                for (int i = 0; i < NUM_RULES; ++i) {
                    if (final_tx_match_valid_out[i]) {
                        fprintf(output_file, "     - Regola %d (Addr: 0x%X) - TX Addr: 0x%X\n", i, my_rules_in[i].addr, my_rules_in[i].packet_tx_addr);
                    }
                }
            }
            if (my_final_match_logic_enable_in) {
                fprintf(output_file, "   Risultato logica AND: 0x%llX\n", final_res_mask_and_out);
                fprintf(output_file, "   Risultato logica OR: 0x%llX\n", final_res_mask_or_out);
            }
            fprintf(output_file, "----------------------------------\n");

            // Reset dello stato per il prossimo messaggio FIX
            accum_match_valid_reg = 0ULL;
            current_beat_start_byte_offset = 0;
        } else {
            // Se non è l'ultimo beat, aggiorna l'offset per il prossimo beat
            current_beat_start_byte_offset += PKT_KSTRB_WIDTH;
        }
    }


    fprintf(output_file, "\nTest completato con input da file.\n");
    fprintf(output_file, "Processati %d blocchi totali (%d messaggi FIX completi)", 
                processed_blocks, processed_fix_messages);
    
    
    fclose(input_file);
    fclose(output_file);
    return 0;
}
