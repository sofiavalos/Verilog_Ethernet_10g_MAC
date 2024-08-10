/*

Copyright (c) 2015-2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 10G Ethernet MAC
 */
module eth_mac_10g #
(
    parameter DATA_WIDTH = 64,                                    //! Ancho de datos
    parameter KEEP_WIDTH = (DATA_WIDTH/8),                        //! Ancho de bits válidos
    parameter CTRL_WIDTH = (DATA_WIDTH/8),                        //! Ancho de control
    parameter ENABLE_PADDING = 1,                                 //! Flag para habilitar padding
    parameter ENABLE_DIC = 1,                                     //! Flag para habilitar DIC (Data Integrity Check)
    parameter MIN_FRAME_LENGTH = 64,                              //! Longitud mínima de trama
    parameter PTP_TS_ENABLE = 0,                                  //! Flag para habilitar marca de tiempo PTP
    parameter PTP_TS_FMT_TOD = 1,                                 //! Formato de marca de tiempo PTP
    parameter PTP_TS_WIDTH = PTP_TS_FMT_TOD ? 96 : 64,            //! Ancho de marca de tiempo PTP
    parameter TX_PTP_TS_CTRL_IN_TUSER = 0,                        //! Control de marca de tiempo PTP en TUSER
    parameter TX_PTP_TAG_ENABLE = PTP_TS_ENABLE,                  //! Habilitar etiqueta PTP en transmisión
    parameter TX_PTP_TAG_WIDTH = 16,                              //! Ancho de etiqueta PTP en transmisión
    parameter TX_USER_WIDTH = (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? TX_PTP_TAG_WIDTH : 0) + (TX_PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1, //! Ancho de datos de usuario en transmisión
    parameter RX_USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1, //! Ancho de datos de usuario en recepción
    parameter PFC_ENABLE = 0,                                         //! Flag para habilitar control de flujo prioritario (PFC)
    parameter PAUSE_ENABLE = PFC_ENABLE                               //! Flag para habilitar pausa de control de flujo (LFC)
)
(
    input  wire                         rx_clk,                   //! Señal de clock del receptor
    input  wire                         rx_rst,                   //! Señal de reset del receptor
    input  wire                         tx_clk,                   //! Señal de clock del transmisor
    input  wire                         tx_rst,                   //! Señal de reset del transmisor

    /*
     * AXI input
     */
    input  wire [DATA_WIDTH-1:0]        tx_axis_tdata,            //! Datos de la interfaz AXI del transmisor
    input  wire [KEEP_WIDTH-1:0]        tx_axis_tkeep,            //! Bits válidos de la interfaz AXI del transmisor
    input  wire                         tx_axis_tvalid,           //! Señal de datos válidos de la interfaz AXI del transmisor
    output wire                         tx_axis_tready,           //! Señal de ready de la interfaz AXI del transmisor
    input  wire                         tx_axis_tlast,            //! Señal de fin de trama de la interfaz AXI del transmisor
    input  wire [TX_USER_WIDTH-1:0]     tx_axis_tuser,            //! Datos de usuario de la interfaz AXI del transmisor

    /*
     * AXI output
     */
    output wire [DATA_WIDTH-1:0]        rx_axis_tdata,            //! Datos de la interfaz AXI del receptor
    output wire [KEEP_WIDTH-1:0]        rx_axis_tkeep,            //! Bits válidos de la interfaz AXI del receptor
    output wire                         rx_axis_tvalid,           //! Señal de datos válidos de la interfaz AXI del receptor
    output wire                         rx_axis_tlast,            //! Señal de fin de trama de la interfaz AXI del receptor
    output wire [RX_USER_WIDTH-1:0]     rx_axis_tuser,            //! Datos de usuario de la interfaz AXI del receptor

    /*
     * XGMII interface
     */
    input  wire [DATA_WIDTH-1:0]        xgmii_rxd,                //! Datos recibidos de la interfaz XGMII
    input  wire [CTRL_WIDTH-1:0]        xgmii_rxc,                //! Datos de control recibidos de la interfaz XGMII
    output wire [DATA_WIDTH-1:0]        xgmii_txd,                //! Datos transmitidos de la interfaz XGMII
    output wire [CTRL_WIDTH-1:0]        xgmii_txc,                //! Datos de control transmitidos de la interfaz XGMII

    /*
     * PTP
     */
    input  wire [PTP_TS_WIDTH-1:0]      tx_ptp_ts,                //! Marca de tiempo PTP del transmisor
    input  wire [PTP_TS_WIDTH-1:0]      rx_ptp_ts,                //! Marca de tiempo PTP del receptor
    output wire [PTP_TS_WIDTH-1:0]      tx_axis_ptp_ts,           //! Marca de tiempo PTP en interfaz AXI del transmisor
    output wire [TX_PTP_TAG_WIDTH-1:0]  tx_axis_ptp_ts_tag,       //! Etiqueta de marca de tiempo PTP en interfaz AXI del transmisor
    output wire                         tx_axis_ptp_ts_valid,     //! Señal de datos válidos de marca de tiempo PTP en interfaz AXI del transmisor

    /*
     * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
     */
    input  wire                         tx_lfc_req,               //! Solicitud de pausa de control de flujo en el transmisor
    input  wire                         tx_lfc_resend,            //! Reenvío de solicitud de pausa de control de flujo en el transmisor
    input  wire                         rx_lfc_en,                //! Habilitación de pausa de control de flujo en el receptor
    output wire                         rx_lfc_req,               //! Solicitud de pausa de control de flujo en el receptor
    input  wire                         rx_lfc_ack,               //! Reconocimiento de pausa de control de flujo en el receptor

    /*
     * Priority Flow Control (PFC) (IEEE 802.3 annex 31D PFC)
     */
    input  wire [7:0]                   tx_pfc_req,               //! Solicitud de control de flujo prioritario el transmisor
    input  wire                         tx_pfc_resend,            //! Reenvío de solicitud de control de flujo prioritario el transmisor
    input  wire [7:0]                   rx_pfc_en,                //! Habilitación de control de flujo prioritario en el receptor
    output wire [7:0]                   rx_pfc_req,               //! Solicitud de control de flujo prioritario en el receptor
    input  wire [7:0]                   rx_pfc_ack,               //! Reconocimiento de control de flujo prioritario en el receptor

    /*
     * Pause interface
     */
    input  wire                         tx_lfc_pause_en,          //! Habilitación de pausa de control de flujo el transmisor
    input  wire                         tx_pause_req,             //! Solicitud de pausa el transmisor
    output wire                         tx_pause_ack,             //! Reconocimiento de pausa el transmisor

    /*
     * Status
     */
    output wire [1:0]                   tx_start_packet,          //! Estado de inicio de paquete en el transmisor
    output wire                         tx_error_underflow,       //! Error de subflujo en el transmisor
    output wire [1:0]                   rx_start_packet,          //! Estado de inicio de paquete en el receptor
    output wire                         rx_error_bad_frame,       //! Error de trama incorrecta en el receptor
    output wire                         rx_error_bad_fcs,         //! Error de FCS incorrecto en el receptor
    output wire                         stat_tx_mcf,              //! Estado que indica la transmisión de un marco de control MAC.
    output wire                         stat_rx_mcf,              //! Estado que indica la recepción de un marco de control MAC.
    output wire                         stat_tx_lfc_pkt,          //! Estado que indica la transmisión de un paquete LFC.
    output wire                         stat_tx_lfc_xon,          //! Estado que indica la transmisión de una señal XON en LFC.
    output wire                         stat_tx_lfc_xoff,         //! Estado que indica la transmisión de una señal XOFF en LFC.
    output wire                         stat_tx_lfc_paused,       //! Estado que indica que la transmisión está pausada debido a LFC.
    output wire                         stat_tx_pfc_pkt,          //! Estado que indica la transmisión de un paquete PFC.
    output wire [7:0]                   stat_tx_pfc_xon,          //! Estado que indica la transmisión de una señal XON en PFC para cada prioridad.
    output wire [7:0]                   stat_tx_pfc_xoff,         //! Estado que indica la transmisión de una señal XOFF en PFC para cada prioridad.
    output wire [7:0]                   stat_tx_pfc_paused,       //! Estado que indica que la transmisión está pausada debido a PFC para cada prioridad.
    output wire                         stat_rx_lfc_pkt,          //! Estado que indica la recepción de un paquete LFC.
    output wire                         stat_rx_lfc_xon,          //! Estado que indica la recepción de una señal XON en LFC.
    output wire                         stat_rx_lfc_xoff,         //! Estado que indica la recepción de una señal XOFF en LFC.
    output wire                         stat_rx_lfc_paused,       //! Estado que indica que la recepción está pausada debido a LFC.
    output wire                         stat_rx_pfc_pkt,          //! Estado que indica la recepción de un paquete PFC.
    output wire [7:0]                   stat_rx_pfc_xon,          //! Estado que indica la recepción de una señal XON en PFC para cada prioridad.
    output wire [7:0]                   stat_rx_pfc_xoff,         //! Estado que indica la recepción de una señal XOFF en PFC para cada prioridad.
    output wire [7:0]                   stat_rx_pfc_paused        //! Estado que indica que la recepción está pausada debido a PFC para cada prioridad.
    
    /*
     * Configuration
     */
    input  wire [7:0]                   cfg_ifg,                                //! Configuración de IFG
    input  wire                         cfg_tx_enable,                          //! Habilitación del transmisor
    input  wire                         cfg_rx_enable,                          //! Habilitación del receptor
    input  wire [47:0]                  cfg_mcf_rx_eth_dst_mcast,               //! Dirección multicast Ethernet del receptor MCF (Filtro de Multidifusión)
    input  wire                         cfg_mcf_rx_check_eth_dst_mcast,         //! Verificación de dirección multicast Ethernet del receptor MCF
    input  wire [47:0]                  cfg_mcf_rx_eth_dst_ucast,               //! Dirección unicast Ethernet del receptor MCF
    input  wire                         cfg_mcf_rx_check_eth_dst_ucast,         //! Verificación de dirección unicast Ethernet del receptor MCF
    input  wire [47:0]                  cfg_mcf_rx_eth_src,                     //! Dirección de origen Ethernet del receptor MCF
    input  wire                         cfg_mcf_rx_check_eth_src,               //! Verificación de dirección de origen Ethernet del receptor MCF
    input  wire [15:0]                  cfg_mcf_rx_eth_type,                    //! Tipo Ethernet del receptor MCF
    input  wire [15:0]                  cfg_mcf_rx_opcode_lfc,                  //! Código de operación LFC del receptor MCF
    input  wire                         cfg_mcf_rx_check_opcode_lfc,            //! Verificación de código de operación LFC del receptor MCF
    input  wire [15:0]                  cfg_mcf_rx_opcode_pfc,                  //! Código de operación PFC del receptor MCF
    input  wire                         cfg_mcf_rx_check_opcode_pfc,            //! Verificación de código de operación PFC del receptor MCF
    input  wire                         cfg_mcf_rx_forward,                     //! Reenvío del receptor MCF
    input  wire                         cfg_mcf_rx_enable,                      //! Habilitación del receptor MCF
    input  wire [47:0]                  cfg_tx_lfc_eth_dst,                     //! Dirección Ethernet de pausa de control de flujo en el transmisor
    input  wire [47:0]                  cfg_tx_lfc_eth_src,                     //! Dirección de origen Ethernet de pausa de control de flujo en el transmisor
    input  wire [15:0]                  cfg_tx_lfc_eth_type,                    //! Tipo Ethernet de pausa de control de flujo en el transmisor
    input  wire [15:0]                  cfg_tx_lfc_opcode,                      //! Código de operación de pausa de control de flujo en el transmisor
    input  wire                         cfg_tx_lfc_en,                          //! Habilitación de pausa de control de flujo en el transmisor
    input  wire [15:0]                  cfg_tx_lfc_quanta,                      //! Cuánta de pausa de control de flujo en el transmisor
    input  wire [15:0]                  cfg_tx_lfc_refresh,                     //! Actualización de pausa de control de flujo en el transmisor
    input  wire [47:0]                  cfg_tx_pfc_eth_dst,                     //! Dirección Ethernet de control de flujo prioritario en el transmisor
    input  wire [47:0]                  cfg_tx_pfc_eth_src,                     //! Dirección de origen Ethernet de control de flujo prioritario en el transmisor
    input  wire [15:0]                  cfg_tx_pfc_eth_type,                    //! Tipo Ethernet de control de flujo prioritario en el transmisor
    input  wire [15:0]                  cfg_tx_pfc_opcode,                      //! Código de operación de control de flujo prioritario en el transmisor
    input  wire                         cfg_tx_pfc_en,                          //! Habilitación de control de flujo prioritario en el transmisor
    input  wire [8*16-1:0]              cfg_tx_pfc_quanta,                      //! Cuánta de control de flujo prioritario en el transmisor
    input  wire [8*16-1:0]              cfg_tx_pfc_refresh,                     //! Actualización de control de flujo prioritario en el transmisor
    input  wire [15:0]                  cfg_rx_lfc_opcode,                      //! Código de operación de pausa de control de flujo en el receptor
    input  wire                         cfg_rx_lfc_en,                          //! Habilitación de pausa de control de flujo en el receptor
    input  wire [15:0]                  cfg_rx_pfc_opcode,                      //! Código de operación de control de flujo prioritario en el receptor
    input  wire                         cfg_rx_pfc_en                           //! Habilitación de control de flujo prioritario en el receptor
);

parameter MAC_CTRL_ENABLE = PAUSE_ENABLE || PFC_ENABLE;  //! Habilitación del controlador MAC
parameter TX_USER_WIDTH_INT = MAC_CTRL_ENABLE ? (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? TX_PTP_TAG_WIDTH : 0) + 1 : 0) + 1 : TX_USER_WIDTH; //! Ancho de datos de usuario interno en transmisión

// bus width assertions
initial begin
    if (DATA_WIDTH != 32 && DATA_WIDTH != 64) begin
        $error("Error: Interface width must be 32 or 64");
        $finish;
    end

    if (KEEP_WIDTH * 8 != DATA_WIDTH || CTRL_WIDTH * 8 != DATA_WIDTH) begin
        $error("Error: Interface requires byte (8-bit) granularity");
        $finish;
    end
end

wire [DATA_WIDTH-1:0]         tx_axis_tdata_int;       //! Datos de salida internos de la interfaz AXI en el transmisor
wire [KEEP_WIDTH-1:0]         tx_axis_tkeep_int;       //! Bits válidos de salida internos de la interfaz AXI en el transmisor
wire                          tx_axis_tvalid_int;      //! Señal de datos válidos interna de la interfaz AXI en el transmisor
wire                          tx_axis_tready_int;      //! Flag de ready para recibir datos interna de la interfaz AXI en el transmisor
wire                          tx_axis_tlast_int;       //! Flag de fin de trama interna de la interfaz AXI en el transmisor
wire [TX_USER_WIDTH_INT-1:0]  tx_axis_tuser_int;       //! Datos de usuario internos de la interfaz AXI en el transmisor

wire [DATA_WIDTH-1:0]     rx_axis_tdata_int;           //! Datos de entrada internos de la interfaz AXI en el receptor
wire [KEEP_WIDTH-1:0]     rx_axis_tkeep_int;           //! Bits válidos de entrada internos de la interfaz AXI en el receptor
wire                      rx_axis_tvalid_int;          //! Flag de datos válidos interna de la interfaz AXI en el receptor
wire                      rx_axis_tlast_int;           //! Flag de fin de trama interna de la interfaz AXI en el receptor
wire [RX_USER_WIDTH-1:0]  rx_axis_tuser_int;           //! Datos de usuario internos de la interfaz AXI en el receptor

generate

if (DATA_WIDTH == 64) begin
//! Instanciación de la interfaz AXI del receptor para 64 bits
axis_xgmii_rx_64 #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_WIDTH(KEEP_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .PTP_TS_FMT_TOD(PTP_TS_FMT_TOD),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .USER_WIDTH(RX_USER_WIDTH)
)
axis_xgmii_rx_inst (
    .clk(rx_clk),
    .rst(rx_rst),
    .xgmii_rxd(xgmii_rxd),
    .xgmii_rxc(xgmii_rxc),
    .m_axis_tdata(rx_axis_tdata_int),
    .m_axis_tkeep(rx_axis_tkeep_int),
    .m_axis_tvalid(rx_axis_tvalid_int),
    .m_axis_tlast(rx_axis_tlast_int),
    .m_axis_tuser(rx_axis_tuser_int),
    .ptp_ts(rx_ptp_ts),
    .cfg_rx_enable(cfg_rx_enable),
    .start_packet(rx_start_packet),
    .error_bad_frame(rx_error_bad_frame),
    .error_bad_fcs(rx_error_bad_fcs)
);

//! Instanciación de la interfaz AXI del transmisor para 64 bits
axis_xgmii_tx_64 #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_WIDTH(KEEP_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .ENABLE_PADDING(ENABLE_PADDING),
    .ENABLE_DIC(ENABLE_DIC),
    .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .PTP_TS_FMT_TOD(PTP_TS_FMT_TOD),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .PTP_TS_CTRL_IN_TUSER(MAC_CTRL_ENABLE ? PTP_TS_ENABLE : TX_PTP_TS_CTRL_IN_TUSER),
    .PTP_TAG_ENABLE(TX_PTP_TAG_ENABLE),
    .PTP_TAG_WIDTH(TX_PTP_TAG_WIDTH),
    .USER_WIDTH(TX_USER_WIDTH_INT)
)
axis_xgmii_tx_inst (
    .clk(tx_clk),
    .rst(tx_rst),
    .s_axis_tdata(tx_axis_tdata_int),
    .s_axis_tkeep(tx_axis_tkeep_int),
    .s_axis_tvalid(tx_axis_tvalid_int),
    .s_axis_tready(tx_axis_tready_int),
    .s_axis_tlast(tx_axis_tlast_int),
    .s_axis_tuser(tx_axis_tuser_int),
    .xgmii_txd(xgmii_txd),
    .xgmii_txc(xgmii_txc),
    .ptp_ts(tx_ptp_ts),
    .m_axis_ptp_ts(tx_axis_ptp_ts),
    .m_axis_ptp_ts_tag(tx_axis_ptp_ts_tag),
    .m_axis_ptp_ts_valid(tx_axis_ptp_ts_valid),
    .cfg_ifg(cfg_ifg),
    .cfg_tx_enable(cfg_tx_enable),
    .start_packet(tx_start_packet),
    .error_underflow(tx_error_underflow)
);

end else begin

//! Instanciación de la interfaz AXI del receptor para 32 bits
axis_xgmii_rx_32 #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_WIDTH(KEEP_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .USER_WIDTH(RX_USER_WIDTH)
)
axis_xgmii_rx_inst (
    .clk(rx_clk),
    .rst(rx_rst),
    .xgmii_rxd(xgmii_rxd),
    .xgmii_rxc(xgmii_rxc),
    .m_axis_tdata(rx_axis_tdata_int),
    .m_axis_tkeep(rx_axis_tkeep_int),
    .m_axis_tvalid(rx_axis_tvalid_int),
    .m_axis_tlast(rx_axis_tlast_int),
    .m_axis_tuser(rx_axis_tuser_int),
    .ptp_ts(rx_ptp_ts),
    .cfg_rx_enable(cfg_rx_enable),
    .start_packet(rx_start_packet[0]),
    .error_bad_frame(rx_error_bad_frame),
    .error_bad_fcs(rx_error_bad_fcs)
);

assign rx_start_packet[1] = 1'b0;

//! Instanciación de la interfaz AXI del transmisor para 32 bits
axis_xgmii_tx_32 #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_WIDTH(KEEP_WIDTH),
    .CTRL_WIDTH(CTRL_WIDTH),
    .ENABLE_PADDING(ENABLE_PADDING),
    .ENABLE_DIC(ENABLE_DIC),
    .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH),
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .PTP_TS_CTRL_IN_TUSER(MAC_CTRL_ENABLE ? PTP_TS_ENABLE : TX_PTP_TS_CTRL_IN_TUSER),
    .PTP_TAG_ENABLE(TX_PTP_TAG_ENABLE),
    .PTP_TAG_WIDTH(TX_PTP_TAG_WIDTH),
    .USER_WIDTH(TX_USER_WIDTH_INT)
)
axis_xgmii_tx_inst (
    .clk(tx_clk),
    .rst(tx_rst),
    .s_axis_tdata(tx_axis_tdata_int),
    .s_axis_tkeep(tx_axis_tkeep_int),
    .s_axis_tvalid(tx_axis_tvalid_int),
    .s_axis_tready(tx_axis_tready_int),
    .s_axis_tlast(tx_axis_tlast_int),
    .s_axis_tuser(tx_axis_tuser_int),
    .xgmii_txd(xgmii_txd),
    .xgmii_txc(xgmii_txc),
    .ptp_ts(tx_ptp_ts),
    .m_axis_ptp_ts(tx_axis_ptp_ts),
    .m_axis_ptp_ts_tag(tx_axis_ptp_ts_tag),
    .m_axis_ptp_ts_valid(tx_axis_ptp_ts_valid),
    .cfg_ifg(cfg_ifg),
    .cfg_tx_enable(cfg_tx_enable),
    .start_packet(tx_start_packet[0]),
    .error_underflow(tx_error_underflow)
);

assign tx_start_packet[1] = 1'b0;

end

if (MAC_CTRL_ENABLE) begin : mac_ctrl

    localparam MCF_PARAMS_SIZE = PFC_ENABLE ? 18 : 2;

    wire                          tx_mcf_valid;               //! Flag que indica si el marco de control MAC (MCF) de transmisión es válido
    wire                          tx_mcf_ready;               //! Flag que indica si el módulo está listo para aceptar un MCF del transmisor
    wire [47:0]                   tx_mcf_eth_dst;             //! Dirección MAC de destino del MCF del transmisor
    wire [47:0]                   tx_mcf_eth_src;             //! Dirección MAC de origen del MCF del transmisor
    wire [15:0]                   tx_mcf_eth_type;            //! Tipo Ethernet del MCF del transmisor
    wire [15:0]                   tx_mcf_opcode;              //! Opcode del MCF del transmisor
    wire [MCF_PARAMS_SIZE*8-1:0]  tx_mcf_params;              //! Parámetros del MCF del transmisor

    wire                          rx_mcf_valid;               //! Flag que indica si el marco de control MAC (MCF) del receptor es válido
    wire [47:0]                   rx_mcf_eth_dst;             //! Dirección MAC de destino del MCF del receptor
    wire [47:0]                   rx_mcf_eth_src;             //! Dirección MAC de origen del MCF del receptor
    wire [15:0]                   rx_mcf_eth_type;            //! Tipo Ethernet del MCF del receptor
    wire [15:0]                   rx_mcf_opcode;              //! Opcode del MCF del receptor
    wire [MCF_PARAMS_SIZE*8-1:0]  rx_mcf_params;              //! Parámetros del MCF del receptor

    // terminate LFC pause requests from RX internally on TX side
    wire                          tx_pause_req_int;           //! Señal interna para las solicitudes de pausa LFC en el lado del transmisor
    wire                          rx_lfc_ack_int;             //! Señal interna de reconocimiento de pausa LFC en el lado del receptor

    reg tx_lfc_req_sync_reg_1 = 1'b0;                         //! Registro de sincronización de la solicitud de pausa LFC del transmisor (etapa 1)
    reg tx_lfc_req_sync_reg_2 = 1'b0;                         //! Registro de sincronización de la solicitud de pausa LFC del transmisor (etapa 2)
    reg tx_lfc_req_sync_reg_3 = 1'b0;                         //! Registro de sincronización de la solicitud de pausa LFC del transmisor (etapa 3)


    // Sincronización de la señal de solicitud de pausa LFC de recepción al dominio de reloj de transmisión
    always @(posedge rx_clk or posedge rx_rst) begin
        if (rx_rst) begin
            tx_lfc_req_sync_reg_1 <= 1'b0;    // reinicia el registro de sincronización de la solicitud de pausa LFC de transmisión (etapa 1) al resetear
        end else begin
            tx_lfc_req_sync_reg_1 <= rx_lfc_req; // actualiza el registro de sincronización con la solicitud de pausa LFC de recepción
        end
    end

    always @(posedge tx_clk or posedge tx_rst) begin
        if (tx_rst) begin
            tx_lfc_req_sync_reg_2 <= 1'b0;    // reinicia el registro de sincronización de la solicitud de pausa LFC de transmisión (etapa 2) al resetear
            tx_lfc_req_sync_reg_3 <= 1'b0;    // reinicia el registro de sincronización de la solicitud de pausa LFC de transmisión (etapa 3) al resetear
        end else begin
            tx_lfc_req_sync_reg_2 <= tx_lfc_req_sync_reg_1; // sincroniza la solicitud de pausa LFC al dominio de reloj de transmisión (etapa 2)
            tx_lfc_req_sync_reg_3 <= tx_lfc_req_sync_reg_2; // sincroniza la solicitud de pausa LFC al dominio de reloj de transmisión (etapa 3)
        end
    end


    reg rx_lfc_ack_sync_reg_1 = 1'b0;  //! Reg de sincronización de reconocimiento de pausa LFC de recepción (etapa 1)
    reg rx_lfc_ack_sync_reg_2 = 1'b0;  //! Reg de sincronización de reconocimiento de pausa LFC de recepción (etapa 2)
    reg rx_lfc_ack_sync_reg_3 = 1'b0;  //! Reg de sincronización de reconocimiento de pausa LFC de recepción (etapa 3)
    
    //! Sincronización de la señal de reconocimiento de pausa LFC de transmisión al dominio de reloj de recepción
    always @(posedge tx_clk or posedge tx_rst) begin
        if (tx_rst) begin
            rx_lfc_ack_sync_reg_1 <= 1'b0;    // reinicia el registro de sincronización al resetear
        end else begin
            rx_lfc_ack_sync_reg_1 <= tx_lfc_pause_en ? tx_pause_ack : 0; // actualiza el registro de sincronización con la señal de reconocimiento de pausa LFC
        end
    end
    
    //! Sincronización de la señal de reconocimiento de pausa LFC al dominio de reloj de transmisión
    always @(posedge rx_clk or posedge rx_rst) begin
        if (rx_rst) begin
            rx_lfc_ack_sync_reg_2 <= 1'b0;    // reinicia el registro de sincronización (etapa 2) al resetear
            rx_lfc_ack_sync_reg_3 <= 1'b0;    // reinicia el registro de sincronización (etapa 3) al resetear
        end else begin
            rx_lfc_ack_sync_reg_2 <= rx_lfc_ack_sync_reg_1; // sincroniza la señal de reconocimiento de pausa LFC al dominio de reloj de transmisión (etapa 2)
            rx_lfc_ack_sync_reg_3 <= rx_lfc_ack_sync_reg_2; // sincroniza la señal de reconocimiento de pausa LFC al dominio de reloj de transmisión (etapa 3)
        end
    end
    
    assign tx_pause_req_int = tx_pause_req || (tx_lfc_pause_en ? tx_lfc_req_sync_reg_3 : 0); // asigna la solicitud de pausa interna de transmisión
    
    assign rx_lfc_ack_int = rx_lfc_ack || rx_lfc_ack_sync_reg_3; // asigna el reconocimiento de pausa LFC interno
    
    // manejo del bit de habilitación de PTP TS en tuser
    wire [TX_USER_WIDTH_INT-1:0] tx_axis_tuser_in;  //! Entrada de tuser del eje de transmisión
    
    if (PTP_TS_ENABLE && !TX_PTP_TS_CTRL_IN_TUSER) begin
        assign tx_axis_tuser_in = {tx_axis_tuser[TX_USER_WIDTH-1:1], 1'b1, tx_axis_tuser[0]}; // asigna tuser con el bit de habilitación de PTP TS
    end else begin
        assign tx_axis_tuser_in = tx_axis_tuser; // asigna tuser directamente
    end
    

    //! Instancia el modulo de control MAC del transmisor
    mac_ctrl_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(KEEP_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(TX_USER_WIDTH_INT),
        .MCF_PARAMS_SIZE(MCF_PARAMS_SIZE)
    )
    mac_ctrl_tx_inst (
        .clk(tx_clk),
        .rst(tx_rst),

        /*
         * AXI stream input
         */
        .s_axis_tdata(tx_axis_tdata),
        .s_axis_tkeep(tx_axis_tkeep),
        .s_axis_tvalid(tx_axis_tvalid),
        .s_axis_tready(tx_axis_tready),
        .s_axis_tlast(tx_axis_tlast),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(tx_axis_tuser_in),

        /*
         * AXI stream output
         */
        .m_axis_tdata(tx_axis_tdata_int),
        .m_axis_tkeep(tx_axis_tkeep_int),
        .m_axis_tvalid(tx_axis_tvalid_int),
        .m_axis_tready(tx_axis_tready_int),
        .m_axis_tlast(tx_axis_tlast_int),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(tx_axis_tuser_int),

        /*
         * MAC control frame interface
         */
        .mcf_valid(tx_mcf_valid),
        .mcf_ready(tx_mcf_ready),
        .mcf_eth_dst(tx_mcf_eth_dst),
        .mcf_eth_src(tx_mcf_eth_src),
        .mcf_eth_type(tx_mcf_eth_type),
        .mcf_opcode(tx_mcf_opcode),
        .mcf_params(tx_mcf_params),
        .mcf_id(0),
        .mcf_dest(0),
        .mcf_user(0),

        /*
         * Pause interface
         */
        .tx_pause_req(tx_pause_req_int),
        .tx_pause_ack(tx_pause_ack),

        /*
         * Status
         */
        .stat_tx_mcf(stat_tx_mcf)
    );

    //! Instancia el modulo de control MAC del receptor
    mac_ctrl_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(KEEP_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(RX_USER_WIDTH),
        .USE_READY(0),
        .MCF_PARAMS_SIZE(MCF_PARAMS_SIZE)
    )
    mac_ctrl_rx_inst (
        .clk(rx_clk),
        .rst(rx_rst),

        /*
         * AXI stream input
         */
        .s_axis_tdata(rx_axis_tdata_int),
        .s_axis_tkeep(rx_axis_tkeep_int),
        .s_axis_tvalid(rx_axis_tvalid_int),
        .s_axis_tready(),
        .s_axis_tlast(rx_axis_tlast_int),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(rx_axis_tuser_int),

        /*
         * AXI stream output
         */
        .m_axis_tdata(rx_axis_tdata),
        .m_axis_tkeep(rx_axis_tkeep),
        .m_axis_tvalid(rx_axis_tvalid),
        .m_axis_tready(1'b1),
        .m_axis_tlast(rx_axis_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(rx_axis_tuser),

        /*
         * MAC control frame interface
         */
        .mcf_valid(rx_mcf_valid),
        .mcf_eth_dst(rx_mcf_eth_dst),
        .mcf_eth_src(rx_mcf_eth_src),
        .mcf_eth_type(rx_mcf_eth_type),
        .mcf_opcode(rx_mcf_opcode),
        .mcf_params(rx_mcf_params),
        .mcf_id(),
        .mcf_dest(),
        .mcf_user(),

        /*
         * Configuration
         */
        .cfg_mcf_rx_eth_dst_mcast(cfg_mcf_rx_eth_dst_mcast),
        .cfg_mcf_rx_check_eth_dst_mcast(cfg_mcf_rx_check_eth_dst_mcast),
        .cfg_mcf_rx_eth_dst_ucast(cfg_mcf_rx_eth_dst_ucast),
        .cfg_mcf_rx_check_eth_dst_ucast(cfg_mcf_rx_check_eth_dst_ucast),
        .cfg_mcf_rx_eth_src(cfg_mcf_rx_eth_src),
        .cfg_mcf_rx_check_eth_src(cfg_mcf_rx_check_eth_src),
        .cfg_mcf_rx_eth_type(cfg_mcf_rx_eth_type),
        .cfg_mcf_rx_opcode_lfc(cfg_mcf_rx_opcode_lfc),
        .cfg_mcf_rx_check_opcode_lfc(cfg_mcf_rx_check_opcode_lfc),
        .cfg_mcf_rx_opcode_pfc(cfg_mcf_rx_opcode_pfc),
        .cfg_mcf_rx_check_opcode_pfc(cfg_mcf_rx_check_opcode_pfc && PFC_ENABLE),
        .cfg_mcf_rx_forward(cfg_mcf_rx_forward),
        .cfg_mcf_rx_enable(cfg_mcf_rx_enable),

        /*
         * Status
         */
        .stat_rx_mcf(stat_rx_mcf)
    );

    //! Instancia del modulo de pausa de control MAC del transmisor
    mac_pause_ctrl_tx #(
        .MCF_PARAMS_SIZE(MCF_PARAMS_SIZE),
        .PFC_ENABLE(PFC_ENABLE)
    )
    mac_pause_ctrl_tx_inst (
        .clk(tx_clk),
        .rst(tx_rst),

        /*
         * MAC control frame interface
         */
        .mcf_valid(tx_mcf_valid),
        .mcf_ready(tx_mcf_ready),
        .mcf_eth_dst(tx_mcf_eth_dst),
        .mcf_eth_src(tx_mcf_eth_src),
        .mcf_eth_type(tx_mcf_eth_type),
        .mcf_opcode(tx_mcf_opcode),
        .mcf_params(tx_mcf_params),

        /*
         * Pause (IEEE 802.3 annex 31B)
         */
        .tx_lfc_req(tx_lfc_req),
        .tx_lfc_resend(tx_lfc_resend),

        /*
         * Priority Flow Control (PFC) (IEEE 802.3 annex 31D)
         */
        .tx_pfc_req(tx_pfc_req),
        .tx_pfc_resend(tx_pfc_resend),

        /*
         * Configuration
         */
        .cfg_tx_lfc_eth_dst(cfg_tx_lfc_eth_dst),
        .cfg_tx_lfc_eth_src(cfg_tx_lfc_eth_src),
        .cfg_tx_lfc_eth_type(cfg_tx_lfc_eth_type),
        .cfg_tx_lfc_opcode(cfg_tx_lfc_opcode),
        .cfg_tx_lfc_en(cfg_tx_lfc_en),
        .cfg_tx_lfc_quanta(cfg_tx_lfc_quanta),
        .cfg_tx_lfc_refresh(cfg_tx_lfc_refresh),
        .cfg_tx_pfc_eth_dst(cfg_tx_pfc_eth_dst),
        .cfg_tx_pfc_eth_src(cfg_tx_pfc_eth_src),
        .cfg_tx_pfc_eth_type(cfg_tx_pfc_eth_type),
        .cfg_tx_pfc_opcode(cfg_tx_pfc_opcode),
        .cfg_tx_pfc_en(cfg_tx_pfc_en),
        .cfg_tx_pfc_quanta(cfg_tx_pfc_quanta),
        .cfg_tx_pfc_refresh(cfg_tx_pfc_refresh),
        .cfg_quanta_step((DATA_WIDTH*256)/512),
        .cfg_quanta_clk_en(1'b1),

        /*
         * Status
         */
        .stat_tx_lfc_pkt(stat_tx_lfc_pkt),
        .stat_tx_lfc_xon(stat_tx_lfc_xon),
        .stat_tx_lfc_xoff(stat_tx_lfc_xoff),
        .stat_tx_lfc_paused(stat_tx_lfc_paused),
        .stat_tx_pfc_pkt(stat_tx_pfc_pkt),
        .stat_tx_pfc_xon(stat_tx_pfc_xon),
        .stat_tx_pfc_xoff(stat_tx_pfc_xoff),
        .stat_tx_pfc_paused(stat_tx_pfc_paused)
    );

    //! Instancia del modulo de pausa de control MAC del receptor
    mac_pause_ctrl_rx #(
        .MCF_PARAMS_SIZE(18),
        .PFC_ENABLE(PFC_ENABLE)
    )
    mac_pause_ctrl_rx_inst (
        .clk(rx_clk),
        .rst(rx_rst),

        /*
         * MAC control frame interface
         */
        .mcf_valid(rx_mcf_valid),
        .mcf_eth_dst(rx_mcf_eth_dst),
        .mcf_eth_src(rx_mcf_eth_src),
        .mcf_eth_type(rx_mcf_eth_type),
        .mcf_opcode(rx_mcf_opcode),
        .mcf_params(rx_mcf_params),

        /*
         * Pause (IEEE 802.3 annex 31B)
         */
        .rx_lfc_en(rx_lfc_en),
        .rx_lfc_req(rx_lfc_req),
        .rx_lfc_ack(rx_lfc_ack_int),

        /*
         * Priority Flow Control (PFC) (IEEE 802.3 annex 31D)
         */
        .rx_pfc_en(rx_pfc_en),
        .rx_pfc_req(rx_pfc_req),
        .rx_pfc_ack(rx_pfc_ack),

        /*
         * Configuration
         */
        .cfg_rx_lfc_opcode(cfg_rx_lfc_opcode),
        .cfg_rx_lfc_en(cfg_rx_lfc_en),
        .cfg_rx_pfc_opcode(cfg_rx_pfc_opcode),
        .cfg_rx_pfc_en(cfg_rx_pfc_en),
        .cfg_quanta_step((DATA_WIDTH*256)/512),
        .cfg_quanta_clk_en(1'b1),

        /*
         * Status
         */
        .stat_rx_lfc_pkt(stat_rx_lfc_pkt),
        .stat_rx_lfc_xon(stat_rx_lfc_xon),
        .stat_rx_lfc_xoff(stat_rx_lfc_xoff),
        .stat_rx_lfc_paused(stat_rx_lfc_paused),
        .stat_rx_pfc_pkt(stat_rx_pfc_pkt),
        .stat_rx_pfc_xon(stat_rx_pfc_xon),
        .stat_rx_pfc_xoff(stat_rx_pfc_xoff),
        .stat_rx_pfc_paused(stat_rx_pfc_paused)
    );

end else begin

    assign tx_axis_tdata_int = tx_axis_tdata;
    assign tx_axis_tkeep_int = tx_axis_tkeep;
    assign tx_axis_tvalid_int = tx_axis_tvalid;
    assign tx_axis_tready = tx_axis_tready_int;
    assign tx_axis_tlast_int = tx_axis_tlast;
    assign tx_axis_tuser_int = tx_axis_tuser;

    assign rx_axis_tdata = rx_axis_tdata_int;
    assign rx_axis_tkeep = rx_axis_tkeep_int;
    assign rx_axis_tvalid = rx_axis_tvalid_int;
    assign rx_axis_tlast = rx_axis_tlast_int;
    assign rx_axis_tuser = rx_axis_tuser_int;

    assign rx_lfc_req = 0;
    assign rx_pfc_req = 0;
    assign tx_pause_ack = 0;

    assign stat_tx_mcf = 0;
    assign stat_rx_mcf = 0;
    assign stat_tx_lfc_pkt = 0;
    assign stat_tx_lfc_xon = 0;
    assign stat_tx_lfc_xoff = 0;
    assign stat_tx_lfc_paused = 0;
    assign stat_tx_pfc_pkt = 0;
    assign stat_tx_pfc_xon = 0;
    assign stat_tx_pfc_xoff = 0;
    assign stat_tx_pfc_paused = 0;
    assign stat_rx_lfc_pkt = 0;
    assign stat_rx_lfc_xon = 0;
    assign stat_rx_lfc_xoff = 0;
    assign stat_rx_lfc_paused = 0;
    assign stat_rx_pfc_pkt = 0;
    assign stat_rx_pfc_xon = 0;
    assign stat_rx_pfc_xoff = 0;
    assign stat_rx_pfc_paused = 0;

end

endgenerate

endmodule

`resetall
