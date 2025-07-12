// File: traffic_manager_pkg.sv

package traffic_manager_pkg;

    // =====================================================================
    // PARAMETERS GLOBALI
    // =====================================================================
    parameter NUM_RULES = 16;
    parameter RULE_ADDR_WIDTH = $clog2(NUM_RULES);

    // Parametri per l'interfaccia AXI4-Lite Slave (per la configurazione delle regole)
    parameter AXI_LITE_ADDR_WIDTH = 12;
    parameter AXI_LITE_DATA_WIDTH = 32;

    // Parametri per l'interfaccia AXI4-Stream (per i pacchetti di dati)
    parameter AXI_STREAM_DATA_WIDTH = 512;
    parameter AXI_STREAM_KSTRB_WIDTH = (AXI_STREAM_DATA_WIDTH / 8);


    // La dimensione massima prevista del pacchetto in byte.
    // Usata per dimensionare correttamente gli offset.
    // Esempio: 4096 bytes (4KB) se i pacchetti possono essere grandi.
    parameter PACKET_MAX_SIZE = 4096; // Definisci la dimensione massima del pacchetto in byte
    // *********************************************************************

    // =====================================================================
    // TIPI DI DATI (TYPEDEFS) GLOBALI
    // =====================================================================
    typedef enum bit [2:0] {
        EQ = 3'b000,
        GT = 3'b001,
        LT = 3'b010,
        GE = 3'b011,
        LE = 3'b100
    } compare_symbol_e;

    typedef struct packed {
        logic [11:0] addr;
        logic [7:0]  value;
        compare_symbol_e symbol;
        logic [31:0] packet_tx_addr;
        logic        enable;
    } rule_entry_t;

    // =====================================================================
    // MAPPATURA AXI-LITE PER rule_entry_t (COME I REGISTRI VERRANNO SCRITTI/LETTI)
    // Questa sezione rimane un riferimento cruciale per il software!
    // =====================================================================
    // rules_axi_reg[rule_idx][0] (Word 0):
    // { (8'b0), addr[11:0], value[7:0], symbol[2:0], enable[0:0] }

    // rules_axi_reg[rule_idx][1] (Word 1):
    // { packet_tx_addr[31:0] }

    localparam RULE_WORD0_OFFSET = 0;
    localparam RULE_WORD1_OFFSET = 4;
    localparam RULE_BYTE_SIZE = 8;

endpackage