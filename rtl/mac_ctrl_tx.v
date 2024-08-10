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
 * MAC control transmit
 */
module mac_ctrl_tx #
(
    parameter DATA_WIDTH = 8,                   //! Ancho de los datos en bits
    parameter KEEP_ENABLE = DATA_WIDTH>8,       //! Habilita el uso de 'keep' si el ancho de datos es mayor que 8
    parameter KEEP_WIDTH = DATA_WIDTH/8,        //! Ancho de 'keep', calculado como el ancho de datos dividido por 8
    parameter ID_ENABLE = 0,                    //! Habilita el campo de identificación
    parameter ID_WIDTH = 8,                     //! Ancho del campo de identificación
    parameter DEST_ENABLE = 0,                  //! Habilita el campo de destino
    parameter DEST_WIDTH = 8,                   //! Ancho del campo de destino
    parameter USER_ENABLE = 1,                  //! Habilita el campo de usuario
    parameter USER_WIDTH = 1,                   //! Ancho del campo de usuario
    parameter MCF_PARAMS_SIZE = 18              //! Tamaño en bytes de los parámetros del marco de control MAC
)
(
    input  wire                          clk,   //! Señal de reloj
    input  wire                          rst,   //! Señal de reset

    /*
     * Entradas AXI stream
     */
    input  wire [DATA_WIDTH-1:0]         s_axis_tdata,  //! Datos de entrada
    input  wire [KEEP_WIDTH-1:0]         s_axis_tkeep,  //! Señal 'keep' de entrada
    input  wire                          s_axis_tvalid, //! Señal de validez de datos de entrada
    output wire                          s_axis_tready, //! Señal de preparado de datos de entrada
    input  wire                          s_axis_tlast,  //! Indicador de último dato de entrada
    input  wire [ID_WIDTH-1:0]           s_axis_tid,    //! Identificador de transacción de entrada
    input  wire [DEST_WIDTH-1:0]         s_axis_tdest,  //! Destino de transacción de entrada
    input  wire [USER_WIDTH-1:0]         s_axis_tuser,  //! Usuario de transacción de entrada

    /*
     * Salidas AXI stream
     */
    output wire [DATA_WIDTH-1:0]         m_axis_tdata,  //! Datos de salida
    output wire [KEEP_WIDTH-1:0]         m_axis_tkeep,  //! Señal 'keep' de salida
    output wire                          m_axis_tvalid, //! Señal de validez de datos de salida
    input  wire                          m_axis_tready, //! Señal de preparado de datos de salida
    output wire                          m_axis_tlast,  //! Indicador de último dato de salida
    output wire [ID_WIDTH-1:0]           m_axis_tid,    //! Identificador de transacción de salida
    output wire [DEST_WIDTH-1:0]         m_axis_tdest,  //! Destino de transacción de salida
    output wire [USER_WIDTH-1:0]         m_axis_tuser,  //! Usuario de transacción de salida

    /*
     * Interfaz de marco de control MAC
     */
    input  wire                          mcf_valid,           //! Validez del marco de control MAC
    output wire                          mcf_ready,           //! Listo para recibir marco de control MAC
    input  wire [47:0]                   mcf_eth_dst,         //! Dirección de destino Ethernet del marco de control MAC
    input  wire [47:0]                   mcf_eth_src,         //! Dirección de origen Ethernet del marco de control MAC
    input  wire [15:0]                   mcf_eth_type,        //! Tipo Ethernet del marco de control MAC
    input  wire [15:0]                   mcf_opcode,          //! Código de operación del marco de control MAC
    input  wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,          //! Parámetros del marco de control MAC
    input  wire [ID_WIDTH-1:0]           mcf_id,              //! Identificador del marco de control MAC
    input  wire [DEST_WIDTH-1:0]         mcf_dest,            //! Destino del marco de control MAC
    input  wire [USER_WIDTH-1:0]         mcf_user,            //! Usuario del marco de control MAC

    /*
     * Interfaz de pausa
     */
    input  wire                          tx_pause_req,        //! Solicitud de pausa de transmisión
    output wire                          tx_pause_ack,        //! Confirmación de pausa de transmisión

    /*
     * Estado
     */
    output wire                          stat_tx_mcf            //! Estado de transmisión del marco de control MAC
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;            //! Número de carriles de bytes activos

parameter HDR_SIZE = 60;                                        //! Tamaño del encabezado en bytes

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;     //! Número de ciclos necesarios para transmitir el encabezado

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);                      //! Ancho del puntero necesario para contar los ciclos de transmisión

parameter OFFSET = HDR_SIZE % BYTE_LANES;                       //! Desplazamiento necesario para alinear el encabezado con los límites de byte


// check configuration
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end

    if (MCF_PARAMS_SIZE > 44) begin
        $error("Error: Maximum MCF_PARAMS_SIZE is 44 bytes (instance %m)");
        $finish;
    end
end

/*

MAC control frame

 Field                       Length
 Destination MAC address     6 octets [01:80:C2:00:00:01]
 Source MAC address          6 octets
 Ethertype                   2 octets [0x8808]
 Opcode                      2 octets
 Parameters                  0-44 octets

This module manages the transmission of MAC control frames.  Control frames
are accepted in parallel, serialized, and merged at a higher priority with
data traffic.

*/

reg send_data_reg = 1'b0, send_data_next;          //! Registro para la señal de envío de datos
reg send_mcf_reg = 1'b0, send_mcf_next;            //! Registro para la señal de envío de marco de control MAC
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;         //! Registro para el puntero de control

reg s_axis_tready_reg = 1'b0, s_axis_tready_next;  //! Registro para la señal de listo de datos de entrada AXI stream
reg mcf_ready_reg = 1'b0, mcf_ready_next;          //! Registro para la señal de listo de marco de control MAC
reg tx_pause_ack_reg = 1'b0, tx_pause_ack_next;    //! Registro para la confirmación de pausa de transmisión
reg stat_tx_mcf_reg = 1'b0, stat_tx_mcf_next;      //! Registro para el estado de transmisión del marco de control MAC

// internal datapath
reg  [DATA_WIDTH-1:0] m_axis_tdata_int;             //! Datos de salida internos del camino de datos
reg  [KEEP_WIDTH-1:0] m_axis_tkeep_int;             //! Señal 'keep' de salida interna del camino de datos
reg                   m_axis_tvalid_int;            //! Señal de validez de datos de salida interna
reg                   m_axis_tready_int_reg = 1'b0; //! Registro para la señal de preparado de datos de salida interna
reg                   m_axis_tlast_int;             //! Indicador de último dato de salida interno
reg  [ID_WIDTH-1:0]   m_axis_tid_int;               //! Identificador de transacción de salida interno
reg  [DEST_WIDTH-1:0] m_axis_tdest_int;             //! Destino de transacción de salida interno
reg  [USER_WIDTH-1:0] m_axis_tuser_int;             //! Usuario de transacción de salida interno
wire                  m_axis_tready_int_early;      //! Señal anticipada de preparado de datos de salida interna


assign s_axis_tready = s_axis_tready_reg;
assign mcf_ready = mcf_ready_reg;
assign tx_pause_ack = tx_pause_ack_reg;
assign stat_tx_mcf = stat_tx_mcf_reg;

integer k;

//! Implementa la lógica para configurar un encabezado MAC
always @* begin
    send_data_next = send_data_reg;
    send_mcf_next = send_mcf_reg;
    ptr_next = ptr_reg;

    s_axis_tready_next = 1'b0;
    mcf_ready_next = 1'b0;
    tx_pause_ack_next = tx_pause_ack_reg;
    stat_tx_mcf_next = 1'b0;

    m_axis_tdata_int = 0;
    m_axis_tkeep_int = 0;
    m_axis_tvalid_int = 1'b0;
    m_axis_tlast_int = 1'b0;
    m_axis_tid_int = 0;
    m_axis_tdest_int = 0;
    m_axis_tuser_int = 0;

    if (!send_data_reg && !send_mcf_reg) begin
        m_axis_tdata_int = s_axis_tdata;  // copia los datos de entrada
        m_axis_tkeep_int = s_axis_tkeep;  // copia la señal de keep
        m_axis_tvalid_int = 1'b0;         // invalida la señal de salida
        m_axis_tlast_int = s_axis_tlast;  // copia la señal de last
        m_axis_tid_int = s_axis_tid;      // copia la señal de ID
        m_axis_tdest_int = s_axis_tdest;  // copia la señal de destino
        m_axis_tuser_int = s_axis_tuser;  // copia la señal de usuario
        s_axis_tready_next = m_axis_tready_int_early && !tx_pause_req;  // determina si está lista para recibir
        tx_pause_ack_next = tx_pause_req;  // ack para pausa
        if (s_axis_tvalid && s_axis_tready) begin
            s_axis_tready_next = m_axis_tready_int_early;  // confirma que está lista para enviar
            tx_pause_ack_next = 1'b0;
            m_axis_tvalid_int = 1'b1;  // indica que hay datos válidos para enviar
            if (s_axis_tlast) begin  // si es el último dato
                s_axis_tready_next = m_axis_tready_int_early && !mcf_valid && !mcf_ready;  // espera antes de enviar nuevos datos
                send_data_next = 1'b0;
            end else begin
                send_data_next = 1'b1;  // envía nuevos datos
            end
        end else if (mcf_valid) begin  // si hay un paquete de control de flujo válido
            s_axis_tready_next = 1'b0;  // espera para enviar
            ptr_next = 0;
            send_mcf_next = 1'b1;  // indica que hay datos de control de flujo para enviar
            mcf_ready_next = (CYCLE_COUNT == 1) && m_axis_tready_int_early;  // espera la confirmación de envío
        end
    end
    
    if (send_data_reg) begin
        m_axis_tdata_int = s_axis_tdata;  // copia los datos de entrada
        m_axis_tkeep_int = s_axis_tkeep;  // copia la señal de keep
        m_axis_tvalid_int = 1'b0;         // invalida la señal de salida
        m_axis_tlast_int = s_axis_tlast;  // copia la señal de last
        m_axis_tid_int = s_axis_tid;      // copia la señal de ID
        m_axis_tdest_int = s_axis_tdest;  // copia la señal de destino
        m_axis_tuser_int = s_axis_tuser;  // copia la señal de usuario
        s_axis_tready_next = m_axis_tready_int_early;  // determina si está lista para recibir
        if (s_axis_tvalid && s_axis_tready) begin
            m_axis_tvalid_int = 1'b1;  // indica que hay datos válidos para enviar
            if (s_axis_tlast) begin  // si es el último dato
                s_axis_tready_next = m_axis_tready_int_early && !tx_pause_req;  // espera antes de enviar nuevos datos
                send_data_next = 1'b0;
                if (mcf_valid) begin  // si hay un paquete de control de flujo válido
                    s_axis_tready_next = 1'b0;  // espera para enviar
                    ptr_next = 0;
                    send_mcf_next = 1'b1;  // indica que hay datos de control de flujo para enviar
                    mcf_ready_next = (CYCLE_COUNT == 1) && m_axis_tready_int_early;  // espera la confirmación de envío
                end
            end else begin
                send_data_next = 1'b1;  // envía nuevos datos
            end
        end
    end
    
    if (send_mcf_reg) begin
        mcf_ready_next = (CYCLE_COUNT == 1 || ptr_reg == CYCLE_COUNT-1) && m_axis_tready_int_early;  // determina si está lista para recibir datos de control de flujo
        if (m_axis_tready_int_reg) begin
            ptr_next = ptr_reg + 1;  // incrementa el puntero para el próximo dato de control de flujo
            m_axis_tvalid_int = 1'b1;  // indica que hay datos válidos para enviar
            m_axis_tid_int = mcf_id;   // copia la señal de ID de control de flujo
            m_axis_tdest_int = mcf_dest;  // copia la señal de destino de control de flujo
            m_axis_tuser_int = mcf_user;  // copia la señal de usuario de control de flujo
    
            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    m_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                    m_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                end
    
            `_HEADER_FIELD_(0,  mcf_eth_dst[5*8 +: 8])  // define campos de encabezado para el paquete de control de flujo
            `_HEADER_FIELD_(1,  mcf_eth_dst[4*8 +: 8])
            `_HEADER_FIELD_(2,  mcf_eth_dst[3*8 +: 8])
            `_HEADER_FIELD_(3,  mcf_eth_dst[2*8 +: 8])
            `_HEADER_FIELD_(4,  mcf_eth_dst[1*8 +: 8])
            `_HEADER_FIELD_(5,  mcf_eth_dst[0*8 +: 8])
            `_HEADER_FIELD_(6,  mcf_eth_src[5*8 +: 8])
            `_HEADER_FIELD_(7,  mcf_eth_src[4*8 +: 8])
            `_HEADER_FIELD_(8,  mcf_eth_src[3*8 +: 8])
            `_HEADER_FIELD_(9,  mcf_eth_src[2*8 +: 8])
            `_HEADER_FIELD_(10, mcf_eth_src[1*8 +: 8])
            `_HEADER_FIELD_(11, mcf_eth_src[0*8 +: 8])
            `_HEADER_FIELD_(12, mcf_eth_type[1*8 +: 8])
            `_HEADER_FIELD_(13, mcf_eth_type[0*8 +: 8])
            `_HEADER_FIELD_(14, mcf_opcode[1*8 +: 8])
            `_HEADER_FIELD_(15, mcf_opcode[0*8 +: 8])

            for (k = 0; k < HDR_SIZE-16; k = k + 1) begin
            // verifica si el puntero actual apunta al byte correspondiente en el arreglo de datos
                if (ptr_reg == (16+k)/BYTE_LANES) begin
                    // copia los parámetros del paquete de control de flujo a la interfaz axis de salida interna
                    if (k < MCF_PARAMS_SIZE) begin
                        m_axis_tdata_int[((16+k)%BYTE_LANES)*8 +: 8] = mcf_params[k*8 +: 8];
                    end else begin
                        m_axis_tdata_int[((16+k)%BYTE_LANES)*8 +: 8] = 0;  // rellena con ceros si no hay más parámetros
                    end
                    m_axis_tkeep_int[(16+k)%BYTE_LANES] = 1'b1;  // marca los bits válidos en la señal de keep
                end
            end

            // verifica si el último byte del encabezado se ha procesado completamente
            if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES) begin
                // prepara las señales para enviar el paquete de control de flujo completo
                s_axis_tready_next = m_axis_tready_int_early && !tx_pause_req;  // espera antes de enviar nuevos datos si es el último
                mcf_ready_next = 1'b0;  // indica que no hay más datos de control de flujo para enviar
                m_axis_tlast_int = 1'b1;  // marca el último dato del paquete de control de flujo
                send_mcf_next = 1'b0;  // indica que no hay más datos de control de flujo para enviar
                stat_tx_mcf_next = 1'b1;  // marca el estado de transmisión del paquete de control de flujo
            end else begin
                // determina si la interfaz axis de salida está lista para recibir más datos de control de flujo
                mcf_ready_next = (ptr_next == CYCLE_COUNT-1) && m_axis_tready_int_early;
            end
        
            `undef _HEADER_FIELD_
        end
    end
end

//! Actualiza los registros en el flanco positivo del clock
always @(posedge clk) begin
    send_data_reg <= send_data_next;
    send_mcf_reg <= send_mcf_next;
    ptr_reg <= ptr_next;

    s_axis_tready_reg <= s_axis_tready_next;
    mcf_ready_reg <= mcf_ready_next;
    tx_pause_ack_reg <= tx_pause_ack_next;
    stat_tx_mcf_reg <= stat_tx_mcf_next;

    if (rst) begin
        send_data_reg <= 1'b0;
        send_mcf_reg <= 1'b0;
        ptr_reg <= 0;
        s_axis_tready_reg <= 1'b0;
        mcf_ready_reg <= 1'b0;
        tx_pause_ack_reg <= 1'b0;
        stat_tx_mcf_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};    //! Registro para datos de salida 
reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};    //! Registro para señal de keep de salida
reg                  m_axis_tvalid_reg = 1'b0;                  //! Registro para señal de validez de salida
reg                  m_axis_tlast_reg  = 1'b0;                  //! Registro para señal de último de salida
reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};      //! Registro para ID de salida
reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};    //! Registro para destino de salida
reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};    //! Registro para usuario de salida

reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};   //! Registro temporal para datos
reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};   //! Registro temporal para keep 
reg                  temp_m_axis_tvalid_reg = 1'b0;                 //! Registro temporal para la validez de datos
reg                  temp_m_axis_tlast_reg  = 1'b0;                 //! Registro temporal para último dato
reg [ID_WIDTH-1:0]   temp_m_axis_tid_reg    = {ID_WIDTH{1'b0}};     //! Registro temporal para el ID 
reg [DEST_WIDTH-1:0] temp_m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};   //! Registro temporal para el destino
reg [USER_WIDTH-1:0] temp_m_axis_tuser_reg  = {USER_WIDTH{1'b0}};   //! Registro temporal para el usuario 

// datapath control
reg store_axis_int_to_output;   //! Control para almacenar datos internos en la salida
reg store_axis_int_to_temp;     //! Control para almacenar datos internos en temporales
reg store_axis_temp_to_output;  //! Control para almacenar datos temporales en la salida


assign m_axis_tdata  = m_axis_tdata_reg;
assign m_axis_tkeep  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_axis_tvalid = m_axis_tvalid_reg;
assign m_axis_tlast  = m_axis_tlast_reg;
assign m_axis_tid    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
assign m_axis_tdest  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
assign m_axis_tuser  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axis_tready_int_early = m_axis_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_tvalid_int));

//! Gestiona la transferencia del estado listo del destino hacia la fuente de datos
always @* begin
    // transfer sink ready state to source
    m_axis_tvalid_next = m_axis_tvalid_reg;
    temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_axis_tready_int_reg) begin
        // input is ready
        if (m_axis_tready || !m_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_tready) begin
        // input is not ready, but output is ready
        m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

//! Maneja la lógica de transferencia de datos entre diferentes etapas, asegurando que los datos sean correctamente almacenados y transferidos conforme a las condiciones de listo y a las señales de control disponibles
always @(posedge clk) begin
    m_axis_tvalid_reg <= m_axis_tvalid_next;
    m_axis_tready_int_reg <= m_axis_tready_int_early;
    temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_tdata_reg <= m_axis_tdata_int;
        m_axis_tkeep_reg <= m_axis_tkeep_int;
        m_axis_tlast_reg <= m_axis_tlast_int;
        m_axis_tid_reg   <= m_axis_tid_int;
        m_axis_tdest_reg <= m_axis_tdest_int;
        m_axis_tuser_reg <= m_axis_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_tdata_reg <= temp_m_axis_tdata_reg;
        m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
        m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        m_axis_tid_reg   <= temp_m_axis_tid_reg;
        m_axis_tdest_reg <= temp_m_axis_tdest_reg;
        m_axis_tuser_reg <= temp_m_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_tdata_reg <= m_axis_tdata_int;
        temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
        temp_m_axis_tlast_reg <= m_axis_tlast_int;
        temp_m_axis_tid_reg   <= m_axis_tid_int;
        temp_m_axis_tdest_reg <= m_axis_tdest_int;
        temp_m_axis_tuser_reg <= m_axis_tuser_int;
    end

    if (rst) begin
        m_axis_tvalid_reg <= 1'b0;
        m_axis_tready_int_reg <= 1'b0;
        temp_m_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
