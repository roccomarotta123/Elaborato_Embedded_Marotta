`timescale 1ns / 1ps



// Importa il package per accedere ai parametri

import traffic_manager_pkg::*;



module top_level_wrapper (

    input logic clk,
    input logic reset_n,

    // Questi sono gli UNICI I/O che andranno sui pin fisici della FPGA.
    // Tipicamente sono clock, reset, e magari interfacce di controllo/debug.
    // L'interfaccia AXI-Stream principale per i dati dei pacchetti
    // e l'interfaccia per la configurazione delle regole
    // saranno gestite INTERNAMENTE da altri IP (es. CMAC, AXI-Lite IP).
    // Esempio di un output aggregato se vuoi vedere un risultato finale

    output logic aggregated_match_out //  final_sop_match_out

);



    // =====================================================================

    // SEGNALI INTERNI CHE CONNETTONO IL TOP-LEVEL CON IL match_engine

    // Questi NON diventano I/O fisici della FPGA

    // =====================================================================



    // AXI-Stream per i pacchetti: questi provengono DA un CMAC o un DMA, non dai pin!

    logic [AXI_STREAM_DATA_WIDTH-1:0] pkt_data_in_i;
    logic [AXI_STREAM_KSTRB_WIDTH-1:0] pkt_kstrb_in_i;
    logic                               pkt_last_in_i;
    logic                               pkt_valid_in_i;
    logic                               pkt_ready_out_i; // Questo è l'output del match_engine ma è collegato internamente



    // Array delle regole: queste sono caricate da un controllore interno (es. AXI-Lite Slave)

    rule_entry_t rules_in_i [NUM_RULES-1:0];



    // Risultati dei match: questi vengono usati INTERNAMENTE per altre logiche o bufferizzati

    logic [NUM_RULES-1:0]               tx_match_valid_out_i;
    logic [NUM_RULES-1:0][31:0]         tx_packet_addr_list_out_i; // Questo è il problema principale per gli I/O
    logic [$clog2(NUM_RULES+1)-1:0]     tx_num_matches_out_i;



    // Segnali per la logica AND/OR (generalmente configurati via AXI-Lite o costanti)

    logic [NUM_RULES-1:0]               rule_logic_mask_and_in_i;
    logic [NUM_RULES-1:0]               rule_logic_mask_or_in_i;
    logic                               final_match_logic_enable_in_i;
    logic                               res_mask_and_i;
    logic [NUM_RULES-1:0]               res_mask_or_i;



    // Segnali per la logica SOP (generalmente configurati via AXI-Lite o costanti)

    logic [MAX_SOP_TERMS-1:0][NUM_RULES-1:0] sop_term_masks_in_i;
    logic [MAX_SOP_TERMS-1:0]           sop_term_enable_in_i;
    logic                               sop_logic_enable_in_i;
    logic                               final_sop_match_out_i;



    // =====================================================================

    // ISTANZIAZIONE DEL DUT (match_engine)

    // =====================================================================
    (* DONT_TOUCH = "TRUE" *)
    match_engine #(
        .PKT_DATA_WIDTH(AXI_STREAM_DATA_WIDTH),
        .PKT_KSTRB_WIDTH(AXI_STREAM_KSTRB_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .pkt_data_in(pkt_data_in_i),
        .pkt_kstrb_in(pkt_kstrb_in_i),
        .pkt_last_in(pkt_last_in_i),
        .pkt_valid_in(pkt_valid_in_i),
        .pkt_ready_out(pkt_ready_out_i),
        .rules_in(rules_in_i),
        .tx_match_valid_out(tx_match_valid_out_i),
        .tx_packet_addr_list_out(tx_packet_addr_list_out_i),
        .tx_num_matches_out(tx_num_matches_out_i),
        .rule_logic_mask_and_in(rule_logic_mask_and_in_i),
        .rule_logic_mask_or_in(rule_logic_mask_or_in_i),
        .final_match_logic_enable_in(final_match_logic_enable_in_i),
        .res_mask_and(res_mask_and_i),
        .res_mask_or(res_mask_or_i),
        .sop_term_masks_in(sop_term_masks_in_i),
        .sop_term_enable_in(sop_term_enable_in_i),
        .sop_logic_enable_in(sop_logic_enable_in_i),
        .final_sop_match_out(final_sop_match_out_i)

    );



   

    // In un sistema reale, sarebbero connessi ad altri IP

    assign pkt_data_in_i = '0; // Dati a zero (il match non avverrà)
    assign pkt_kstrb_in_i = '0;
    assign pkt_last_in_i = 1'b0;
    assign pkt_valid_in_i = 1'b0;



    // Regole: usare un blocco RAM configurabile via AXI-Lite

    // Per un test di area, Vivado inferirà i registri anche se non vengono scritti dinamicamente.

    genvar i;
    generate
        for (i = 0; i < NUM_RULES; i++) begin : init_rules
            assign rules_in_i[i] = '{addr: '0, value: '0, symbol: EQ, packet_tx_addr: '0, enable: 1'b0};
        end
    endgenerate



    // Maschere logiche:

    assign rule_logic_mask_and_in_i = '0;
    assign rule_logic_mask_or_in_i = '0;
    assign final_match_logic_enable_in_i = 1'b0;
    assign sop_term_masks_in_i = '0;
    assign sop_term_enable_in_i = '0;
    assign sop_logic_enable_in_i = 1'b1; // Abilita SOP per testare quella logica



    // Connetti l'output desiderato al pin top-level

    assign aggregated_match_out = final_sop_match_out_i;



    



endmodule