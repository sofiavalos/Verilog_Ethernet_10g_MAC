/*

Copyright (c) 2023 Alex Forencich

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
 * PFC and pause frame receive handling
 */
//! implementa la recepción y gestión de marcos de control MAC, incluyendo tanto el flujo de control a nivel de enlace (LFC), como el flujo de control de prioridad (PFC).
module mac_pause_ctrl_rx #
(
    parameter MCF_PARAMS_SIZE = 18,  //! Tamaño de los parámetros del marco de control MAC
    parameter PFC_ENABLE = 1         //! Habilitar PFC (Control de Flujo de Prioridad)
)
(
    input  wire                          clk,               //! Señal de clock
    input  wire                          rst,               //! Señal de reset

    /*
     * MAC control frame interface
     */
    input  wire                          mcf_valid,         //! Validez del marco de control MAC
    input  wire [47:0]                   mcf_eth_dst,       //! Destino Ethernet del marco de control MAC
    input  wire [47:0]                   mcf_eth_src,       //! Origen Ethernet del marco de control MAC
    input  wire [15:0]                   mcf_eth_type,      //! Tipo Ethernet del marco de control MAC
    input  wire [15:0]                   mcf_opcode,        //! Código de operación del marco de control MAC
    input  wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,        //! Parámetros del marco de control MAC

    /*
     * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
     */
    input  wire                          rx_lfc_en,         //! Habilitar LFC (Control de Flujo a Nivel de Enlace)
    output wire                          rx_lfc_req,        //! Solicitud de LFC (Control de Flujo a Nivel de Enlace)
    input  wire                          rx_lfc_ack,        //! Reconocimiento de LFC (Control de Flujo a Nivel de Enlace)

    /*
     * Priority Flow Control (PFC) (IEEE 802.3 annex 31D PFC)
     */
    input  wire [7:0]                    rx_pfc_en,         //! Habilitar PFC (Control de Flujo de Prioridad)
    output wire [7:0]                    rx_pfc_req,        //! Solicitud de PFC (Control de Flujo de Prioridad)
    input  wire [7:0]                    rx_pfc_ack,        //! Reconocimiento de PFC (Control de Flujo de Prioridad)

    /*
     * Configuration
     */
    input  wire [15:0]                   cfg_rx_lfc_opcode, //! Código de operación de LFC configurado
    input  wire                          cfg_rx_lfc_en,     //! Habilitar LFC configurado
    input  wire [15:0]                   cfg_rx_pfc_opcode, //! Código de operación de PFC configurado
    input  wire                          cfg_rx_pfc_en,     //! Habilitar PFC configurado
    input  wire [9:0]                    cfg_quanta_step,   //! Paso de cuantum configurado
    input  wire                          cfg_quanta_clk_en, //! Habilitar reloj de cuantum configurado

    /*
     * Status
     */
    output wire                          stat_rx_lfc_pkt,   //! Paquete recibido de LFC
    output wire                          stat_rx_lfc_xon,   //! XON recibido de LFC
    output wire                          stat_rx_lfc_xoff,  //! XOFF recibido de LFC
    output wire                          stat_rx_lfc_paused,//! Estado pausado de LFC
    output wire                          stat_rx_pfc_pkt,   //! Paquete recibido de PFC
    output wire [7:0]                    stat_rx_pfc_xon,   //! XON recibido de PFC
    output wire [7:0]                    stat_rx_pfc_xoff,  //! XOFF recibido de PFC
    output wire [7:0]                    stat_rx_pfc_paused //! Estado pausado de PFC
);

localparam QFB = 8;


// check configuration
initial begin
    if (MCF_PARAMS_SIZE < (PFC_ENABLE ? 18 : 2)) begin
        $error("Error: MCF_PARAMS_SIZE too small for requested configuration (instance %m)");
        $finish;
    end
end

reg lfc_req_reg = 1'b0, lfc_req_next;                       //! Registro para solicitud de LFC (Control de Flujo a Nivel de Enlace)
reg [7:0] pfc_req_reg = 8'd0, pfc_req_next;                 //! Registro para solicitud de PFC (Control de Flujo de Prioridad)

reg [16+QFB-1:0] lfc_quanta_reg = 0, lfc_quanta_next;       //! Registro para cuantum de LFC
reg [16+QFB-1:0] pfc_quanta_reg[0:7], pfc_quanta_next[0:7]; //! Registros para cuantum de PFC para cada cola

reg stat_rx_lfc_pkt_reg = 1'b0, stat_rx_lfc_pkt_next;           //! Registro para indicar paquete recibido de LFC
reg stat_rx_lfc_xon_reg = 1'b0, stat_rx_lfc_xon_next;           //! Registro para indicar XON recibido de LFC
reg stat_rx_lfc_xoff_reg = 1'b0, stat_rx_lfc_xoff_next;         //! Registro para indicar XOFF recibido de LFC
reg stat_rx_pfc_pkt_reg = 1'b0, stat_rx_pfc_pkt_next;           //! Registro para indicar paquete recibido de PFC
reg [7:0] stat_rx_pfc_xon_reg = 8'd0, stat_rx_pfc_xon_next;     //! Registro para indicar XON recibido de PFC
reg [7:0] stat_rx_pfc_xoff_reg = 8'd0, stat_rx_pfc_xoff_next;   //! Registro para indicar XOFF recibido de PFC


assign rx_lfc_req = lfc_req_reg;
assign rx_pfc_req = pfc_req_reg;

assign stat_rx_lfc_pkt = stat_rx_lfc_pkt_reg;
assign stat_rx_lfc_xon = stat_rx_lfc_xon_reg;
assign stat_rx_lfc_xoff = stat_rx_lfc_xoff_reg;
assign stat_rx_lfc_paused = lfc_req_reg;
assign stat_rx_pfc_pkt = stat_rx_pfc_pkt_reg;
assign stat_rx_pfc_xon = stat_rx_pfc_xon_reg;
assign stat_rx_pfc_xoff = stat_rx_pfc_xoff_reg;
assign stat_rx_pfc_paused = pfc_req_reg;

integer k;

initial begin
    for (k = 0; k < 8; k = k + 1) begin
        pfc_quanta_reg[k] = 0;
    end
end

//! Gestiona el control de cuantum y las solicitudes de control de flujo tanto a nivel de enlace (LFC) como de prioridad (PFC)
always @* begin
    stat_rx_lfc_pkt_next = 1'b0;
    stat_rx_lfc_xon_next = 1'b0;
    stat_rx_lfc_xoff_next = 1'b0;
    stat_rx_pfc_pkt_next = 1'b0;
    stat_rx_pfc_xon_next = 0;
    stat_rx_pfc_xoff_next = 0;

    if (cfg_quanta_clk_en && rx_lfc_ack) begin  // si se habilita el reloj de cuantum y se recibe un ACK de LFC
        if (lfc_quanta_reg > cfg_quanta_step) begin  // si el cuantum de LFC actual es mayor que el paso de cuantum configurado
            lfc_quanta_next = lfc_quanta_reg - cfg_quanta_step;  // reduce el cuantum de LFC
        end else begin
            lfc_quanta_next = 0;  // de lo contrario, establecer el cuantum de LFC en cero
        end
    end else begin
        lfc_quanta_next = lfc_quanta_reg;  // mantiene el cuantum de LFC sin cambios
    end

    lfc_req_next = (lfc_quanta_reg != 0) && rx_lfc_en && cfg_rx_lfc_en;  // determinar la solicitud de LFC

    for (k = 0; k < 8; k = k + 1) begin  // bucle para cada cola de PFC
        if (cfg_quanta_clk_en && rx_pfc_ack[k]) begin  // si se habilita el reloj de cuantum y se recibe un ACK de PFC para la cola k
            if (pfc_quanta_reg[k] > cfg_quanta_step) begin  // si el cuantum de PFC actual para la cola k es mayor que el paso de cuantum configurado
                pfc_quanta_next[k] = pfc_quanta_reg[k] - cfg_quanta_step;  // reduci el cuantum de PFC para la cola k
            end else begin
                pfc_quanta_next[k] = 0;  // de lo contrario, establece el cuantum de PFC para la cola k en cero
            end
        end else begin
            pfc_quanta_next[k] = pfc_quanta_reg[k];  // mantiene el cuantum de PFC para la cola k sin cambios
        end

        pfc_req_next[k] = (pfc_quanta_reg[k] != 0) && rx_pfc_en[k] && cfg_rx_pfc_en;  // determina la solicitud de PFC para la cola k
    end

    if (mcf_valid) begin  // si hay un marco de control MAC válido
        if (mcf_opcode == cfg_rx_lfc_opcode && cfg_rx_lfc_en) begin  // si el código de operación del marco es igual al código de operación de LFC configurado y LFC está habilitado
            stat_rx_lfc_pkt_next = 1'b1;  // indicar que se recibió un paquete de LFC
            stat_rx_lfc_xon_next = {mcf_params[7:0], mcf_params[15:8]} == 0;  // verificar si se recibió un XON de LFC
            stat_rx_lfc_xoff_next = {mcf_params[7:0], mcf_params[15:8]} != 0;  // verificar si se recibió un XOFF de LFC
            lfc_quanta_next = {mcf_params[7:0], mcf_params[15:8], {QFB{1'b0}}};  // actualizar el cuantum de LFC según los parámetros recibidos
        end else if (PFC_ENABLE && mcf_opcode == cfg_rx_pfc_opcode && cfg_rx_pfc_en) begin  // si PFC está habilitado y el código de operación del marco es igual al código de operación de PFC configurado y PFC está habilitado
            stat_rx_pfc_pkt_next = 1'b1;  // indicar que se recibió un paquete de PFC
            for (k = 0; k < 8; k = k + 1) begin
                if (mcf_params[k+8]) begin  // si el bit correspondiente a la cola k está activo en los parámetros del marco
                    stat_rx_pfc_xon_next[k] = {mcf_params[16+(k*16)+0 +: 8], mcf_params[16+(k*16)+8 +: 8]} == 0;  // verifica si se recibió un XON de PFC para la cola k
                    stat_rx_pfc_xoff_next[k] = {mcf_params[16+(k*16)+0 +: 8], mcf_params[16+(k*16)+8 +: 8]} != 0;  // verifica si se recibió un XOFF de PFC para la cola k
                    pfc_quanta_next[k] = {mcf_params[16+(k*16)+0 +: 8], mcf_params[16+(k*16)+8 +: 8], {QFB{1'b0}}};  // actualiza el cuantum de PFC para la cola k según los parámetros recibidos
                end
            end
        end
    end
end

//! Actualiza los datos en los flancos positivos de reloj
always @(posedge clk) begin
    lfc_req_reg <= lfc_req_next;
    pfc_req_reg <= pfc_req_next;

    lfc_quanta_reg <= lfc_quanta_next;
    for (k = 0; k < 8; k = k + 1) begin
        pfc_quanta_reg[k] <= pfc_quanta_next[k];
    end

    stat_rx_lfc_pkt_reg <= stat_rx_lfc_pkt_next;
    stat_rx_lfc_xon_reg <= stat_rx_lfc_xon_next;
    stat_rx_lfc_xoff_reg <= stat_rx_lfc_xoff_next;
    stat_rx_pfc_pkt_reg <= stat_rx_pfc_pkt_next;
    stat_rx_pfc_xon_reg <= stat_rx_pfc_xon_next;
    stat_rx_pfc_xoff_reg <= stat_rx_pfc_xoff_next;

    if (rst) begin
        lfc_req_reg <= 1'b0;
        pfc_req_reg <= 8'd0;
        lfc_quanta_reg <= 0;
        for (k = 0; k < 8; k = k + 1) begin
            pfc_quanta_reg[k] <= 0;
        end

        stat_rx_lfc_pkt_reg <= 1'b0;
        stat_rx_lfc_xon_reg <= 1'b0;
        stat_rx_lfc_xoff_reg <= 1'b0;
        stat_rx_pfc_pkt_reg <= 1'b0;
        stat_rx_pfc_xon_reg <= 0;
        stat_rx_pfc_xoff_reg <= 0;
    end
end

endmodule

`resetall
