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
 * MAC control receive
*/
//! Bloque que se encarga de configurar el receptor MAC
module mac_ctrl_rx #
(
    parameter DATA_WIDTH = 8,                      //! Ancho de datos en bits
    parameter KEEP_ENABLE = DATA_WIDTH > 8,        //! Flag para habilitar señal de keep
    parameter KEEP_WIDTH = DATA_WIDTH / 8,         //! Ancho de la señal keep
    parameter ID_ENABLE = 0,                       //! Flag para habilitar ID
    parameter ID_WIDTH = 8,                        //! Ancho de la señal ID
    parameter DEST_ENABLE = 0,                     //! Flag para habilitar el destino
    parameter DEST_WIDTH = 8,                      //! Ancho de la señal de destino
    parameter USER_ENABLE = 1,                     //! Flag para habilitar el usuario
    parameter USER_WIDTH = 1,                      //! Ancho de la señal de usuario
    parameter USE_READY = 0,                       //! Uso de señal de ready
    parameter MCF_PARAMS_SIZE = 18                 //! Tamaño de los parámetros del marco de control MAC
)
(
    input  wire                          clk,            //! Señal de clock
    input  wire                          rst,            //! Señal de reset
 
    /*
    * Entrada de flujo AXI
    */
    input  wire [DATA_WIDTH-1:0]         s_axis_tdata,   //! Datos de entrada
    input  wire [KEEP_WIDTH-1:0]         s_axis_tkeep,   //! Señal keep de entrada
    input  wire                          s_axis_tvalid,  //! Señal de datos de entrada validos
    output wire                          s_axis_tready,  //! Señal de ready para datos de entrada
    input  wire                          s_axis_tlast,   //! Señal last para datos de entrada
    input  wire [ID_WIDTH-1:0]           s_axis_tid,     //! ID de entrada
    input  wire [DEST_WIDTH-1:0]         s_axis_tdest,   //! Destino de entrada
    input  wire [USER_WIDTH-1:0]         s_axis_tuser,   //! Usuario de entrada
 
    /*
    * Salida de flujo AXI
    */
    output wire [DATA_WIDTH-1:0]         m_axis_tdata,   //! Datos de salida
    output wire [KEEP_WIDTH-1:0]         m_axis_tkeep,   //! Señal keep de salida
    output wire                          m_axis_tvalid,  //! Señal de válida para datos de salida
    input  wire                          m_axis_tready,  //! Señal de ready para datos de salida
    output wire                          m_axis_tlast,   //! Señal last para datos de salida
    output wire [ID_WIDTH-1:0]           m_axis_tid,     //! ID de salida
    output wire [DEST_WIDTH-1:0]         m_axis_tdest,   //! Destino de salida
    output wire [USER_WIDTH-1:0]         m_axis_tuser,   //! Usuario de salida
 
    /*
    * Interfaz del marco de control MAC
    */
    output wire                          mcf_valid,      //! Señal de marco de control MAC valido
    output wire [47:0]                   mcf_eth_dst,    //! Dirección MAC de destino para el marco de control MAC
    output wire [47:0]                   mcf_eth_src,    //! Dirección MAC de origen para el marco de control MAC
    output wire [15:0]                   mcf_eth_type,   //! Tipo Ethernet para el marco de control MAC
    output wire [15:0]                   mcf_opcode,     //! Opcode para el marco de control MAC
    output wire [MCF_PARAMS_SIZE*8-1:0]  mcf_params,     //! Parámetros para el marco de control MAC
    output wire [ID_WIDTH-1:0]           mcf_id,         //! ID para el marco de control MAC
    output wire [DEST_WIDTH-1:0]         mcf_dest,       //! Destino para el marco de control MAC
    output wire [USER_WIDTH-1:0]         mcf_user,       //! Campo de usuario para el marco de control MAC
 
    /*
    * Configuración
    */
    input  wire [47:0]                   cfg_mcf_rx_eth_dst_mcast,       //! Configuración de dirección MAC de destino multicast
    input  wire                          cfg_mcf_rx_check_eth_dst_mcast, //! Verificación de dirección MAC de destino multicast
    input  wire [47:0]                   cfg_mcf_rx_eth_dst_ucast,       //! Configuración de dirección MAC de destino unicast
    input  wire                          cfg_mcf_rx_check_eth_dst_ucast, //! Verificación de dirección MAC de destino unicast
    input  wire [47:0]                   cfg_mcf_rx_eth_src,             //! Configuración de dirección MAC de origen
    input  wire                          cfg_mcf_rx_check_eth_src,       //! Verificación de dirección MAC de origen
    input  wire [15:0]                   cfg_mcf_rx_eth_type,            //! Configuración de tipo Ethernet
    input  wire [15:0]                   cfg_mcf_rx_opcode_lfc,          //! Opcode para Control de Flujo de Enlace (LFC)
    input  wire                          cfg_mcf_rx_check_opcode_lfc,    //! Verificación de opcode de Control de Flujo de Enlace (LFC)
    input  wire [15:0]                   cfg_mcf_rx_opcode_pfc,          //! Opcode para Control de Flujo de Prioridad (PFC)
    input  wire                          cfg_mcf_rx_check_opcode_pfc,    //! Verificación de opcode de Control de Flujo de Prioridad (PFC)
    input  wire                          cfg_mcf_rx_forward,             //! Configuración de habilitación de reenvío
    input  wire                          cfg_mcf_rx_enable,              //! Configuración de habilitación de recepción de marco de control MAC
 
    /*
     * Estado
     */
    output wire                          stat_rx_mcf     //! Salida de estado para el marco de control MAC
);
 
parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;    //! Ancho de carriles de bytes

parameter HDR_SIZE = 60;                                //! Tamaño del encabezado en bytes
 
parameter CYCLE_COUNT = (HDR_SIZE + BYTE_LANES - 1) / BYTE_LANES; //! Cantidad de ciclos necesarios para el encabezado
 
parameter PTR_WIDTH = $clog2(CYCLE_COUNT);              //! Ancho del puntero para el número de ciclos
 
parameter OFFSET = HDR_SIZE % BYTE_LANES;               //! Desplazamiento del tamaño del encabezado en bytes
 

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

This module manages the reception of MAC control frames.  Incoming frames are
checked based on the ethertype and (optionally) MAC addresses.  Matching control
frames are marked by setting tuser[0] on the data output and forwarded through
a separate interface for processing.

*/

reg read_mcf_reg = 1'b1, read_mcf_next;         //! Registro de lectura de MCF
reg mcf_frame_reg = 1'b0, mcf_frame_next;       //! Registro de marco de MCF
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;      //! Registro de puntero

reg s_axis_tready_reg = 1'b0, s_axis_tready_next; //! Registro de listo para la salida

// internal datapath
reg  [DATA_WIDTH-1:0]   m_axis_tdata_int;         //! Registro para almacenar datos en el camino de datos interno
reg  [KEEP_WIDTH-1:0]   m_axis_tkeep_int;         //! Registro para almacenar señales de keep en el camino de datos interno
reg                     m_axis_tvalid_int;        //! Registro para almacenar la señal de validez en el camino de datos interno
reg                     m_axis_tready_int_reg = 1'b0; //! Registro para almacenar la señal de preparado en el camino de datos interno
reg                     m_axis_tlast_int;         //! Registro para almacenar la señal de último en el camino de datos interno
reg  [ID_WIDTH-1:0]     m_axis_tid_int;           //! Registro para almacenar el ID en el camino de datos interno
reg  [DEST_WIDTH-1:0]   m_axis_tdest_int;         //! Registro para almacenar el destino en el camino de datos interno
reg  [USER_WIDTH-1:0]   m_axis_tuser_int;         //! Registro para almacenar la información de usuario en el camino de datos interno
wire                    m_axis_tready_int_early;  //! Wire para la señal temprana de preparado en el camino de datos interno


reg                          mcf_valid_reg = 0, mcf_valid_next;         //! Válido de MCF
reg [47:0]                   mcf_eth_dst_reg = 0, mcf_eth_dst_next;     //! Destino Ethernet de MCF
reg [47:0]                   mcf_eth_src_reg = 0, mcf_eth_src_next;     //! Origen Ethernet de MCF
reg [15:0]                   mcf_eth_type_reg = 0, mcf_eth_type_next;   //! Tipo Ethernet de MCF
reg [15:0]                   mcf_opcode_reg = 0, mcf_opcode_next;       //! Opcode de MCF
reg [MCF_PARAMS_SIZE*8-1:0]  mcf_params_reg = 0, mcf_params_next;       //! Parámetros de MCF
reg [ID_WIDTH-1:0]           mcf_id_reg = 0, mcf_id_next;               //! ID de MCF
reg [DEST_WIDTH-1:0]         mcf_dest_reg = 0, mcf_dest_next;           //! Destino de MCF
reg [USER_WIDTH-1:0]         mcf_user_reg = 0, mcf_user_next;           //! Usuario de MCF


reg stat_rx_mcf_reg = 1'b0, stat_rx_mcf_next;

assign s_axis_tready = s_axis_tready_reg;

assign mcf_valid = mcf_valid_reg;
assign mcf_eth_dst = mcf_eth_dst_reg;
assign mcf_eth_src = mcf_eth_src_reg;
assign mcf_eth_type = mcf_eth_type_reg;
assign mcf_opcode = mcf_opcode_reg;
assign mcf_params = mcf_params_reg;
assign mcf_id = mcf_id_reg;
assign mcf_dest = mcf_dest_reg;
assign mcf_user = mcf_user_reg;

assign stat_rx_mcf = stat_rx_mcf_reg;

wire mcf_eth_dst_mcast_match = mcf_eth_dst_next == cfg_mcf_rx_eth_dst_mcast;
wire mcf_eth_dst_ucast_match = mcf_eth_dst_next == cfg_mcf_rx_eth_dst_ucast;
wire mcf_eth_src_match = mcf_eth_src_next == cfg_mcf_rx_eth_src;
wire mcf_eth_type_match = mcf_eth_type_next == cfg_mcf_rx_eth_type;
wire mcf_opcode_lfc_match = mcf_opcode_next == cfg_mcf_rx_opcode_lfc;
wire mcf_opcode_pfc_match = mcf_opcode_next == cfg_mcf_rx_opcode_pfc;

wire mcf_eth_dst_match = ((mcf_eth_dst_mcast_match && cfg_mcf_rx_check_eth_dst_mcast) ||
    (mcf_eth_dst_ucast_match && cfg_mcf_rx_check_eth_dst_ucast) ||
    (!cfg_mcf_rx_check_eth_dst_mcast && !cfg_mcf_rx_check_eth_dst_ucast));

wire mcf_opcode_match = ((mcf_opcode_lfc_match && cfg_mcf_rx_check_opcode_lfc) ||
    (mcf_opcode_pfc_match && cfg_mcf_rx_check_opcode_pfc) ||
    (!cfg_mcf_rx_check_opcode_lfc && !cfg_mcf_rx_check_opcode_pfc));

wire mcf_match = (mcf_eth_dst_match &&
    (mcf_eth_src_match || !cfg_mcf_rx_check_eth_src) &&
    mcf_eth_type_match && mcf_opcode_match);

integer k;

//! Implementa la lógica para capturar y procesar un encabezado MAC desde un flujo de datos AXI, almacenando sus campos en registros internos y tomando decisiones basadas en configuraciones y señales de control
always @* begin
    read_mcf_next = read_mcf_reg;
    mcf_frame_next = mcf_frame_reg;
    ptr_next = ptr_reg;

    // pass through data
    m_axis_tdata_int = s_axis_tdata;
    m_axis_tkeep_int = s_axis_tkeep;
    m_axis_tvalid_int = s_axis_tvalid;
    m_axis_tlast_int = s_axis_tlast;
    m_axis_tid_int = s_axis_tid;
    m_axis_tdest_int = s_axis_tdest;
    m_axis_tuser_int = s_axis_tuser;

    s_axis_tready_next = m_axis_tready_int_early || !USE_READY;

    mcf_valid_next = 1'b0;
    mcf_eth_dst_next = mcf_eth_dst_reg;
    mcf_eth_src_next = mcf_eth_src_reg;
    mcf_eth_type_next = mcf_eth_type_reg;
    mcf_opcode_next = mcf_opcode_reg;
    mcf_params_next = mcf_params_reg;
    mcf_id_next = mcf_id_reg;
    mcf_dest_next = mcf_dest_reg;
    mcf_user_next = mcf_user_reg;

    stat_rx_mcf_next = 1'b0;

    // si el canal de salida está listo (o no se utiliza el ready) y el canal de entrada es válido
    if ((s_axis_tready || !USE_READY) && s_axis_tvalid) begin
        // si se está leyendo el registro de control MAC
        if (read_mcf_reg) begin
            ptr_next = ptr_reg + 1; // incrementa el puntero para el siguiente byte

            // captura los campos del encabezado MAC
            mcf_id_next = s_axis_tid; // captura el ID del encabezado
            mcf_dest_next = s_axis_tdest; // captura el destino del encabezado
            mcf_user_next = s_axis_tuser; // captura el usuario del encabezado

            // macro para leer campos del encabezado según el offset
            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    field = s_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

            `_HEADER_FIELD_(0,  mcf_eth_dst_next[5*8 +: 8])   // captura la parte alta de la dirección de destino
            `_HEADER_FIELD_(1,  mcf_eth_dst_next[4*8 +: 8])   // captura la siguiente parte de la dirección de destino
            `_HEADER_FIELD_(2,  mcf_eth_dst_next[3*8 +: 8])   // captura la siguiente parte de la dirección de destino
            `_HEADER_FIELD_(3,  mcf_eth_dst_next[2*8 +: 8])   // captura la siguiente parte de la dirección de destino
            `_HEADER_FIELD_(4,  mcf_eth_dst_next[1*8 +: 8])   // captura la siguiente parte de la dirección de destino
            `_HEADER_FIELD_(5,  mcf_eth_dst_next[0*8 +: 8])   // captura la parte baja de la dirección de destino
            `_HEADER_FIELD_(6,  mcf_eth_src_next[5*8 +: 8])   // captura la parte alta de la dirección de origen
            `_HEADER_FIELD_(7,  mcf_eth_src_next[4*8 +: 8])   // captura la siguiente parte de la dirección de origen
            `_HEADER_FIELD_(8,  mcf_eth_src_next[3*8 +: 8])   // captura la siguiente parte de la dirección de origen
            `_HEADER_FIELD_(9,  mcf_eth_src_next[2*8 +: 8])   // captura la siguiente parte de la dirección de origen
            `_HEADER_FIELD_(10, mcf_eth_src_next[1*8 +: 8])   // captura la siguiente parte de la dirección de origen
            `_HEADER_FIELD_(11, mcf_eth_src_next[0*8 +: 8])   // captura la parte baja de la dirección de origen
            `_HEADER_FIELD_(12, mcf_eth_type_next[1*8 +: 8])  // captura el byte alto del tipo de Ethernet
            `_HEADER_FIELD_(13, mcf_eth_type_next[0*8 +: 8])  // captura el byte bajo del tipo de Ethernet
            `_HEADER_FIELD_(14, mcf_opcode_next[1*8 +: 8])    // captura el byte alto del código de operación
            `_HEADER_FIELD_(15, mcf_opcode_next[0*8 +: 8])    // captura el byte bajo del código de operación

            // si está en el primer byte de los parámetros, se limpia el campo
            if (ptr_reg == 0/BYTE_LANES) begin
                mcf_params_next = 0;
            end

            // captura de parámetros adicionales del encabezado MAC
            for (k = 0; k < MCF_PARAMS_SIZE; k = k + 1) begin
                if (ptr_reg == (16+k)/BYTE_LANES) begin
                    mcf_params_next[k*8 +: 8] = s_axis_tdata[((16+k)%BYTE_LANES)*8 +: 8];
                end
            end

            // si está en el último byte del encabezado MAC y se cumple la condición de 'keep'
            if (ptr_reg == 15/BYTE_LANES && (!KEEP_ENABLE || s_axis_tkeep[13%BYTE_LANES])) begin
                // se registra la coincidencia al final del campo de opcode
                mcf_frame_next = mcf_match && cfg_mcf_rx_enable;
            end

            // si se llega al último byte del encabezado MAC
            if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES) begin
                read_mcf_next = 1'b0; // termina la lectura del encabezado
            end

            `undef _HEADER_FIELD_ // se deshace la macro
        end

        // si se recibe el último byte del paquete
        if (s_axis_tlast) begin
            // si el paquete está marcado como inválido
            if (s_axis_tuser[0]) begin
                // el marco está marcado como inválido
            end else if (mcf_frame_next) begin
                // si no se debe reenviar el paquete, se marca como inválido
                if (!cfg_mcf_rx_forward) begin
                    m_axis_tuser_int[0] = 1'b1;
                end
                // se transfiere el encabezado MAC saliente
                mcf_valid_next = 1'b1;
                stat_rx_mcf_next = 1'b1;
            end

            // se prepara para leer el siguiente encabezado
            read_mcf_next = 1'b1;
            mcf_frame_next = 1'b0;
            ptr_next = 0;
        end
    end

end

//! Actualiza datos con la señal del clock
always @(posedge clk) begin
    read_mcf_reg <= read_mcf_next;
    mcf_frame_reg <= mcf_frame_next;
    ptr_reg <= ptr_next;

    s_axis_tready_reg <= s_axis_tready_next;

    mcf_valid_reg <= mcf_valid_next;
    mcf_eth_dst_reg <= mcf_eth_dst_next;
    mcf_eth_src_reg <= mcf_eth_src_next;
    mcf_eth_type_reg <= mcf_eth_type_next;
    mcf_opcode_reg <= mcf_opcode_next;
    mcf_params_reg <= mcf_params_next;
    mcf_id_reg <= mcf_id_next;
    mcf_dest_reg <= mcf_dest_next;
    mcf_user_reg <= mcf_user_next;

    stat_rx_mcf_reg <= stat_rx_mcf_next;

    if (rst) begin
        read_mcf_reg <= 1'b1;
        mcf_frame_reg <= 1'b0;
        ptr_reg <= 0;
        s_axis_tready_reg <= 1'b0;
        mcf_valid_reg <= 1'b0;
        stat_rx_mcf_reg <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};        //! Registro para datos de salida
reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};        //! Registro para mantener bits de datos de salida válidos
reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;  //! Registro de señal de validez actual y siguiente
reg                  m_axis_tlast_reg  = 1'b0;                      //! Registro de señal de último dato de salida
reg [ID_WIDTH-1:0]   m_axis_tid_reg    = {ID_WIDTH{1'b0}};          //! Registro de identificador de transacción de salida
reg [DEST_WIDTH-1:0] m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};        //! Registro de destino de transacción de salida
reg [USER_WIDTH-1:0] m_axis_tuser_reg  = {USER_WIDTH{1'b0}};        //! Registro de datos de usuario de salida

reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};   //! Registro temporal para datos de salida
reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};   //! Registro temporal para mantener bits de datos de salida válidos
reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next; //! Registro temporal de señal de validez actual y siguiente
reg                  temp_m_axis_tlast_reg  = 1'b0;                 //! Registro temporal de señal de último dato de salida
reg [ID_WIDTH-1:0]   temp_m_axis_tid_reg    = {ID_WIDTH{1'b0}};     //! Registro temporal de identificador de transacción de salida
reg [DEST_WIDTH-1:0] temp_m_axis_tdest_reg  = {DEST_WIDTH{1'b0}};   //! Registro temporal de destino de transacción de salida
reg [USER_WIDTH-1:0] temp_m_axis_tuser_reg  = {USER_WIDTH{1'b0}};   //! Registro temporal de datos de usuario de salida

// datapath control
reg store_axis_int_to_output;                                       //! Señal para almacenar datos internos en la salida
reg store_axis_int_to_temp;                                         //! Señal para almacenar datos internos en el registro temporal
reg store_axis_temp_to_output;                                      //! Señal para almacenar datos temporales en la salida

assign m_axis_tdata  = m_axis_tdata_reg;
assign m_axis_tkeep  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_axis_tvalid = m_axis_tvalid_reg;
assign m_axis_tlast  = m_axis_tlast_reg;
assign m_axis_tid    = ID_ENABLE   ? m_axis_tid_reg   : {ID_WIDTH{1'b0}};
assign m_axis_tdest  = DEST_ENABLE ? m_axis_tdest_reg : {DEST_WIDTH{1'b0}};
assign m_axis_tuser  = USER_ENABLE ? m_axis_tuser_reg : {USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axis_tready_int_early = m_axis_tready || !USE_READY || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_tvalid_int));

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
        if (m_axis_tready || !USE_READY || !m_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_tready || !USE_READY) begin
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
