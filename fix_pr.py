from scapy.all import rdpcap, TCP, Raw
import math
import os


PKT_DATA_WIDTH = 512          # Larghezza del bus del tuo modulo in bit
BLOCK_SIZE_BYTES = PKT_DATA_WIDTH // 8 # 64 bytes (512 bits)

# --- CONFIGURAZIONE ---
PCAP_FILE = "fix.pcap" 
OUTPUT_FILE = "packet_stream_for_match_engine.txt"

# --- FUNZIONI DI SUPPORTO ---

def byte_array_to_hex_string(byte_array):
    """Converte una lista di interi (byte) in una stringa esadecimale."""
    return ''.join(f'{b:02x}' for b in byte_array)

def generate_kstrb(actual_block_len_bytes):
    """
    Genera una stringa esadecimale per kstrb (un byte per ogni byte del blocco).
    Se il blocco è parziale, i byte kstrb corrispondenti al padding saranno 0x00.
    """
    kstrb_bytes = [0xFF] * BLOCK_SIZE_BYTES # Inizialmente tutti validi
    if actual_block_len_bytes < BLOCK_SIZE_BYTES:
        # Se il blocco è parziale (l'ultimo di un messaggio), invalida i byte di padding
        for i in range(actual_block_len_bytes, BLOCK_SIZE_BYTES):
            kstrb_bytes[i] = 0x00
    return byte_array_to_hex_string(kstrb_bytes)

# --- NUOVE FUNZIONI PER PARSING FIX ---

def find_fix_message_end(fix_payload):
    """
    Trova la fine del primo messaggio FIX nel payload dato.
    Un messaggio FIX valido termina con '10=XXX<SOH>'.
    Restituisce l'indice del byte SUCCESSIVO al carattere SOH finale,
    o -1 se non trova un messaggio FIX completo e valido.
    """
    # Cerca la stringa del CheckSum e il SOH finale
    # Pattern: 10=XXX<SOH>
    # <SOH> è 0x01. Tag 10 è sempre il penultimo campo.
    # Il valore del checksum XXX è di 3 cifre.
    
    # Inizia a cercare il CheckSum (Tag 10) dal retro per efficienza
    # Un messaggio FIX inizia con 8= e finisce con 10=
    
    # Questo parser è semplificato e si aspetta messaggi completi
    # Per una robustezza totale, si dovrebbe parsare BodyLength (Tag 9)
    # Tuttavia, per il nostro scopo di simulazione, possiamo cercare il 10=XXX<SOH>
    
    current_pos = 0
    while True:
        # Cerca l'inizio del messaggio FIX: 8=FIX...
        start_tag_8_pos = fix_payload.find(b'8=FIX', current_pos)
        if start_tag_8_pos == -1:
            return -1 # Nessun altro messaggio FIX trovato

        # Il messaggio FIX inizia qui. Ora cerchiamo la fine del messaggio: 10=XXX<SOH>
        # SOH è 0x01
        
        # Un messaggio FIX ha una struttura BeginString (8=), BodyLength (9=), MsgType (35=), ... CheckSum (10=XXX)
        # Il BodyLength (Tag 9) è la lunghezza tra SOH dopo MsgType e SOH prima del CheckSum
        # Questo è il modo più affidabile per trovare la fine senza indovinare
        
        # Cerchiamo 9= (BodyLength)
        tag_9_pos_start = fix_payload.find(b'9=', start_tag_8_pos)
        if tag_9_pos_start == -1 or tag_9_pos_start > start_tag_8_pos + 20: # Limita la ricerca a inizio messaggio
            current_pos = start_tag_8_pos + 1 # Messaggio malformato, prova dal prossimo byte
            continue

        tag_9_val_start = tag_9_pos_start + 2 # Inizio del valore di BodyLength
        
        # Trova la fine del valore di BodyLength (carattere SOH)
        soh_after_tag_9 = fix_payload.find(b'\x01', tag_9_val_start)
        if soh_after_tag_9 == -1:
            current_pos = start_tag_8_pos + 1 # Messaggio malformato
            continue

        try:
            body_length_str = fix_payload[tag_9_val_start:soh_after_tag_9].decode('ascii')
            body_length = int(body_length_str)
        except (ValueError, UnicodeDecodeError):
            current_pos = start_tag_8_pos + 1 # Valore di BodyLength non valido
            continue

        # La lunghezza del messaggio FIX completo include:
        # 1. BeginString (8=FIX.x.y<SOH>) -> Lunghezza fissa (es. 9 byte per FIX.4.2)
        # 2. BodyLength (9=length<SOH>) -> Lunghezza variabile
        # 3. Il corpo del messaggio (specificato da BodyLength)
        # 4. CheckSum (10=XXX<SOH>) -> Lunghezza fissa (7 bytes: "10=XXX\x01")

        # FIX.4.2: "8=FIX.4.2\x01" è 9 byte
        # "9=LEN\x01" + BodyLength + "10=CHK\x01" (7 byte)
        
        # L'offset di BodyLength (Tag 9) rispetto all'inizio del messaggio (Tag 8)
        len_prefix_before_body = (soh_after_tag_9 - start_tag_8_pos) + 7 # Lunghezza di "8=..." + "9=LEN<SOH>" + "10=XXX<SOH>"

        # L'inizio del corpo del messaggio (dopo 9=LEN<SOH>) è soh_after_tag_9 + 1
        # La fine prevista del messaggio dovrebbe essere l'inizio del corpo + body_length + lunghezza del CheckSum (7 bytes: 10=XXX<SOH>)
        expected_msg_end = (soh_after_tag_9 + 1) + body_length + 7 
        
        if expected_msg_end <= len(fix_payload):
            # Trovato un messaggio completo, il CheckSum finale dovrebbe essere qui
            # Possiamo fare una verifica leggera del CheckSum per maggiore robustezza
            # Se il byte precedente a expected_msg_end è SOH (0x01)
            # E i 7 byte precedenti a expected_msg_end sono "10=XXX\x01"
            if fix_payload[expected_msg_end - 1] == 0x01 and \
               fix_payload[expected_msg_end - 7 : expected_msg_end - 4] == b'10=':
                return expected_msg_end
        
        current_pos = start_tag_8_pos + 1 # Messaggio incompleto o malformato, riprova dal prossimo byte

# --- PROGRAMMA PRINCIPALE ---

def main():
    if not os.path.exists(PCAP_FILE):
        print(f"Errore: Il file PCAP '{PCAP_FILE}' non trovato nella directory corrente.")
        print("Assicurati di aver scaricato 'fix.pcap' e posizionato qui.")
        return

    print(f"Inizio analisi del file PCAP: {PCAP_FILE}")
    
    try:
        packets = rdpcap(PCAP_FILE) # Carica tutti i pacchetti dal file PCAP
    except Exception as e:
        print(f"Errore durante la lettura del file PCAP: {e}")
        print("Assicurati che il file sia valido e non corrotto.")
        return

    print(f"Trovati {len(packets)} pacchetti nel PCAP.")

    processed_tcp_segments_count = 0
    generated_blocks_count = 0
    processed_fix_messages_count = 0 # Contatore per i messaggi FIX individuali

    with open(OUTPUT_FILE, 'w') as f_out:
        for pkt_idx, pkt in enumerate(packets):
            if pkt.haslayer(TCP):
                tcp_payload = bytes(pkt[TCP].payload)
                
                if not tcp_payload:
                    continue # Salta i pacchetti TCP senza payload

                processed_tcp_segments_count += 1
                
                current_fix_offset = 0
                while current_fix_offset < len(tcp_payload):
                    # Cerca la fine del prossimo messaggio FIX nel payload TCP rimanente
                    remaining_payload = tcp_payload[current_fix_offset:]
                    
                    msg_end_relative = find_fix_message_end(remaining_payload)
                    
                    if msg_end_relative == -1:
                        # Nessun messaggio FIX completo trovato nel rimanente payload.
                        # Questo può succedere se c'è traffico non FIX, o un messaggio parziale alla fine.
                        # Per ora, ignoriamo il resto del payload. Potresti voler loggare un warning.
                        # print(f"AVVISO: Pacchetto {pkt_idx}, payload TCP parziale o non FIX valido.")
                        break # Esci dal while e passa al prossimo pacchetto TCP

                    # Abbiamo trovato un messaggio FIX completo
                    single_fix_message_bytes = remaining_payload[:msg_end_relative]
                    processed_fix_messages_count += 1
                    
                    fix_message_len = len(single_fix_message_bytes)
                    
                    # Calcola quanti blocchi di 512 bit (64 byte) servono per questo singolo messaggio FIX
                    num_blocks_for_message = math.ceil(fix_message_len / BLOCK_SIZE_BYTES)

                    # Dividi il singolo messaggio FIX in blocchi di 64 byte
                    for block_idx in range(num_blocks_for_message):
                        start_byte = block_idx * BLOCK_SIZE_BYTES
                        end_byte = min((block_idx + 1) * BLOCK_SIZE_BYTES, fix_message_len)
                        
                        current_block_bytes = single_fix_message_bytes[start_byte:end_byte]
                        actual_block_len_bytes = len(current_block_bytes)

                        padded_block_bytes = list(current_block_bytes) + [0x00] * (BLOCK_SIZE_BYTES - actual_block_len_bytes)
                        data_hex_str = byte_array_to_hex_string(padded_block_bytes)

                        kstrb_hex_str = generate_kstrb(actual_block_len_bytes)

                        # Imposta pkt_last_in: 1 se è l'ultimo blocco di QUESTO SINGOLO MESSAGGIO FIX, altrimenti 0
                        pkt_last_val = 1 if (block_idx == num_blocks_for_message - 1) else 0

                        f_out.write(f"{data_hex_str},{kstrb_hex_str},{pkt_last_val}\n")
                        generated_blocks_count += 1
                    
                    # Sposta l'offset per cercare il prossimo messaggio FIX all'interno dello stesso payload TCP
                    current_fix_offset += msg_end_relative
                
    print(f"\nGenerazione completata.")
    print(f"Processati {processed_tcp_segments_count} segmenti TCP con payload.")
    print(f"Identificati e processati {processed_fix_messages_count} messaggi FIX individuali.")
    print(f"Generati {generated_blocks_count} blocchi di {PKT_DATA_WIDTH} bit per il tuo testbench C in '{OUTPUT_FILE}'.")
    print(f"Ora puoi usare '{OUTPUT_FILE}' come input per il tuo programma C.")

if __name__ == "__main__":
    main()
