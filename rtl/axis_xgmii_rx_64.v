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
 * AXI4-Stream XGMII frame receiver (XGMII in, AXI out)
 */
 //! Modulo que convierte interfaz XGMII a AXI
 module axis_xgmii_rx_64 #
 (
     parameter DATA_WIDTH = 64,                                      //! Parametro que define el tamaño de los datos
     parameter KEEP_WIDTH = (DATA_WIDTH/8),                          //! Cantidad de bytes de datos que deben ser validos
     parameter CTRL_WIDTH = (DATA_WIDTH/8),                          //! Cantidad de bits de control
     parameter PTP_TS_ENABLE = 0,                                    //! Flag para habilitar protocolo PTP
     parameter PTP_TS_FMT_TOD = 1,                                   //! Flag para cambiar el formato de la marca de tiempo según "Time of day"
     parameter PTP_TS_WIDTH = PTP_TS_FMT_TOD ? 96 : 64,              //! Parametro del ancho de la marca del tiempo
     parameter USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1   //! Parametro que define el ancho de los datos de usuario
 )
 (
     input  wire                     clk,                            //! Señal de clock
     input  wire                     rst,                            //! Señal de reset
 
     /*
      * XGMII input
      */
     input  wire [DATA_WIDTH-1:0]    xgmii_rxd,                      //! Entrada de datos de interfaz XGMII
     input  wire [CTRL_WIDTH-1:0]    xgmii_rxc,                      //! Entrada de control de interfaz XGMII
 
     /*
      * AXI output
      */
     output wire [DATA_WIDTH-1:0]    m_axis_tdata,                   //! Salida de datos de la interfaz AXI
     output wire [KEEP_WIDTH-1:0]    m_axis_tkeep,                   //! Salida de bits válidos de la interfaz AXI
     output wire                     m_axis_tvalid,                  //! Señal de datos válidos de la interfaz AXI
     output wire                     m_axis_tlast,                   //! Señal de fin de trama de la interfaz AXI
     output wire [USER_WIDTH-1:0]    m_axis_tuser,                   //! Salida de datos de usuario de la interfaz AXI
 
     /*
      * PTP
      */
     input  wire [PTP_TS_WIDTH-1:0]  ptp_ts,                         //! Entrada de marca de tiempo PTP
 
     /*
      * Configuration
      */
     input  wire                     cfg_rx_enable,                  //! Señal de configuración para habilitar recepción
 
     /*
      * Status
      */
     output wire [1:0]               start_packet,                   //! Estado indicando inicio de paquete
     output wire                     error_bad_frame,                //! Señal de error para trama incorrecta
     output wire                     error_bad_fcs                   //! Señal de error para FCS incorrecto
 );
 
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
    ETH_PRE = 8'h55,                                              //! Preambulo de Ethernet
    ETH_SFD = 8'hD5;                                              //! Delimitador de inicio de paquete

localparam [7:0]
    XGMII_IDLE = 8'h07,                                         //! Estado de Idle en la interfaz XGMII
    XGMII_START = 8'hfb,                                        //! Inicio de trama en la interfaz XGMII
    XGMII_TERM = 8'hfd,                                         //! Fin de trama en la interfaz XGMII
    XGMII_ERROR = 8'hfe;                                        //! Error en la interfaz XGMII

localparam [1:0]
    STATE_IDLE = 2'd0,                                          //! Estado Idle
    STATE_PAYLOAD = 2'd1,                                       //! Estado Payload
    STATE_LAST = 2'd2;                                          //! Estado Último 

reg [1:0] state_reg = STATE_IDLE, state_next;                   //! Registro de estado actual y siguiente

// Control de la ruta de datos
reg reset_crc;                                                  //! Señal para resetear el cálculo de CRC

reg lanes_swapped = 1'b0;                                       //! Flag que indica de si los lanes están intercambiados
reg [31:0] swap_rxd = 32'd0;                                    //! Registro para el intercambio de datos RXD
reg [3:0] swap_rxc = 4'd0;                                      //! Registro para el intercambio de control RXC
reg [3:0] swap_rxc_term = 4'd0;                                 //! Registro para el intercambio de control RXC para término de trama

reg [DATA_WIDTH-1:0] xgmii_rxd_masked = {DATA_WIDTH{1'b0}};     //! Datos XGMII con máscara de bits
reg [CTRL_WIDTH-1:0] xgmii_term = {CTRL_WIDTH{1'b0}};           //! Control XGMII para el final de trama
reg [2:0] term_lane_reg = 0, term_lane_d0_reg = 0;              //! Registro para el lane del final y el lane del final del ciclo anterior
reg term_present_reg = 1'b0;                                    //! Registro para indicar la presencia del final de trama
reg framing_error_reg = 1'b0, framing_error_d0_reg = 1'b0;      //! Registro para indicar error de frame

reg [DATA_WIDTH-1:0] xgmii_rxd_d0 = {DATA_WIDTH{1'b0}};         //! Registro de datos XGMII del ciclo anterior
reg [DATA_WIDTH-1:0] xgmii_rxd_d1 = {DATA_WIDTH{1'b0}};         //! Registro de datos XGMII del ciclo anterior (1 ciclo atrás)

reg [CTRL_WIDTH-1:0] xgmii_rxc_d0 = {CTRL_WIDTH{1'b0}};         //! Registro de control XGMII del ciclo anterior

reg xgmii_start_swap = 1'b0;                                    //! Flag para indicar inicio de trama con swap
reg xgmii_start_d0 = 1'b0;                                      //! Flag para indicar inicio de trama en el ciclo anterior
reg xgmii_start_d1 = 1'b0;                                      //! Flag para indicar inicio de trama en el ciclo anterior (1 ciclo atrás)

reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}}, m_axis_tdata_next;  //! Registro de datos de salida AXI
reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg = {KEEP_WIDTH{1'b0}}, m_axis_tkeep_next;  //! Registro de bits válidos de salida AXI
reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;                               //! Registro de señal de datos válidos de salida AXI
reg m_axis_tlast_reg = 1'b0, m_axis_tlast_next;                                 //! Registro de señal de fin de trama de salida AXI
reg [USER_WIDTH-1:0] m_axis_tuser_reg = {USER_WIDTH{1'b0}}, m_axis_tuser_next;  //! Registro de datos de usuario de salida AXI

reg [1:0] start_packet_reg = 2'b00;                                             //! Registro de estado indicando inicio de paquete
reg error_bad_frame_reg = 1'b0, error_bad_frame_next;                           //! Registro de señal de error para trama incorrecta
reg error_bad_fcs_reg = 1'b0, error_bad_fcs_next;                               //! Registro de señal de error para FCS incorrecto
// FCS == frame check sequence

reg [PTP_TS_WIDTH-1:0] ptp_ts_reg = 0;                                          //! Registro de marca de tiempo PTP
reg [PTP_TS_WIDTH-1:0] ptp_ts_adj_reg = 0;                                      //! Registro de marca de tiempo PTP ajustada
reg ptp_ts_borrow_reg = 0;                                                      //! Registro de deuda de marca de tiempo PTP
// CRC = Cyclic Redundancy Check
reg [31:0] crc_state = 32'hFFFFFFFF;                                            //! Estado del CRC

wire [31:0] crc_next;                                                           //! Próximo estado del CRC

wire [7:0] crc_valid;                                                           //! Señales de validación del CRC
reg [7:0] crc_valid_save;                                                       //! Registro de señales de validación del CRC

// Asignaciones para las señales de validación del CRC
assign crc_valid[7] = crc_next == ~32'h2144df1c;
assign crc_valid[6] = crc_next == ~32'hc622f71d;
assign crc_valid[5] = crc_next == ~32'hb1c2a1a3;
assign crc_valid[4] = crc_next == ~32'h9d6cdf7e;
assign crc_valid[3] = crc_next == ~32'h6522df69;
assign crc_valid[2] = crc_next == ~32'he60914ae;
assign crc_valid[1] = crc_next == ~32'he38a6876;
assign crc_valid[0] = crc_next == ~32'h6b87b1ec;

reg [4+16-1:0] last_ts_reg = 0;                                             //! Registro para el último timestamp
reg [4+16-1:0] ts_inc_reg = 0;                                              //! Registro para el incremento del timestamp

assign m_axis_tdata = m_axis_tdata_reg;                                     // Asignación de salida de datos AXI
assign m_axis_tkeep = m_axis_tkeep_reg;                                     // Asignación de salida de bits válidos AXI
assign m_axis_tvalid = m_axis_tvalid_reg;                                   // Asignación de salida de señal de datos válidos AXI
assign m_axis_tlast = m_axis_tlast_reg;                                     // Asignación de salida de señal de fin de trama AXI
assign m_axis_tuser = m_axis_tuser_reg;                                     // Asignación de salida de datos de usuario AXI

assign start_packet = start_packet_reg;                                     // Asignación de estado de inicio de paquete
assign error_bad_frame = error_bad_frame_reg;                               // Asignación de señal de error para trama incorrecta
assign error_bad_fcs = error_bad_fcs_reg;                                   // Asignación de señal de error para FCS incorrecto


//! Instanciacion del lsfr para calcular el CRC
lfsr #(
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h4c11db7),
    .LFSR_CONFIG("GALOIS"),
    .LFSR_FEED_FORWARD(0),
    .REVERSE(1),
    .DATA_WIDTH(64),
    .STYLE("AUTO")
)
eth_crc (
    .data_in(xgmii_rxd_d0),
    .state_in(crc_state),
    .data_out(),
    .state_out(crc_next)
);


integer j;

//! Aplica mascara a los datos de entrada
always @* begin
    for (j = 0; j < 8; j = j + 1) begin
        xgmii_rxd_masked[j*8 +: 8] = xgmii_rxc[j] ? 8'd0 : xgmii_rxd[j*8 +: 8];
        xgmii_term[j] = xgmii_rxc[j] && (xgmii_rxd[j*8 +: 8] == XGMII_TERM);
    end
end

//! Gestiona estados como la espera de inicio de paquetes, la lectura de la carga útil del paquete, y la verificación y manejo de errores, incluido el CRC
always @* begin
    state_next = STATE_IDLE;

    reset_crc = 1'b0;

    m_axis_tdata_next = xgmii_rxd_d1;
    m_axis_tkeep_next = {KEEP_WIDTH{1'b1}};
    m_axis_tvalid_next = 1'b0;
    m_axis_tlast_next = 1'b0;
    m_axis_tuser_next = m_axis_tuser_reg;
    m_axis_tuser_next[0] = 1'b0;

    error_bad_frame_next = 1'b0;
    error_bad_fcs_next = 1'b0;

    case (state_reg)
        // Si el estado es idle
        STATE_IDLE: begin
            // idle state - wait for packet
            reset_crc = 1'b1; // resetea el CRC

            if (xgmii_start_d1 && cfg_rx_enable) begin // si está el RX habilitado y XGMII_START activo
                reset_crc = 1'b0; // desactiva el reset del CRC
                state_next = STATE_PAYLOAD; // el siguiente estado es PAYLOAD
            end else begin
                state_next = STATE_IDLE; // el siguiente estado es IDLE
            end
        end

        // Si el estado es payload
        STATE_PAYLOAD: begin
            // lee los datos
            m_axis_tdata_next = xgmii_rxd_d1; // copia los datos recibidos a la salida
            m_axis_tkeep_next = {KEEP_WIDTH{1'b1}}; // marca los bytes como válidos
            m_axis_tvalid_next = 1'b1; // marca el dato como válido
            m_axis_tlast_next = 1'b0; // indica que no es el último dato
            m_axis_tuser_next[0] = 1'b0; // reinicia el bit de usuario

            if (PTP_TS_ENABLE) begin
                // añade la marca de tiempo PTP si está habilitada
                m_axis_tuser_next[1 +: PTP_TS_WIDTH] = (!PTP_TS_FMT_TOD || ptp_ts_borrow_reg) ? ptp_ts_reg : ptp_ts_adj_reg;
            end

            if (framing_error_reg || framing_error_d0_reg) begin
                // si hay errores de encuadre o caracteres de control en el paquete
                m_axis_tlast_next = 1'b1; // marca el último dato del paquete
                m_axis_tuser_next[0] = 1'b1; // indica error en el bit de usuario
                error_bad_frame_next = 1'b1; // indica que hay error en el paquete
                reset_crc = 1'b1; // activa el reset del CRC
                state_next = STATE_IDLE; // vuelve al estado IDLE
            end else if (term_present_reg) begin
                reset_crc = 1'b1; // activa el reset del CRC
                if (term_lane_reg <= 4) begin
                    // finaliza el ciclo
                    m_axis_tkeep_next = {KEEP_WIDTH{1'b1}} >> (CTRL_WIDTH-4-term_lane_reg); // ajusta el ancho de mantener
                    m_axis_tlast_next = 1'b1; // marca el último dato del paquete

                    // verifica la validez del CRC
                    if ((term_lane_reg == 0 && crc_valid_save[7]) ||
                        (term_lane_reg == 1 && crc_valid[0]) ||
                        (term_lane_reg == 2 && crc_valid[1]) ||
                        (term_lane_reg == 3 && crc_valid[2]) ||
                        (term_lane_reg == 4 && crc_valid[3])) begin
                        // CRC válido
                    end else begin
                        m_axis_tuser_next[0] = 1'b1; // indica error en el bit de usuario
                        error_bad_frame_next = 1'b1; // indica error en el paquete
                        error_bad_fcs_next = 1'b1; // indica error en el FCS
                    end
                    state_next = STATE_IDLE; // vuelve al estado IDLE
                end else begin
                    state_next = STATE_LAST; // el siguiente estado es LAST
                end
            end else begin
                state_next = STATE_PAYLOAD; // el siguiente estado es PAYLOAD
            end
        end

        // Si el estado es last
        STATE_LAST: begin
            // last cycle of packet 
            m_axis_tdata_next = xgmii_rxd_d1; // copia los datos recibidos a la salida
            m_axis_tkeep_next = {KEEP_WIDTH{1'b1}} >> (CTRL_WIDTH+4-term_lane_d0_reg); // ajusta el ancho de mantener para el último ciclo
            m_axis_tvalid_next = 1'b1; // marca el dato como válido
            m_axis_tlast_next = 1'b1; // marca el último dato del paquete
            m_axis_tuser_next[0] = 1'b0; // reinicia el bit de usuario

            reset_crc = 1'b1; // activa el reset del CRC

            // verifica la validez del CRC
            if ((term_lane_d0_reg == 5 && crc_valid_save[4]) ||
                (term_lane_d0_reg == 6 && crc_valid_save[5]) ||
                (term_lane_d0_reg == 7 && crc_valid_save[6])) begin
                // CRC válido
            end else begin
                m_axis_tuser_next[0] = 1'b1; // indica error en el bit de usuario
                error_bad_frame_next = 1'b1; // indica error en el paquete
                error_bad_fcs_next = 1'b1; // indica error en el FCS
            end

            if (xgmii_start_d1 && cfg_rx_enable) begin
                // start condition
                reset_crc = 1'b0; // desactiva el reset del CRC
                state_next = STATE_PAYLOAD; // el siguiente estado es PAYLOAD
            end else begin
                state_next = STATE_IDLE; // el siguiente estado es IDLE
            end
        end
    endcase

end

integer i;

//! Realiza la asignación de datos según las diferentes condiciones de intercambio de lanes y marcas de tiempo PTP
always @(posedge clk) begin
    state_reg <= state_next;

    m_axis_tdata_reg <= m_axis_tdata_next;
    m_axis_tkeep_reg <= m_axis_tkeep_next;
    m_axis_tvalid_reg <= m_axis_tvalid_next;
    m_axis_tlast_reg <= m_axis_tlast_next;
    m_axis_tuser_reg <= m_axis_tuser_next;

    start_packet_reg <= 2'b00;
    error_bad_frame_reg <= error_bad_frame_next;
    error_bad_fcs_reg <= error_bad_fcs_next;

    swap_rxd <= xgmii_rxd_masked[63:32];
    swap_rxc <= xgmii_rxc[7:4];
    swap_rxc_term <= xgmii_term[7:4];

    xgmii_start_swap <= 1'b0;
    xgmii_start_d0 <= xgmii_start_swap;

    // Ajuste de la marca de tiempo PTP si PTP_TS_ENABLE y PTP_TS_FMT_TOD están habilitados
    if (PTP_TS_ENABLE && PTP_TS_FMT_TOD) begin
        // ns field rollover == ajuste de desbordamiento del campo ns
        ptp_ts_adj_reg[15:0] <= ptp_ts_reg[15:0]; // copia los primeros 16 bits de ptp_ts_reg a ptp_ts_adj_reg
        {ptp_ts_borrow_reg, ptp_ts_adj_reg[45:16]} <= $signed({1'b0, ptp_ts_reg[45:16]}) - $signed(31'd1000000000); // ajusta ptp_ts_adj_reg para manejar el desbordamiento
        ptp_ts_adj_reg[47:46] <= 0; // reinicia los bits 47 y 46 de ptp_ts_adj_reg
        ptp_ts_adj_reg[95:48] <= ptp_ts_reg[95:48] + 1; // incrementa el campo superior de la marca de tiempo
    end

    // detecta si se intercambiaron carriles
    if (lanes_swapped) begin
        // si los carriles están intercambiados
        xgmii_rxd_d0 <= {xgmii_rxd_masked[31:0], swap_rxd}; // aplica el intercambio de lanes los datos recibidos
        xgmii_rxc_d0 <= {xgmii_rxc[3:0], swap_rxc}; // aplica el intercambio de lanes a los controles recibidos

        term_lane_reg <= 0; // reinicia el registro de carril del terminacion
        term_present_reg <= 1'b0; // reinicia la señal de presencia de terminacion
        framing_error_reg <= {xgmii_rxc[3:0], swap_rxc} != 0; // verifica los errores de trama

        // busca el carácter de finalizacion en los datos de control recibidos
        for (i = CTRL_WIDTH-1; i >= 0; i = i - 1) begin
            if ({xgmii_term[3:0], swap_rxc_term} & (1 << i)) begin
                term_lane_reg <= i; // establece el carril de finalizacion encontrado
                term_present_reg <= 1'b1; // activa la flag de term_present
                framing_error_reg <= ({xgmii_rxc[3:0], swap_rxc} & ({CTRL_WIDTH{1'b1}} >> (CTRL_WIDTH-i))) != 0; // verifica errores de trama
                lanes_swapped <= 1'b0; // desactiva el intercambio de lanes
            end
        end
    end else begin
        // si los carriles no están intercambiados
        xgmii_rxd_d0 <= xgmii_rxd_masked; // aplica los datos recibidos a xgmii_rxd_d0
        xgmii_rxc_d0 <= xgmii_rxc; // aplica los datos de control recibidos a xgmii_rxc_d0

        term_lane_reg <= 0; // reinicia el registro de carril de finalizacion
        term_present_reg <= 1'b0; // reinicia la señal de term presente
        framing_error_reg <= xgmii_rxc != 0; // verifica los errores de trama

        // busca el carácter de terminación en los datos de control recibidos
        for (i = CTRL_WIDTH-1; i >= 0; i = i - 1) begin
            if (xgmii_rxc[i] && (xgmii_rxd[i*8 +: 8] == XGMII_TERM)) begin
                term_lane_reg <= i; // establece el carril de finalizacion encontrado
                term_present_reg <= 1'b1; // activa la flag de term_present
                framing_error_reg <= (xgmii_rxc & ({CTRL_WIDTH{1'b1}} >> (CTRL_WIDTH-i))) != 0; // verifica errores de trama
                lanes_swapped <= 1'b0; // desactiva el intercambio de carriles
            end
        end
    end

    // detección del carácter de inicio en los datos de control
    if (xgmii_rxc[0] && xgmii_rxd[7:0] == XGMII_START) begin
        // si se detecta el carácter de inicio de control (sin intercambio de carriles)
        lanes_swapped <= 1'b0; // desactiva el intercambio de lanes

        xgmii_start_d0 <= 1'b1; // indica el inicio del paquete

        term_lane_reg <= 0; // reinicia el registro de carril de finalizacion
        term_present_reg <= 1'b0; // baja la flag de term_present
        framing_error_reg <= xgmii_rxc[7:1] != 0; // verifica los errores de trama
    end else if (xgmii_rxc[4] && xgmii_rxd[39:32] == XGMII_START) begin
        // si se detecta el carácter de inicio de control (con intercambio de carriles)
        lanes_swapped <= 1'b1; // activa el intercambio de carriles

        xgmii_start_swap <= 1'b1; // indica el inicio del paquete con swap

        term_lane_reg <= 0; // reinicia el registro de carril de finalizacion
        term_present_reg <= 1'b0; // baja la flag de term_present
        framing_error_reg <= xgmii_rxc[7:5] != 0; // verifica los errores de trama
    end

    if (xgmii_start_swap) begin
        // si se detecta el inicio del paquete con intercambio de carriles
        start_packet_reg <= 2'b10; // marca el inicio del paquete como detectado

        if (PTP_TS_FMT_TOD) begin
            // si se utiliza el formato de marca de tiempo "Time of Day"
            ptp_ts_reg[45:0] <= ptp_ts[45:0] + (ts_inc_reg >> 1); // ajusta la marca de tiempo para "Time of Day"
            ptp_ts_reg[95:48] <= ptp_ts[95:48]; // mantiene el valor superior de la marca de tiempo
        end else begin
            // si no se utiliza el formato de marca de tiempo "Time of Day"
            ptp_ts_reg <= ptp_ts + (ts_inc_reg >> 1); // ajusta la marca de tiempo según el incremento
        end
    end

    if (xgmii_start_d0) begin
        // si se detecta el inicio del paquete (sin intercambio de carriles)
        if (!lanes_swapped) begin
            start_packet_reg <= 2'b01; // marca el inicio del paquete como detectado

            ptp_ts_reg <= ptp_ts; // copia la marca de tiempo actual
        end
    end

    term_lane_d0_reg <= term_lane_reg;
    framing_error_d0_reg <= framing_error_reg;

    if (reset_crc) begin
        crc_state <= 32'hFFFFFFFF;
    end else begin
        crc_state <= crc_next;
    end

    crc_valid_save <= crc_valid;

    xgmii_rxd_d1 <= xgmii_rxd_d0;
    xgmii_start_d1 <= xgmii_start_d0;

    last_ts_reg <= ptp_ts;
    ts_inc_reg <= ptp_ts - last_ts_reg;

    if (rst) begin
        state_reg <= STATE_IDLE;

        m_axis_tvalid_reg <= 1'b0;

        start_packet_reg <= 2'b00;
        error_bad_frame_reg <= 1'b0;
        error_bad_fcs_reg <= 1'b0;

        xgmii_rxc_d0 <= {CTRL_WIDTH{1'b0}};

        xgmii_start_swap <= 1'b0;
        xgmii_start_d0 <= 1'b0;
        xgmii_start_d1 <= 1'b0;

        lanes_swapped <= 1'b0;
    end
end

endmodule

`resetall
