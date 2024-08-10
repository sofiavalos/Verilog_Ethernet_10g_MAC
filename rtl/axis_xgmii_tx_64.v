/*

Copyright (c) 2015-2017 Alex Forencich

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
 * AXI4-Stream XGMII frame transmitter (AXI in, XGMII out)
 */
  //! Modulo que convierte interfaz AXI a XGMII
 module axis_xgmii_tx_64 #
 (
     parameter DATA_WIDTH = 64,                                        //! Parametro que define el tamaño de los datos
     parameter KEEP_WIDTH = (DATA_WIDTH/8),                            //! Cantidad de bytes de datos que deben ser válidos
     parameter CTRL_WIDTH = (DATA_WIDTH/8),                            //! Cantidad de bits de control
     parameter ENABLE_PADDING = 1,                                     //! Flag para habilitar el relleno de tramas
     parameter ENABLE_DIC = 1,                                         //! Flag para habilitar DIC (Data Integrity Check)
     parameter MIN_FRAME_LENGTH = 64,                                  //! Longitud mínima de la trama
     parameter PTP_TS_ENABLE = 0,                                      //! Flag para habilitar protocolo PTP
     parameter PTP_TS_FMT_TOD = 1,                                     //! Flag para cambiar el formato de la marca de tiempo según "Time of day"
     parameter PTP_TS_WIDTH = PTP_TS_FMT_TOD ? 96 : 64,                //! Parametro del ancho de la marca del tiempo
     parameter PTP_TS_CTRL_IN_TUSER = 0,                               //! Flag para habilitar control PTP en tuser
     parameter PTP_TAG_ENABLE = PTP_TS_ENABLE,                         //! Flag para habilitar etiqueta PTP
     parameter PTP_TAG_WIDTH = 16,                                     //! Ancho de la etiqueta PTP
     parameter USER_WIDTH = (PTP_TS_ENABLE ?                           //! Parametro que define el ancho de los datos de usuario
                            (PTP_TAG_ENABLE ? PTP_TAG_WIDTH : 0) + 
                            (PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1
 )
 (
     input  wire                      clk,                             //! Señal de clock
     input  wire                      rst,                             //! Señal de reset
 
     /*
      * AXI input
      */
     input  wire [DATA_WIDTH-1:0]     s_axis_tdata,                    //! Entrada de datos de la interfaz AXI
     input  wire [KEEP_WIDTH-1:0]     s_axis_tkeep,                    //! Entrada de bits válidos de la interfaz AXI
     input  wire                      s_axis_tvalid,                   //! Señal de datos válidos de la interfaz AXI
     output wire                      s_axis_tready,                   //! Señal de que la interfaz AXI está lista para recibir datos
     input  wire                      s_axis_tlast,                    //! Señal de fin de trama de la interfaz AXI
     input  wire [USER_WIDTH-1:0]     s_axis_tuser,                    //! Entrada de datos de usuario de la interfaz AXI
 
     /*
      * XGMII output
      */
     output wire [DATA_WIDTH-1:0]     xgmii_txd,                       //! Salida de datos de la interfaz XGMII
     output wire [CTRL_WIDTH-1:0]     xgmii_txc,                       //! Salida de control de la interfaz XGMII
 
     /*
      * PTP
      */
     input  wire [PTP_TS_WIDTH-1:0]   ptp_ts,                          //! Entrada de marca de tiempo PTP
     output wire [PTP_TS_WIDTH-1:0]   m_axis_ptp_ts,                   //! Salida de marca de tiempo PTP
     output wire [PTP_TAG_WIDTH-1:0]  m_axis_ptp_ts_tag,               //! Salida de etiqueta de marca de tiempo PTP
     output wire                      m_axis_ptp_ts_valid,             //! Señal de validez de marca de tiempo PTP
 
     /*
      * Configuration
      */
     input  wire [7:0]                cfg_ifg,                         //! Señal de configuración de espacio interframe
     input  wire                      cfg_tx_enable,                   //! Señal de configuración para habilitar transmisión
 
     /*
      * Status
      */
     output wire [1:0]                start_packet,                    //! Estado indicando inicio de paquete
     output wire                      error_underflow                  //! Señal de error por desbordamiento
 );
 
 parameter EMPTY_WIDTH = $clog2(KEEP_WIDTH);                           //! Parametro del ancho de vacío
 parameter MIN_LEN_WIDTH = $clog2(MIN_FRAME_LENGTH-4-CTRL_WIDTH+1);    //! Parametro del ancho mínimo de la longitud 

// bus width assertions
initial begin
    if (DATA_WIDTH != 64) begin
        $error("Error: Interface width must be 64");
        $finish;
    end

    if (KEEP_WIDTH * 8 != DATA_WIDTH || CTRL_WIDTH * 8 != DATA_WIDTH) begin
        $error("Error: Interface requires byte (8-bit) granularity");
        $finish;
    end
end

localparam [7:0]
    ETH_PRE = 8'h55,                  //! Preambulo de Ethernet
    ETH_SFD = 8'hD5;                  //! Delimitador de inicio de trama de Ethernet

localparam [7:0]
    XGMII_IDLE = 8'h07,               //! Código de control de XGMII para estado inactivo
    XGMII_START = 8'hfb,              //! Código de control de XGMII para inicio de paquete
    XGMII_TERM = 8'hfd,               //! Código de control de XGMII para terminación de paquete
    XGMII_ERROR = 8'hfe;              //! Código de control de XGMII para error

localparam [2:0]
    STATE_IDLE = 3'd0,                //! Estado IDLE
    STATE_PAYLOAD = 3'd1,             //! Estado PAYLOAD
    STATE_PAD = 3'd2,                 //! Estado PAD
    STATE_FCS_1 = 3'd3,               //! Estado FCS_1
    STATE_FCS_2 = 3'd4,               //! Estado FCS_2
    STATE_ERR = 3'd5,                 //! Estado ERR
    STATE_IFG = 3'd6;                 //! Estado IFG

reg [2:0] state_reg = STATE_IDLE, state_next;                       //! Registro y próximo estado del FSM

// Señales de control del datapath
reg reset_crc;                                                  //! Señal para resetear el CRC
reg update_crc;                                                 //! Señal para actualizar el CRC

reg swap_lanes_reg = 1'b0, swap_lanes_next;                     //! Registro y próximo valor de swap de lanes
reg [31:0] swap_txd = 32'd0;                                    //! Datos para swap de lanes
reg [3:0] swap_txc = 4'd0;                                      //! Datos de control para swap de lanes

reg [DATA_WIDTH-1:0] s_axis_tdata_masked;                       //! Datos de la entrada AXI con máscara aplicada

reg [DATA_WIDTH-1:0] s_tdata_reg = 0, s_tdata_next;             //! Registro y próximo valor de datos de entrada AXI
reg [EMPTY_WIDTH-1:0] s_empty_reg = 0, s_empty_next;            //! Registro y próximo valor de datos vacíos

reg [DATA_WIDTH-1:0] fcs_output_txd_0;                          //! Datos de salida del primer FCS
reg [DATA_WIDTH-1:0] fcs_output_txd_1;                          //! Datos de salida del segundo FCS
reg [CTRL_WIDTH-1:0] fcs_output_txc_0;                          //! Control de salida del primer FCS
reg [CTRL_WIDTH-1:0] fcs_output_txc_1;                          //! Control de salida del segundo FCS

reg [7:0] ifg_offset;                                           //! Desplazamiento para el intervalo entre tramas

reg frame_start_reg = 1'b0, frame_start_next;                               //! Registro y próximo valor de inicio de trama
reg frame_reg = 1'b0, frame_next;                                           //! Registro y próximo valor de trama
reg frame_error_reg = 1'b0, frame_error_next;                               //! Registro y próximo valor de error de trama
reg [MIN_LEN_WIDTH-1:0] frame_min_count_reg = 0, frame_min_count_next;      //! Registro y próximo valor de contador de longitud mínima de trama

reg [7:0] ifg_count_reg = 8'd0, ifg_count_next;                             //! Registro y próximo valor de contador de intervalo entre tramas
reg [1:0] deficit_idle_count_reg = 2'd0, deficit_idle_count_next;           //! Registro y próximo valor de contador de déficit de inactividad

reg s_axis_tready_reg = 1'b0, s_axis_tready_next;                           //! Registro y próximo valor de disponibilidad de AXI

reg [PTP_TS_WIDTH-1:0] m_axis_ptp_ts_reg = 0;                               //! Registro de marca de tiempo PTP
reg [PTP_TS_WIDTH-1:0] m_axis_ptp_ts_adj_reg = 0;                           //! Registro de ajuste de marca de tiempo PTP
reg [PTP_TAG_WIDTH-1:0] m_axis_ptp_ts_tag_reg = 0;                          //! Registro de etiqueta de marca de tiempo PTP
reg m_axis_ptp_ts_valid_reg = 1'b0;                                         //! Registro de validez de marca de tiempo PTP
reg m_axis_ptp_ts_valid_int_reg = 1'b0;                                     //! Registro interno de validez de marca de tiempo PTP
reg m_axis_ptp_ts_borrow_reg = 1'b0;                                        //! Registro de ajuste de marca de tiempo PTP

reg [31:0] crc_state_reg[7:0];                                              //! Registro de estado de CRC
wire [31:0] crc_state_next[7:0];                                            //! Próximo valor del estado de CRC

reg [4+16-1:0] last_ts_reg = 0;                                             //! Registro del último timestamp
reg [4+16-1:0] ts_inc_reg = 0;                                              //! Registro de incremento del timestamp

reg [DATA_WIDTH-1:0] xgmii_txd_reg = {CTRL_WIDTH{XGMII_IDLE}}, xgmii_txd_next;      //! Registro y próximo valor de datos XGMII
reg [CTRL_WIDTH-1:0] xgmii_txc_reg = {CTRL_WIDTH{1'b1}}, xgmii_txc_next;            //! Registro y próximo valor de control XGMII

reg start_packet_reg = 2'b00;                                               //! Registro de inicio de paquete
reg error_underflow_reg = 1'b0, error_underflow_next;                       //! Registro y próximo valor de error por desbordamiento


assign s_axis_tready = s_axis_tready_reg;

assign xgmii_txd = xgmii_txd_reg;
assign xgmii_txc = xgmii_txc_reg;

assign m_axis_ptp_ts = PTP_TS_ENABLE ? ((!PTP_TS_FMT_TOD || m_axis_ptp_ts_borrow_reg) ? m_axis_ptp_ts_reg : m_axis_ptp_ts_adj_reg) : 0;
assign m_axis_ptp_ts_tag = PTP_TAG_ENABLE ? m_axis_ptp_ts_tag_reg : 0;
assign m_axis_ptp_ts_valid = PTP_TS_ENABLE || PTP_TAG_ENABLE ? m_axis_ptp_ts_valid_reg : 1'b0;

assign start_packet = start_packet_reg;
assign error_underflow = error_underflow_reg;

generate
    genvar n;

    for (n = 0; n < 8; n = n + 1) begin : crc
        //! Instancia lfsr para generar CRC
        lfsr #(
            .LFSR_WIDTH(32),
            .LFSR_POLY(32'h4c11db7),
            .LFSR_CONFIG("GALOIS"),
            .LFSR_FEED_FORWARD(0),
            .REVERSE(1),
            .DATA_WIDTH(8*(n+1)),
            .STYLE("AUTO")
        )
        eth_crc (
            .data_in(s_tdata_reg[0 +: 8*(n+1)]),
            .state_in(crc_state_reg[7]),
            .data_out(),
            .state_out(crc_state_next[n])
        );
    end

endgenerate

//! Convierte un byte de control k de 8 bits a un valor de 3 bits que representa el número de bits vacíos (no válidos) en el byte
function [2:0] keep2empty;
    input [7:0] k;
    casez (k)
        8'bzzzzzzz0: keep2empty = 3'd7;
        8'bzzzzzz01: keep2empty = 3'd7;
        8'bzzzzz011: keep2empty = 3'd6;
        8'bzzzz0111: keep2empty = 3'd5;
        8'bzzz01111: keep2empty = 3'd4;
        8'bzz011111: keep2empty = 3'd3;
        8'bz0111111: keep2empty = 3'd2;
        8'b01111111: keep2empty = 3'd1;
        8'b11111111: keep2empty = 3'd0;
    endcase
endfunction

integer j;

//! Aplica mascara a los datos de entrada
always @* begin
    for (j = 0; j < 8; j = j + 1) begin
        s_axis_tdata_masked[j*8 +: 8] = s_axis_tkeep[j] ? s_axis_tdata[j*8 +: 8] : 8'd0;
    end
end

// FCS cycle calculation
//! Calculo del ciclo FCS
always @* begin
    casez (s_empty_reg)
        3'd7: begin
            fcs_output_txd_0 = {{2{XGMII_IDLE}}, XGMII_TERM, ~crc_state_next[0][31:0], s_tdata_reg[7:0]}; // configura los datos de salida con el símbolo de finalizacion y el CRC invertido
            fcs_output_txd_1 = {8{XGMII_IDLE}}; // rellena el resto con símbolos IDLE
            fcs_output_txc_0 = 8'b11100000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11111111; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd3; // establece el offset de IFG
        end
        3'd6: begin
            fcs_output_txd_0 = {XGMII_IDLE, XGMII_TERM, ~crc_state_next[1][31:0], s_tdata_reg[15:0]}; // configura los datos de salida con el símbolo de terminacion y el CRC invertido
            fcs_output_txd_1 = {8{XGMII_IDLE}}; // rellena el resto con símbolos IDLE
            fcs_output_txc_0 = 8'b11000000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11111111; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd2; // establece el offset de IFG
        end
        3'd5: begin
            fcs_output_txd_0 = {XGMII_TERM, ~crc_state_next[2][31:0], s_tdata_reg[23:0]}; // configura los datos de salida con el símbolo de terminacion y el CRC invertido
            fcs_output_txd_1 = {8{XGMII_IDLE}}; // rellena el resto con símbolos IDLE
            fcs_output_txc_0 = 8'b10000000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11111111; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd1; // establece el offset de IFG
        end
        3'd4: begin
            fcs_output_txd_0 = {~crc_state_next[3][31:0], s_tdata_reg[31:0]}; // configura los datos de salida con el CRC invertido
            fcs_output_txd_1 = {{7{XGMII_IDLE}}, XGMII_TERM}; // rellena el resto con símbolos IDLE y termina con el símbolo de finalizacion
            fcs_output_txc_0 = 8'b00000000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11111111; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd8; // establece el offset de IFG
        end
        3'd3: begin
            fcs_output_txd_0 = {~crc_state_next[4][23:0], s_tdata_reg[39:0]}; // configura los datos de salida con el CRC invertido
            fcs_output_txd_1 = {{6{XGMII_IDLE}}, XGMII_TERM, ~crc_state_reg[4][31:24]}; // rellena el resto con símbolos IDLE y termina con el símbolo de finalizacion
            fcs_output_txc_0 = 8'b00000000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11111110; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd7; // establece el offset de IFG
        end
        3'd2: begin
            fcs_output_txd_0 = {~crc_state_next[5][15:0], s_tdata_reg[47:0]}; // configura los datos de salida con el CRC invertido
            fcs_output_txd_1 = {{5{XGMII_IDLE}}, XGMII_TERM, ~crc_state_reg[5][31:16]}; // rellena el resto con símbolos IDLE y termina con el símbolo de finalizacion
            fcs_output_txc_0 = 8'b00000000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11111100; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd6; // establece el offset de IFG
        end
        3'd1: begin
            fcs_output_txd_0 = {~crc_state_next[6][7:0], s_tdata_reg[55:0]}; // configura los datos de salida con el CRC invertido
            fcs_output_txd_1 = {{4{XGMII_IDLE}}, XGMII_TERM, ~crc_state_reg[6][31:8]}; // rellena el resto con símbolos IDLE y termina con el símbolo de finalizacion
            fcs_output_txc_0 = 8'b00000000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11111000; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd5; // establece el offset de IFG
        end
        3'd0: begin
            fcs_output_txd_0 = s_tdata_reg; // copia los datos recibidos directamente
            fcs_output_txd_1 = {{3{XGMII_IDLE}}, XGMII_TERM, ~crc_state_reg[7][31:0]}; // rellena el resto con símbolos IDLE y termina con el símbolo de finalizacion y el CRC invertido
            fcs_output_txc_0 = 8'b00000000; // configura los caracteres de control para indicar terminacion e IDLE
            fcs_output_txc_1 = 8'b11110000; // configura los caracteres de control para indicar terminacion e IDLE
            ifg_offset = 8'd4; // establece el offset de IFG
        end
    endcase
end

//! Define una combinación de asignaciones y lógica de control que determina el comportamiento de un sistema de transmisión de datos
always @* begin
    state_next = STATE_IDLE;

    reset_crc = 1'b0;
    update_crc = 1'b0;

    swap_lanes_next = swap_lanes_reg;

    frame_start_next = 1'b0;
    frame_next = frame_reg;
    frame_error_next = frame_error_reg;
    frame_min_count_next = frame_min_count_reg;

    ifg_count_next = ifg_count_reg;
    deficit_idle_count_next = deficit_idle_count_reg;

    s_axis_tready_next = 1'b0;

    s_tdata_next = s_tdata_reg;
    s_empty_next = s_empty_reg;

    // XGMII idle
    xgmii_txd_next = {CTRL_WIDTH{XGMII_IDLE}};
    xgmii_txc_next = {CTRL_WIDTH{1'b1}};

    error_underflow_next = 1'b0;

    // si los datos son validos y está listo
    if (s_axis_tvalid && s_axis_tready) begin
        frame_next = !s_axis_tlast; // establece el frame siguiente como el opuesto de tlast
    end

    case (state_reg)
        // Caso estado idle
        STATE_IDLE: begin
            frame_error_next = 1'b0; // reinicia la señal de error de trama
            frame_min_count_next = MIN_FRAME_LENGTH-4-CTRL_WIDTH; // establece el contador de longitud mínima de la trama
            reset_crc = 1'b1; // resetea el CRC
            s_axis_tready_next = cfg_tx_enable; // prepara la señal de "ready" si la transmisión está habilitada
        
            // configura los datos y control de XGMII como IDLE
            xgmii_txd_next = {CTRL_WIDTH{XGMII_IDLE}};
            xgmii_txc_next = {CTRL_WIDTH{1'b1}};
        
            s_tdata_next = s_axis_tdata_masked; // copia los datos de entrada para el next
            s_empty_next = keep2empty(s_axis_tkeep); // calcula cuántos bytes son vacíos
        
            if (s_axis_tvalid && s_axis_tready) begin
                // si los datos de entrada son válidos y están listos
                xgmii_txd_next = {ETH_SFD, {6{ETH_PRE}}, XGMII_START}; // configura los datos de salida con el preámbulo y el SFD
                xgmii_txc_next = 8'b00000001; // configura el control de XGMII para indicar el inicio
                frame_start_next = 1'b1; // marca el inicio de la trama
                s_axis_tready_next = 1'b1; // indica que está listo para recibir más datos
                state_next = STATE_PAYLOAD; // pasa al estado PAYLOAD
            end else begin
                swap_lanes_next = 1'b0; // reinicia la señal de intercambio de carriles
                ifg_count_next = 8'd0; // reinicia el contador de IFG
                deficit_idle_count_next = 2'd0; // reinicia el contador de IDLE deficitario
                state_next = STATE_IDLE; // permanece en el estado IDLE
            end
        end
        // Caso estado PAYLOAD
        STATE_PAYLOAD: begin
            // transfer payload
            update_crc = 1'b1; // actualiza el CRC
            s_axis_tready_next = 1'b1; // indica que está listo para recibir más datos
        
            if (frame_min_count_reg > CTRL_WIDTH) begin
                frame_min_count_next = frame_min_count_reg - CTRL_WIDTH; // disminuye el contador de longitud mínima de la trama
            end else begin
                frame_min_count_next = 0; // resetea el contador si es menor o igual al ancho de control
            end
        
            xgmii_txd_next = s_tdata_reg; // pasa los datos del PAYLOAD a la salida
            xgmii_txc_next = {CTRL_WIDTH{1'b0}}; // establece el control a 0 (válido)
        
            s_tdata_next = s_axis_tdata_masked; // copia los datos de entrada a la siguiente etapa
            s_empty_next = keep2empty(s_axis_tkeep); // calcula cuántos bytes son vacíos
        
            if (!s_axis_tvalid || s_axis_tlast) begin
                // si los datos de entrada no son válidos o es el último dato
                s_axis_tready_next = frame_next; // descarta la trama
                frame_error_next = !s_axis_tvalid || s_axis_tuser[0]; // marca error de trama si los datos no son válidos o hay error en el usuario
                error_underflow_next = !s_axis_tvalid; // marca error si los datos no son válidos
        
                if (ENABLE_PADDING && frame_min_count_reg) begin
                    if (frame_min_count_reg > CTRL_WIDTH) begin
                        s_empty_next = 0; // no hay bytes vacíos
                        state_next = STATE_PAD; // pasa al estado de relleno
                    end else begin
                        if (keep2empty(s_axis_tkeep) > CTRL_WIDTH-frame_min_count_reg) begin
                            s_empty_next = CTRL_WIDTH-frame_min_count_reg; // ajusta los bytes vacíos
                        end
                        if (frame_error_next) begin
                            state_next = STATE_ERR; // pasa al estado de error
                        end else begin
                            state_next = STATE_FCS_1; // pasa al estado de cálculo de FCS
                        end
                    end
                end else begin
                    if (frame_error_next) begin
                        state_next = STATE_ERR; // pasa al estado de error
                    end else begin
                        state_next = STATE_FCS_1; // pasa al estado de cálculo de FCS
                    end
                end
            end else begin
                state_next = STATE_PAYLOAD; // permanece en el estado de PAYLOAD
            end
        end
        // Caso estado de relleno
        STATE_PAD: begin
            // pad frame to MIN_FRAME_LENGTH
            s_axis_tready_next = frame_next; // descarta la trama
        
            xgmii_txd_next = s_tdata_reg; // pasa los datos de entrada a la salida XGMII
            xgmii_txc_next = {CTRL_WIDTH{1'b0}}; // establece el control a 0 (válido)
        
            s_tdata_next = 64'd0; // siguiente dato es 0
            s_empty_next = 0; // no hay bytes vacíos
        
            update_crc = 1'b1; // actualiza el CRC
        
            if (frame_min_count_reg > CTRL_WIDTH) begin
                frame_min_count_next = frame_min_count_reg - CTRL_WIDTH; // disminuye el contador de longitud mínima de la trama
                state_next = STATE_PAD; // permanece en el estado de relleno
            end else begin
                frame_min_count_next = 0; // resetea el contador
                s_empty_next = CTRL_WIDTH-frame_min_count_reg; // ajusta los bytes vacíos
                if (frame_error_reg) begin
                    state_next = STATE_ERR; // pasa al estado de error
                end else begin
                    state_next = STATE_FCS_1; // pasa al estado de cálculo de FCS
                end
            end
        end  
        // Caso estado de calculo de FCS
        STATE_FCS_1: begin
            // last cycle
            s_axis_tready_next = frame_next; // descarta la trama
        
            xgmii_txd_next = fcs_output_txd_0; // envía la primera parte del FCS
            xgmii_txc_next = fcs_output_txc_0; // establece el control para la primera parte del FCS
        
            update_crc = 1'b1; // actualiza el CRC
        
            // calcula el intervalo de fragmento de relleno (IFG)
            ifg_count_next = (cfg_ifg > 8'd12 ? cfg_ifg : 8'd12) - ifg_offset + (swap_lanes_reg ? 8'd4 : 8'd0) + deficit_idle_count_reg;
        
            if (s_empty_reg <= 4) begin
                state_next = STATE_FCS_2; // si hay 4 bytes o menos vacíos, pasa al estado FCS_2
            end else begin
                state_next = STATE_IFG; // si hay más de 4 bytes vacíos, pasa al estado IFG
            end
        end
        // Caso calculo de FCS_2        
        STATE_FCS_2: begin
            // last cycle
            s_axis_tready_next = frame_next; // descarta la trama
        
            xgmii_txd_next = fcs_output_txd_1; // envía la segunda parte del FCS
            xgmii_txc_next = fcs_output_txc_1; // establece el control para la segunda parte del FCS
        
            if (ENABLE_DIC) begin
                if (ifg_count_next > 8'd7) begin
                    state_next = STATE_IFG; // si el IFG es mayor a 7, pasa al estado IFG
                end else begin
                    if (ifg_count_next >= 8'd4) begin
                        deficit_idle_count_next = ifg_count_next - 8'd4; // ajusta el conteo de deficit idle
                        swap_lanes_next = 1'b1; // intercambia los carriles
                    end else begin
                        deficit_idle_count_next = ifg_count_next; // ajusta el conteo de deficit idle
                        ifg_count_next = 8'd0; // resetea el conteo de IFG
                        swap_lanes_next = 1'b0; // no intercambia los carriles
                    end
                    s_axis_tready_next = cfg_tx_enable; // habilita la transmisión si está configurado
                    state_next = STATE_IDLE; // vuelve al estado IDLE
                end
            end else begin
                if (ifg_count_next > 8'd4) begin
                    state_next = STATE_IFG; // si el IFG es mayor a 4, pasa al estado IFG
                end else begin
                    s_axis_tready_next = cfg_tx_enable; // habilita la transmisión si está configurado
                    swap_lanes_next = ifg_count_next != 0; // intercambia los carriles si el IFG no es 0
                    state_next = STATE_IDLE; // vuelve al estado IDLE
                end
            end
        end
        // Caso estado de error        
        STATE_ERR: begin
            // terminate packet with error
            s_axis_tready_next = frame_next; // descarta la trama
        
            // XGMII error
            xgmii_txd_next = {XGMII_TERM, {7{XGMII_ERROR}}}; // envía terminación y error en XGMII
            xgmii_txc_next = {CTRL_WIDTH{1'b1}}; // establece el control para el error
        
            ifg_count_next = 8'd12; // establece el intervalo de IFG a 12
        
            stat_next = STATE_IFG; // pasa al estado IFG
        end
        // Caso estado IFG
        STATE_IFG: begin
            // send IFG
            s_axis_tready_next = frame_next; // descarta la trama
        
            // XGMII idle
            xgmii_txd_next = {CTRL_WIDTH{XGMII_IDLE}}; // envía XGMII idle
            xgmii_txc_next = {CTRL_WIDTH{1'b1}}; // establece el control para idle
        
            if (ifg_count_reg > 8'd8) begin
                ifg_count_next = ifg_count_reg - 8'd8; // resta 8 del contador de IFG
            end else begin
                ifg_count_next = 8'd0; // establece el contador de IFG a 0
            end
        
            if (ENABLE_DIC) begin
                if (ifg_count_next > 8'd7 || frame_reg) begin
                    state_next = STATE_IFG; // permanece en el estado IFG si el contador es mayor a 7 o hay trama
                end else begin
                    if (ifg_count_next >= 8'd4) begin
                        deficit_idle_count_next = ifg_count_next - 8'd4; // ajusta el contador de deficit idle
                        swap_lanes_next = 1'b1; // habilita el intercambio de lanes
                    end else begin
                        deficit_idle_count_next = ifg_count_next; // actualiza el contador de deficit idle
                        ifg_count_next = 8'd0; // establece el contador de IFG a 0
                        swap_lanes_next = 1'b0; // deshabilita el intercambio de lanes
                    end
                    s_axis_tready_next = cfg_tx_enable; // habilita la transmisión
                    state_next = STATE_IDLE; // pasa al estado IDLE
                end
            end else begin
                if (ifg_count_next > 8'd4 || frame_reg) begin
                    state_next = STATE_IFG; // permanece en el estado IFG si el contador es mayor a 4 o hay trama
                end else begin
                    s_axis_tready_next = cfg_tx_enable; // habilita la transmisión
                    swap_lanes_next = ifg_count_next != 0; // habilita el intercambio de lanes si el contador no es 0
                    state_next = STATE_IDLE; // pasa al estado IDLE
                end
            end
        end        
    endcase
end

//! Actualiza registros de control y datos, gestiona la marca de tiempo PTP y el estado del CRC, y controla la transmisión de datos a través del medio físico
always @(posedge clk) begin
    state_reg <= state_next;

    swap_lanes_reg <= swap_lanes_next;

    frame_start_reg <= frame_start_next;
    frame_reg <= frame_next;
    frame_error_reg <= frame_error_next;
    frame_min_count_reg <= frame_min_count_next;

    ifg_count_reg <= ifg_count_next;
    deficit_idle_count_reg <= deficit_idle_count_next;

    s_tdata_reg <= s_tdata_next;
    s_empty_reg <= s_empty_next;

    s_axis_tready_reg <= s_axis_tready_next;

    m_axis_ptp_ts_valid_reg <= 1'b0;
    m_axis_ptp_ts_valid_int_reg <= 1'b0;

    start_packet_reg <= 2'b00;
    error_underflow_reg <= error_underflow_next;

    if (PTP_TS_ENABLE && PTP_TS_FMT_TOD) begin
        m_axis_ptp_ts_valid_reg <= m_axis_ptp_ts_valid_int_reg; // actualiza la validez de la marca de tiempo PTP
        m_axis_ptp_ts_adj_reg[15:0] <= m_axis_ptp_ts_reg[15:0]; // copia los 16 bits menos significativos de la marca de tiempo PTP
        {m_axis_ptp_ts_borrow_reg, m_axis_ptp_ts_adj_reg[45:16]} <= $signed({1'b0, m_axis_ptp_ts_reg[45:16]}) - $signed(31'd1000000000); // ajusta la marca de tiempo restando 1,000,000,000
        m_axis_ptp_ts_adj_reg[47:46] <= 0; // establece los bits 47 y 46 a 0
        m_axis_ptp_ts_adj_reg[95:48] <= m_axis_ptp_ts_reg[95:48] + 1; // incrementa los bits 95 a 48 en 1
    end    

    if (frame_start_reg) begin
        if (swap_lanes_reg) begin
            if (PTP_TS_ENABLE) begin
                if (PTP_TS_FMT_TOD) begin
                    m_axis_ptp_ts_reg[45:0] <= ptp_ts[45:0] + (ts_inc_reg >> 1); // ajusta la marca de tiempo sumando la mitad del incremento
                    m_axis_ptp_ts_reg[95:48] <= ptp_ts[95:48]; // copia los bits 95 a 48 de la marca de tiempo
                end else begin
                    m_axis_ptp_ts_reg <= ptp_ts + (ts_inc_reg >> 1); // ajusta la marca de tiempo completa sumando la mitad del incremento
                end
            end
            start_packet_reg <= 2'b10; // actualiza el registro de inicio de paquete
        end else begin
            if (PTP_TS_ENABLE) begin
                m_axis_ptp_ts_reg <= ptp_ts; // copia la marca de tiempo
            end
            start_packet_reg <= 2'b01; // actualiza el registro de inicio de paquete
        end
        if (PTP_TS_ENABLE) begin
            if (PTP_TS_CTRL_IN_TUSER) begin
                m_axis_ptp_ts_tag_reg <= s_axis_tuser >> 2; // extrae la etiqueta de marca de tiempo del bus de usuario
                if (PTP_TS_FMT_TOD) begin
                    m_axis_ptp_ts_valid_int_reg <= s_axis_tuser[1]; // actualiza la validez de la marca de tiempo interna
                end else begin
                    m_axis_ptp_ts_valid_reg <= s_axis_tuser[1]; // actualiza la validez de la marca de tiempo
                end
            end else begin
                m_axis_ptp_ts_tag_reg <= s_axis_tuser >> 1; // extrae la etiqueta de marca de tiempo del bus de usuario
                if (PTP_TS_FMT_TOD) begin
                    m_axis_ptp_ts_valid_int_reg <= 1'b1; // marca la validez de la marca de tiempo interna como válida
                end else begin
                    m_axis_ptp_ts_valid_reg <= 1'b1; // marca la validez de la marca de tiempo como válida
                end
            end
        end
    end    

    crc_state_reg[0] <= crc_state_next[0];
    crc_state_reg[1] <= crc_state_next[1];
    crc_state_reg[2] <= crc_state_next[2];
    crc_state_reg[3] <= crc_state_next[3];
    crc_state_reg[4] <= crc_state_next[4];
    crc_state_reg[5] <= crc_state_next[5];
    crc_state_reg[6] <= crc_state_next[6];

    if (update_crc) begin
        crc_state_reg[7] <= crc_state_next[7];
    end

    if (reset_crc) begin
        crc_state_reg[7] <= 32'hFFFFFFFF;
    end

    swap_txd <= xgmii_txd_next[63:32];
    swap_txc <= xgmii_txc_next[7:4];

    if (swap_lanes_reg) begin
        xgmii_txd_reg <= {xgmii_txd_next[31:0], swap_txd}; // si se deben intercambiar los lanes, combina las 4 primeras líneas de datos con los datos intercambiados
        xgmii_txc_reg <= {xgmii_txc_next[3:0], swap_txc}; // combina las 4 primeras líneas de control con el control intercambiado
    end else begin
        xgmii_txd_reg <= xgmii_txd_next; // si no se intercambian las líneas, simplemente pasa los datos siguientes a los registros
        xgmii_txc_reg <= xgmii_txc_next; 
    end
    

    last_ts_reg <= ptp_ts;
    ts_inc_reg <= ptp_ts - last_ts_reg;

    if (rst) begin
        state_reg <= STATE_IDLE;

        frame_start_reg <= 1'b0;
        frame_reg <= 1'b0;

        swap_lanes_reg <= 1'b0;

        ifg_count_reg <= 8'd0;
        deficit_idle_count_reg <= 2'd0;

        s_axis_tready_reg <= 1'b0;

        m_axis_ptp_ts_valid_reg <= 1'b0;
        m_axis_ptp_ts_valid_int_reg <= 1'b0;

        xgmii_txd_reg <= {CTRL_WIDTH{XGMII_IDLE}};
        xgmii_txc_reg <= {CTRL_WIDTH{1'b1}};

        start_packet_reg <= 2'b00;
        error_underflow_reg <= 1'b0;
    end
end

endmodule

`resetall
