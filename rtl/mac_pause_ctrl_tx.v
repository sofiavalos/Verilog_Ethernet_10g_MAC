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
 * PFC and pause frame transmit handling
 */
 //! implementa la transmision y gestión de marcos de control MAC, incluyendo tanto el flujo de control a nivel de enlace (LFC), como el flujo de control de prioridad (PFC).
 module mac_pause_ctrl_tx #
 (
     parameter MCF_PARAMS_SIZE = 18, //! Tamaño de los parámetros del marco de control MAC en bytes.
     parameter PFC_ENABLE = 1        //! Habilita el control de flujo prioritario (PFC).
 )
 (
     input  wire                          clk,                      //! Señal de clock
     input  wire                          rst,                      //! Señal de reset
 
     /*
      * Interfaz del marco de control MAC
      */
     output wire                          mcf_valid,                //! Flag que indica que el marco de control MAC es válido.
     input  wire                          mcf_ready,                //! Flag que indica que el receptor está listo para aceptar un nuevo marco.
     output wire [47:0]                   mcf_eth_dst,              //! Dirección MAC de destino del marco de control MAC.
     output wire [47:0]                   mcf_eth_src,              //! Dirección MAC de origen del marco de control MAC.
     output wire [15:0]                   mcf_eth_type,             //! Tipo de Ethernet del marco de control MAC.
     output wire [15:0]                   mcf_opcode,               //! Opcode del marco de control MAC.
     output wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,               //! Parámetros del marco de control MAC.
 
     /*
      * Control de flujo a nivel de enlace (LFC) (IEEE 802.3 anexo 31B PAUSE)
      */
     input  wire                          tx_lfc_req,               //! Solicitud de control de flujo a nivel de enlace para transmisión.
     input  wire                          tx_lfc_resend,            //! Solicitud de reenvío del marco de control de flujo a nivel de enlace.
 
     /*
      * Control de Flujo Prioritario (PFC) (IEEE 802.3 anexo 31D)
      */
     input  wire [7:0]                    tx_pfc_req,               //! Solicitud de control de flujo prioritario para transmisión.
     input  wire                          tx_pfc_resend,            //! Solicitud de reenvío del marco de control de flujo prioritario.
 
     /*
      * Configuración
      */
     input  wire [47:0]                   cfg_tx_lfc_eth_dst,       //! Configuración de la dirección MAC de destino para LFC.
     input  wire [47:0]                   cfg_tx_lfc_eth_src,       //! Configuración de la dirección MAC de origen para LFC.
     input  wire [15:0]                   cfg_tx_lfc_eth_type,      //! Configuración del tipo de Ethernet para LFC.
     input  wire [15:0]                   cfg_tx_lfc_opcode,        //! Configuración del opcode para LFC.
     input  wire                          cfg_tx_lfc_en,            //! Habilitación del control de flujo a nivel de enlace.
     input  wire [15:0]                   cfg_tx_lfc_quanta,        //! Configuración de la cantidad de tiempo para LFC.
     input  wire [15:0]                   cfg_tx_lfc_refresh,       //! Configuración del tiempo de refresco para LFC.
     input  wire [47:0]                   cfg_tx_pfc_eth_dst,       //! Configuración de la dirección MAC de destino para PFC.
     input  wire [47:0]                   cfg_tx_pfc_eth_src,       //! Configuración de la dirección MAC de origen para PFC.
     input  wire [15:0]                   cfg_tx_pfc_eth_type,      //! Configuración del tipo de Ethernet para PFC.
     input  wire [15:0]                   cfg_tx_pfc_opcode,        //! Configuración del opcode para PFC.
     input  wire                          cfg_tx_pfc_en,            //! Habilitación del control de flujo prioritario.
     input  wire [8*16-1:0]               cfg_tx_pfc_quanta,        //! Configuración de la cantidad de tiempo para cada prioridad en PFC.
     input  wire [8*16-1:0]               cfg_tx_pfc_refresh,       //! Configuración del tiempo de refresco para cada prioridad en PFC.
     input  wire [9:0]                    cfg_quanta_step,          //! Paso de incremento para la cantidad de tiempo.
     input  wire                          cfg_quanta_clk_en,        //! Habilitación del reloj para la cantidad de tiempo.
 
     /*
      * Estado
      */
     output wire                          stat_tx_lfc_pkt,          //! Indicador de paquete LFC transmitido.
     output wire                          stat_tx_lfc_xon,          //! Indicador de señal XON en LFC.
     output wire                          stat_tx_lfc_xoff,         //! Indicador de señal XOFF en LFC.
     output wire                          stat_tx_lfc_paused,       //! Indicador de pausa en LFC.
     output wire                          stat_tx_pfc_pkt,          //! Indicador de paquete PFC transmitido.
     output wire [7:0]                    stat_tx_pfc_xon,          //! Indicador de señal XON en PFC para cada prioridad.
     output wire [7:0]                    stat_tx_pfc_xoff,         //! Indicador de señal XOFF en PFC para cada prioridad.
     output wire [7:0]                    stat_tx_pfc_paused        //! Indicador de pausa en PFC para cada prioridad.
 );
 
 localparam QFB = 8; //! Valor constante para el paso de tiempo de la cantidad de flujo.
 
 endmodule
 

// check configuration
initial begin
    if (MCF_PARAMS_SIZE < (PFC_ENABLE ? 18 : 2)) begin
        $error("Error: MCF_PARAMS_SIZE too small for requested configuration (instance %m)");
        $finish;
    end
end

// Registros para el control de flujo a nivel de enlace (LFC)
reg lfc_req_reg = 1'b0, lfc_req_next;                           //! Registro y próximo valor para la solicitud de control de flujo LFC.
reg lfc_act_reg = 1'b0, lfc_act_next;                           //! Registro y próximo valor para la activación de LFC.
reg lfc_send_reg = 1'b0, lfc_send_next;                         //! Registro y próximo valor para el envío de LFC.

// Registros para el control de flujo prioritario (PFC)
reg [7:0] pfc_req_reg = 8'd0, pfc_req_next;                     //! Registro y próximo valor para la solicitud de PFC para cada prioridad.
reg [7:0] pfc_act_reg = 8'd0, pfc_act_next;                     //! Registro y próximo valor para la activación de PFC para cada prioridad.
reg [7:0] pfc_en_reg = 8'd0, pfc_en_next;                       //! Registro y próximo valor para la habilitación de PFC para cada prioridad.
reg pfc_send_reg = 1'b0, pfc_send_next;                         //! Registro y próximo valor para el envío de PFC.

// Registros para los tiempos de refresco de LFC y PFC
reg [16+QFB-1:0] lfc_refresh_reg = 0, lfc_refresh_next;        //! Registro y próximo valor para el tiempo de refresco de LFC.
reg [16+QFB-1:0] pfc_refresh_reg[0:7], pfc_refresh_next[0:7];  //! Registro y próximo valor para el tiempo de refresco de PFC para cada prioridad.

// Registros de estado de LFC
reg stat_tx_lfc_pkt_reg = 1'b0, stat_tx_lfc_pkt_next;          //! Registro y próximo valor para el estado del paquete LFC transmitido.
reg stat_tx_lfc_xon_reg = 1'b0, stat_tx_lfc_xon_next;          //! Registro y próximo valor para el estado de la señal XON de LFC.
reg stat_tx_lfc_xoff_reg = 1'b0, stat_tx_lfc_xoff_next;        //! Registro y próximo valor para el estado de la señal XOFF de LFC.

// Registros de estadísticas/estado de PFC
reg stat_tx_pfc_pkt_reg = 1'b0, stat_tx_pfc_pkt_next;          //! Registro y próximo valor para el estado del paquete PFC transmitido.
reg [7:0] stat_tx_pfc_xon_reg = 0, stat_tx_pfc_xon_next;       //! Registro y próximo valor para el estado de la señal XON de PFC para cada prioridad.
reg [7:0] stat_tx_pfc_xoff_reg = 0, stat_tx_pfc_xoff_next;     //! Registro y próximo valor para el estado de la señal XOFF de PFC para cada prioridad.

// Interfaz de control MAC
reg mcf_pfc_sel_reg = PFC_ENABLE != 0, mcf_pfc_sel_next;        //! Registro y próximo valor para la selección entre LFC y PFC en el control MAC.
reg mcf_valid_reg = 1'b0, mcf_valid_next;                       //! Registro y próximo valor para la validez del marco de control MAC.

wire [2*8-1:0] mcf_lfc_params;
assign mcf_lfc_params[16*0 +: 16] = lfc_req_reg ? {cfg_tx_lfc_quanta[0 +: 8], cfg_tx_lfc_quanta[8 +: 8]} : 0;

wire [18*8-1:0] mcf_pfc_params;
assign mcf_pfc_params[16*0 +: 16] = {pfc_en_reg, 8'd0};
assign mcf_pfc_params[16*1 +: 16] = pfc_req_reg[0] ? {cfg_tx_pfc_quanta[16*0+0 +: 8], cfg_tx_pfc_quanta[16*0+8 +: 8]} : 0;
assign mcf_pfc_params[16*2 +: 16] = pfc_req_reg[1] ? {cfg_tx_pfc_quanta[16*1+0 +: 8], cfg_tx_pfc_quanta[16*1+8 +: 8]} : 0;
assign mcf_pfc_params[16*3 +: 16] = pfc_req_reg[2] ? {cfg_tx_pfc_quanta[16*2+0 +: 8], cfg_tx_pfc_quanta[16*2+8 +: 8]} : 0;
assign mcf_pfc_params[16*4 +: 16] = pfc_req_reg[3] ? {cfg_tx_pfc_quanta[16*3+0 +: 8], cfg_tx_pfc_quanta[16*3+8 +: 8]} : 0;
assign mcf_pfc_params[16*5 +: 16] = pfc_req_reg[4] ? {cfg_tx_pfc_quanta[16*4+0 +: 8], cfg_tx_pfc_quanta[16*4+8 +: 8]} : 0;
assign mcf_pfc_params[16*6 +: 16] = pfc_req_reg[5] ? {cfg_tx_pfc_quanta[16*5+0 +: 8], cfg_tx_pfc_quanta[16*5+8 +: 8]} : 0;
assign mcf_pfc_params[16*7 +: 16] = pfc_req_reg[6] ? {cfg_tx_pfc_quanta[16*6+0 +: 8], cfg_tx_pfc_quanta[16*6+8 +: 8]} : 0;
assign mcf_pfc_params[16*8 +: 16] = pfc_req_reg[7] ? {cfg_tx_pfc_quanta[16*7+0 +: 8], cfg_tx_pfc_quanta[16*7+8 +: 8]} : 0;

assign mcf_valid = mcf_valid_reg;
assign mcf_eth_dst  = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_eth_dst  : cfg_tx_lfc_eth_dst;
assign mcf_eth_src  = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_eth_src  : cfg_tx_lfc_eth_src;
assign mcf_eth_type = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_eth_type : cfg_tx_lfc_eth_type;
assign mcf_opcode   = (PFC_ENABLE && mcf_pfc_sel_reg) ? cfg_tx_pfc_opcode   : cfg_tx_lfc_opcode;
assign mcf_params   = (PFC_ENABLE && mcf_pfc_sel_reg) ? mcf_pfc_params      : mcf_lfc_params;

assign stat_tx_lfc_pkt = stat_tx_lfc_pkt_reg;
assign stat_tx_lfc_xon = stat_tx_lfc_xon_reg;
assign stat_tx_lfc_xoff = stat_tx_lfc_xoff_reg;
assign stat_tx_lfc_paused = lfc_req_reg;
assign stat_tx_pfc_pkt = stat_tx_pfc_pkt_reg;
assign stat_tx_pfc_xon = stat_tx_pfc_xon_reg;
assign stat_tx_pfc_xoff = stat_tx_pfc_xoff_reg;
assign stat_tx_pfc_paused = pfc_req_reg;

integer k;

initial begin
    for (k = 0; k < 8; k = k + 1) begin
        pfc_refresh_reg[k] = 0;
    end
end

//! Maneja el temporizador de refresco y las solicitudes de control de flujo (LFC y PFC) para determinar cuándo enviar tramas de pausa y actualizar los estados y estadísticas correspondientes en un controlador MAC.
always @* begin
    lfc_req_next = lfc_req_reg;
    lfc_act_next = lfc_act_reg;
    lfc_send_next = lfc_send_reg | tx_lfc_resend;
    pfc_req_next = pfc_req_reg;
    pfc_act_next = pfc_act_reg;
    pfc_en_next = pfc_en_reg;
    pfc_send_next = pfc_send_reg | tx_pfc_resend;

    mcf_pfc_sel_next = mcf_pfc_sel_reg;
    mcf_valid_next = mcf_valid_reg && !mcf_ready;

    stat_tx_lfc_pkt_next = 1'b0;
    stat_tx_lfc_xon_next = 1'b0;
    stat_tx_lfc_xoff_next = 1'b0;
    stat_tx_pfc_pkt_next = 1'b0;
    stat_tx_pfc_xon_next = 0;
    stat_tx_pfc_xoff_next = 0;

    if (cfg_quanta_clk_en) begin
        if (lfc_refresh_reg > cfg_quanta_step) begin
            lfc_refresh_next = lfc_refresh_reg - cfg_quanta_step; // decrementa el temporizador de refresco LFC
        end else begin
            lfc_refresh_next = 0; // restablece el temporizador de refresco LFC
            if (lfc_req_reg) begin
                lfc_send_next = 1'b1; // inicia el envío de una trama de pausa LFC
            end
        end
    end else begin
        lfc_refresh_next = lfc_refresh_reg; // mantiene el valor actual del temporizador de refresco LFC
    end
    
    for (k = 0; k < 8; k = k + 1) begin
        if (cfg_quanta_clk_en) begin
            if (pfc_refresh_reg[k] > cfg_quanta_step) begin
                pfc_refresh_next[k] = pfc_refresh_reg[k] - cfg_quanta_step; // decrementa el temporizador de refresco PFC para la prioridad k
            end else begin
                pfc_refresh_next[k] = 0; // restablece el temporizador de refresco PFC para la prioridad k
                if (pfc_req_reg[k]) begin
                    pfc_send_next = 1'b1; // inicia el envío de una trama de pausa PFC
                end
            end
        end else begin
            pfc_refresh_next[k] = pfc_refresh_reg[k]; // mantiene el valor actual del temporizador de refresco PFC para la prioridad k
        end
    end
    
    if (cfg_tx_lfc_en) begin
        if (!mcf_valid_reg) begin
            if (lfc_req_reg != tx_lfc_req) begin
                lfc_req_next = tx_lfc_req; // actualiza la solicitud LFC
                lfc_act_next = lfc_act_reg | tx_lfc_req; // actualiza el estado activo de LFC
                lfc_send_next = 1'b1; // indica que se debe enviar una trama LFC
            end
    
            if (lfc_send_reg && !(PFC_ENABLE && cfg_tx_pfc_en && pfc_send_reg)) begin
                mcf_pfc_sel_next = 1'b0; // selecciona LFC en el MAC
                mcf_valid_next = lfc_act_reg; // indica que la trama LFC es válida
                lfc_act_next = lfc_req_reg; // actualiza el estado activo de LFC
                lfc_refresh_next = lfc_req_reg ? {cfg_tx_lfc_refresh, {QFB{1'b0}}} : 0; // restablece el temporizador de refresco LFC si se solicita LFC
                lfc_send_next = 1'b0; // finaliza el envío de la trama LFC
    
                stat_tx_lfc_pkt_next = lfc_act_reg; // indica que se ha transmitido una trama LFC
                stat_tx_lfc_xon_next = lfc_act_reg && !lfc_req_reg; // indica que se ha transmitido una señal XON (reanudar)
                stat_tx_lfc_xoff_next = lfc_act_reg && lfc_req_reg; // indica que se ha transmitido una señal XOFF (pausar)
            end
        end
    end
    
    if (PFC_ENABLE && cfg_tx_pfc_en) begin
        if (!mcf_valid_reg) begin
            if (pfc_req_reg != tx_pfc_req) begin
                pfc_req_next = tx_pfc_req; // actualiza la solicitud PFC
                pfc_act_next = pfc_act_reg | tx_pfc_req; // actualiza el estado activo de PFC
                pfc_send_next = 1'b1; // indica que se debe enviar una trama PFC
            end
    
            if (pfc_send_reg) begin
                mcf_pfc_sel_next = 1'b1; // selecciona PFC en el MAC
                mcf_valid_next = pfc_act_reg != 0; // indica que la trama PFC es válida
                pfc_en_next = pfc_act_reg; // actualiza el estado de habilitación de PFC
                pfc_act_next = pfc_req_reg; // actualiza el estado activo de PFC
                for (k = 0; k < 8; k = k + 1) begin
                    pfc_refresh_next[k] = pfc_req_reg[k] ? {cfg_tx_pfc_refresh[16*k +: 16], {QFB{1'b0}}} : 0; // restablece el temporizador de refresco PFC para la prioridad k
                end
                pfc_send_next = 1'b0; // finaliza el envío de la trama PFC
    
                stat_tx_pfc_pkt_next = pfc_act_reg != 0; // indica que se ha transmitido una trama PFC
                stat_tx_pfc_xon_next = pfc_act_reg & ~pfc_req_reg; // indica que se ha transmitido una señal XON (reanudar) para cada prioridad
                stat_tx_pfc_xoff_next = pfc_act_reg & pfc_req_reg; // indica que se ha transmitido una señal XOFF (pausar) para cada prioridad
            end
        end
    end    
end

//! Actualiza los registros en el flanco alto del reloj
always @(posedge clk) begin
    lfc_req_reg <= lfc_req_next;
    lfc_act_reg <= lfc_act_next;
    lfc_send_reg <= lfc_send_next;
    pfc_req_reg <= pfc_req_next;
    pfc_act_reg <= pfc_act_next;
    pfc_en_reg <= pfc_en_next;
    pfc_send_reg <= pfc_send_next;

    mcf_pfc_sel_reg <= mcf_pfc_sel_next;
    mcf_valid_reg <= mcf_valid_next;

    lfc_refresh_reg <= lfc_refresh_next;
    for (k = 0; k < 8; k = k + 1) begin
        pfc_refresh_reg[k] <= pfc_refresh_next[k];
    end

    stat_tx_lfc_pkt_reg <= stat_tx_lfc_pkt_next;
    stat_tx_lfc_xon_reg <= stat_tx_lfc_xon_next;
    stat_tx_lfc_xoff_reg <= stat_tx_lfc_xoff_next;
    stat_tx_pfc_pkt_reg <= stat_tx_pfc_pkt_next;
    stat_tx_pfc_xon_reg <= stat_tx_pfc_xon_next;
    stat_tx_pfc_xoff_reg <= stat_tx_pfc_xoff_next;

    if (rst) begin
        lfc_req_reg <= 1'b0;
        lfc_act_reg <= 1'b0;
        lfc_send_reg <= 1'b0;
        pfc_req_reg <= 0;
        pfc_act_reg <= 0;
        pfc_send_reg <= 0;
        mcf_pfc_sel_reg <= PFC_ENABLE != 0;
        mcf_valid_reg <= 1'b0;
        lfc_refresh_reg <= 0;
        for (k = 0; k < 8; k = k + 1) begin
            pfc_refresh_reg[k] <= 0;
        end

        stat_tx_lfc_pkt_reg <= 1'b0;
        stat_tx_lfc_xon_reg <= 1'b0;
        stat_tx_lfc_xoff_reg <= 1'b0;
        stat_tx_pfc_pkt_reg <= 1'b0;
        stat_tx_pfc_xon_reg <= 0;
        stat_tx_pfc_xoff_reg <= 0;
    end
end

endmodule

`resetall
