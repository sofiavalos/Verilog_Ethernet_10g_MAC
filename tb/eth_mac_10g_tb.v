
module eth_mac_10g_tb;

  // Parameters
    parameter DATA_WIDTH                = 64                                                                                                        ;                                    
    parameter KEEP_WIDTH                = (DATA_WIDTH/8)                                                                                            ;                        
    parameter CTRL_WIDTH                = (DATA_WIDTH/8)                                                                                            ;                        
    parameter ENABLE_PADDING            = 1                                                                                                         ;     
    parameter ENABLE_DIC                = 1                                                                                                         ;                                    
    parameter MIN_FRAME_LENGTH          = 64                                                                                                        ;                                                                         
    parameter PTP_TS_ENABLE             = 0                                                                                                         ;
    parameter PTP_TS_FMT_TOD            = 1                                                                                                         ;
    parameter PTP_TS_WIDTH              = PTP_TS_FMT_TOD ? 96 : 64                                                                                  ;          
    parameter TX_PTP_TS_CTRL_IN_TUSER   = 0                                                                                                         ;                    
    parameter TX_PTP_TAG_ENABLE         = PTP_TS_ENABLE                                                                                             ;                                
    parameter TX_PTP_TAG_WIDTH          = 16                                                                                                        ;                                   
    parameter TX_USER_WIDTH             = (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? TX_PTP_TAG_WIDTH : 0) + (TX_PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1  ;
    parameter RX_USER_WIDTH             = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1                                                                    ;  
    parameter PFC_ENABLE                = 0                                                                                                         ;                                                                           
    parameter PAUSE_ENABLE              = PFC_ENABLE                                                                                                ;

    //Ports
    reg                              rx_clk;
    reg                              rx_rst;
    reg                              tx_clk;
    reg                              tx_rst;
    reg  [DATA_WIDTH        - 1 : 0] tx_axis_tdata;
    reg  [KEEP_WIDTH        - 1 : 0] tx_axis_tkeep;
    reg                              tx_axis_tvalid;
    wire                             tx_axis_tready;
    reg                              tx_axis_tlast;
    reg  [TX_USER_WIDTH     - 1 : 0] tx_axis_tuser;
    wire [DATA_WIDTH        - 1 : 0] rx_axis_tdata;
    wire [KEEP_WIDTH        - 1 : 0] rx_axis_tkeep;
    wire                             rx_axis_tvalid;
    wire                             rx_axis_tlast;
    wire [RX_USER_WIDTH     - 1 : 0] rx_axis_tuser;
    reg  [DATA_WIDTH        - 1 : 0] xgmii_rxd;
    reg  [CTRL_WIDTH        - 1 : 0] xgmii_rxc;
    wire [DATA_WIDTH        - 1 : 0] xgmii_txd;
    wire [CTRL_WIDTH        - 1 : 0] xgmii_txc;
    reg  [PTP_TS_WIDTH      - 1 : 0] tx_ptp_ts;
    reg  [PTP_TS_WIDTH      - 1 : 0] rx_ptp_ts;
    wire [PTP_TS_WIDTH      - 1 : 0] tx_axis_ptp_ts;
    wire [TX_PTP_TAG_WIDTH  - 1 : 0] tx_axis_ptp_ts_tag;
    wire                             tx_axis_ptp_ts_valid;
    reg                              tx_lfc_resend;
    reg                              tx_lfc_req;
    reg                              rx_lfc_en;
    wire                             rx_lfc_req;
    reg                              rx_lfc_ack;
    reg  [7                     : 0] tx_pfc_req;
    reg                              tx_pfc_resend;
    reg  [7                     : 0] rx_pfc_en;
    wire [7                     : 0] rx_pfc_req;
    reg  [7                     : 0] rx_pfc_ack;
    reg                              tx_lfc_pause_en;
    reg                              tx_pause_req;
    wire                             tx_pause_ack;
    wire [1                     : 0] tx_start_packet;
    wire                             tx_error_underflow;
    wire [1                     : 0] rx_start_packet;
    wire                             rx_error_bad_frame;
    wire                             rx_error_bad_fcs;
    wire                             stat_tx_mcf;
    wire                             stat_rx_mcf;
    wire                             stat_tx_lfc_pkt;
    wire                             stat_tx_lfc_xon;
    wire                             stat_tx_lfc_xoff;
    wire                             stat_tx_lfc_paused;
    wire                             stat_tx_pfc_pkt;
    wire [7                     : 0] stat_tx_pfc_xon;
    wire [7                     : 0] stat_tx_pfc_xoff;
    wire [7                     : 0] stat_tx_pfc_paused;
    wire                             stat_rx_lfc_pkt;
    wire                             stat_rx_lfc_xon;
    wire                             stat_rx_lfc_xoff;
    wire                             stat_rx_lfc_paused;
    wire                             stat_rx_pfc_pkt;
    wire [7                     : 0] stat_rx_pfc_xon;
    wire [7                     : 0] stat_rx_pfc_xoff;
    wire [7                     : 0] stat_rx_pfc_paused;
    reg                              cfg_tx_enable;
    reg                              cfg_rx_enable;
    reg [47                     : 0] cfg_mcf_rx_eth_dst_mcast;
    reg                              cfg_mcf_rx_check_eth_dst_mcast;
    reg [47                     : 0] cfg_mcf_rx_eth_dst_ucast;
    reg                              cfg_mcf_rx_check_eth_dst_ucast;
    reg [47                     : 0] cfg_mcf_rx_eth_src;
    reg                              cfg_mcf_rx_check_eth_src;
    reg [15                     : 0] cfg_mcf_rx_eth_type;
    reg [15                     : 0] cfg_mcf_rx_opcode_lfc;
    reg                              cfg_mcf_rx_check_opcode_lfc;
    reg [15                     : 0] cfg_mcf_rx_opcode_pfc;
    reg                              cfg_mcf_rx_check_opcode_pfc;
    reg                              cfg_mcf_rx_forward;
    reg                              cfg_mcf_rx_enable;
    reg [47                     : 0] cfg_tx_lfc_eth_dst;
    reg [47                     : 0] cfg_tx_lfc_eth_src;
    reg [15                     : 0] cfg_tx_lfc_eth_type;
    reg [15                     : 0] cfg_tx_lfc_opcode;
    reg                              cfg_tx_lfc_en;
    reg [15                     : 0] cfg_tx_lfc_quanta;
    reg [15                     : 0] cfg_tx_lfc_refresh;
    reg [47                     : 0] cfg_tx_pfc_eth_dst;
    reg [47                     : 0] cfg_tx_pfc_eth_src;
    reg [15                     : 0] cfg_tx_pfc_eth_type;
    reg [15                     : 0] cfg_tx_pfc_opcode;
    reg                              cfg_tx_pfc_en;
    reg [8*16-1                 : 0] cfg_tx_pfc_quanta;
    reg [8*16-1                 : 0] cfg_tx_pfc_refresh;
    reg [15                     : 0] cfg_rx_lfc_opcode;
    reg                              cfg_rx_lfc_en;
    reg [15                     : 0] cfg_rx_pfc_opcode;
    reg                              cfg_rx_pfc_en;


    eth_mac_10g # (
        .DATA_WIDTH                     (DATA_WIDTH                     ),
        .KEEP_WIDTH                     (KEEP_WIDTH                     ),
        .CTRL_WIDTH                     (CTRL_WIDTH                     ),
        .ENABLE_PADDING                 (ENABLE_PADDING                 ),
        .ENABLE_DIC                     (ENABLE_DIC                     ),
        .MIN_FRAME_LENGTH               (MIN_FRAME_LENGTH               ),
        .PTP_TS_ENABLE                  (PTP_TS_ENABLE                  ),
        .PTP_TS_FMT_TOD                 (PTP_TS_FMT_TOD                 ),
        .PTP_TS_WIDTH                   (PTP_TS_WIDTH                   ),
        .TX_PTP_TS_CTRL_IN_TUSER        (TX_PTP_TS_CTRL_IN_TUSER        ),
        .TX_PTP_TAG_ENABLE              (TX_PTP_TAG_ENABLE              ),
        .TX_PTP_TAG_WIDTH               (TX_PTP_TAG_WIDTH               ),
        .TX_USER_WIDTH                  (TX_USER_WIDTH                  ),
        .RX_USER_WIDTH                  (RX_USER_WIDTH                  ),
        .PFC_ENABLE                     (PFC_ENABLE                     ),
        .PAUSE_ENABLE                   (PAUSE_ENABLE                   )
    )
    dut(
        .rx_clk                         (rx_clk                         ),
        .rx_rst                         (rx_rst                         ),
        .tx_clk                         (tx_clk                         ),
        .tx_rst                         (tx_rst                         ),
        .tx_axis_tdata                  (tx_axis_tdata                  ),
        .tx_axis_tkeep                  (tx_axis_tkeep                  ),
        .tx_axis_tvalid                 (tx_axis_tvalid                 ),
        .tx_axis_tready                 (tx_axis_tready                 ),
        .tx_axis_tlast                  (tx_axis_tlast                  ),
        .tx_axis_tuser                  (tx_axis_tuser                  ),
        .rx_axis_tdata                  (rx_axis_tdata                  ),
        .rx_axis_tkeep                  (rx_axis_tkeep                  ),
        .rx_axis_tvalid                 (rx_axis_tvalid                 ),
        .rx_axis_tlast                  (rx_axis_tlast                  ),
        .rx_axis_tuser                  (rx_axis_tuser                  ),
        .xgmii_rxd                      (xgmii_rxd                      ),
        .xgmii_rxc                      (xgmii_rxc                      ),
        .xgmii_txd                      (xgmii_txd                      ),
        .xgmii_txc                      (xgmii_txc                      ),
        .tx_ptp_ts                      (tx_ptp_ts                      ),
        .rx_ptp_ts                      (rx_ptp_ts                      ),
        .tx_axis_ptp_ts                 (tx_axis_ptp_ts                 ),
        .tx_axis_ptp_ts_tag             (tx_axis_ptp_ts_tag             ),
        .tx_axis_ptp_ts_valid           (tx_axis_ptp_ts_valid           ),
        .tx_lfc_req                     (tx_lfc_req                     ),
        .tx_lfc_resend                  (tx_lfc_resend                  ),
        .rx_lfc_en                      (rx_lfc_en                      ),
        .rx_lfc_req                     (rx_lfc_req                     ),
        .rx_lfc_ack                     (rx_lfc_ack                     ),
        .tx_pfc_req                     (tx_pfc_req                     ),
        .tx_pfc_resend                  (tx_pfc_resend                  ),
        .rx_pfc_en                      (rx_pfc_en                      ),
        .rx_pfc_req                     (rx_pfc_req                     ),
        .rx_pfc_ack                     (rx_pfc_ack                     ),
        .tx_lfc_pause_en                (tx_lfc_pause_en                ),
        .tx_pause_req                   (tx_pause_req                   ), 
        .tx_pause_ack                   (tx_pause_ack                   ), 
        .tx_start_packet                (tx_start_packet                ),
        .tx_error_underflow             (tx_error_underflow             ),
        .rx_start_packet                (rx_start_packet                ),
        .rx_error_bad_frame             (rx_error_bad_frame             ),
        .rx_error_bad_fcs               (rx_error_bad_fcs               ),
        .stat_tx_mcf                    (stat_tx_mcf                    ),
        .stat_rx_mcf                    (stat_rx_mcf                    ),
        .stat_tx_lfc_pkt                (stat_tx_lfc_pkt                ),
        .stat_tx_lfc_xon                (stat_tx_lfc_xon                ),
        .stat_tx_lfc_xoff               (stat_tx_lfc_xoff               ),
        .stat_tx_lfc_paused             (stat_tx_lfc_paused             ),
        .stat_tx_pfc_pkt                (stat_tx_pfc_pkt                ),
        .stat_tx_pfc_xon                (stat_tx_pfc_xon                ),
        .stat_tx_pfc_xoff               (stat_tx_pfc_xoff               ),
        .stat_tx_pfc_paused             (stat_tx_pfc_paused             ),
        .stat_rx_lfc_pkt                (stat_rx_lfc_pkt                ),
        .stat_rx_lfc_xon                (stat_rx_lfc_xon                ),
        .stat_rx_lfc_xoff               (stat_rx_lfc_xoff               ),
        .stat_rx_lfc_paused             (stat_rx_lfc_paused             ),
        .stat_rx_pfc_pkt                (stat_rx_pfc_pkt                ),
        .stat_rx_pfc_xon                (stat_rx_pfc_xon                ),
        .stat_rx_pfc_xoff               (stat_rx_pfc_xoff               ),
        .stat_rx_pfc_paused             (stat_rx_pfc_paused             ),
        .cfg_tx_enable                  (cfg_tx_enable                  ),
        .cfg_rx_enable                  (cfg_rx_enable                  ),
        .cfg_mcf_rx_eth_dst_mcast       (cfg_mcf_rx_eth_dst_mcast       ),
        .cfg_mcf_rx_check_eth_dst_mcast (cfg_mcf_rx_check_eth_dst_mcast ),
        .cfg_mcf_rx_eth_dst_ucast       (cfg_mcf_rx_eth_dst_ucast       ),
        .cfg_mcf_rx_check_eth_dst_ucast (cfg_mcf_rx_check_eth_dst_ucast ),
        .cfg_mcf_rx_eth_src             (cfg_mcf_rx_eth_src             ),
        .cfg_mcf_rx_check_eth_src       (cfg_mcf_rx_check_eth_src       ),
        .cfg_mcf_rx_eth_type            (cfg_mcf_rx_eth_type            ),
        .cfg_mcf_rx_opcode_lfc          (cfg_mcf_rx_opcode_lfc          ),
        .cfg_mcf_rx_check_opcode_lfc    (cfg_mcf_rx_check_opcode_lfc    ),
        .cfg_mcf_rx_opcode_pfc          (cfg_mcf_rx_opcode_pfc          ),
        .cfg_mcf_rx_check_opcode_pfc    (cfg_mcf_rx_check_opcode_pfc    ),
        .cfg_mcf_rx_forward             (cfg_mcf_rx_forward             ),
        .cfg_mcf_rx_enable              (cfg_mcf_rx_enable              ),
        .cfg_tx_lfc_eth_dst             (cfg_tx_lfc_eth_dst             ),
        .cfg_tx_lfc_eth_src             (cfg_tx_lfc_eth_src             ),
        .cfg_tx_lfc_eth_type            (cfg_tx_lfc_eth_type            ),
        .cfg_tx_lfc_opcode              (cfg_tx_lfc_opcode              ),
        .cfg_tx_lfc_en                  (cfg_tx_lfc_en                  ),
        .cfg_tx_lfc_quanta              (cfg_tx_lfc_quanta              ),
        .cfg_tx_lfc_refresh             (cfg_tx_lfc_refresh             ),
        .cfg_tx_pfc_eth_dst             (cfg_tx_pfc_eth_dst             ),
        .cfg_tx_pfc_eth_src             (cfg_tx_pfc_eth_src             ),
        .cfg_tx_pfc_eth_type            (cfg_tx_pfc_eth_type            ),
        .cfg_tx_pfc_opcode              (cfg_tx_pfc_opcode              ),
        .cfg_tx_pfc_en                  (cfg_tx_pfc_en                  ),
        .cfg_tx_pfc_quanta              (cfg_tx_pfc_quanta              ),
        .cfg_tx_pfc_refresh             (cfg_tx_pfc_refresh             ),
        .cfg_rx_lfc_opcode              (cfg_rx_lfc_opcode              ),
        .cfg_rx_lfc_en                  (cfg_rx_lfc_en                  ),
        .cfg_rx_pfc_opcode              (cfg_rx_pfc_opcode              ),
        .cfg_rx_pfc_en                  (cfg_rx_pfc_en                  )
    );

    always #5  rx_clk =~ rx_clk ;
    always #5  tx_clk =~ tx_clk ;

    initial begin
        rx_clk              = 1'b0;
        tx_clk              = 1'b0;
        rx_rst              = 1'b1;
        tx_rst              = 1'b1;
        // Axis
        tx_axis_tdata       = 64'h0000000000000000;
        tx_axis_tkeep       = 8'h00;
        tx_axis_tvalid      = 1'b0;
        tx_axis_tlast       = 1'b0;
        tx_axis_tuser       = 16'h0000;
        // Pause
        tx_pause_req        = 1'b0;
        tx_lfc_pause_en     = 1'b0;
        // Configuracion
        cfg_tx_lfc_en       = 1'b1;
        cfg_tx_lfc_eth_dst  = 48'h000000000000;
        cfg_tx_lfc_eth_src  = 48'h000000000000;
        cfg_tx_lfc_eth_type = 16'h0000;
        cfg_tx_lfc_opcode   = 16'h0000;
        cfg_tx_lfc_quanta   = 16'h0000;
        cfg_tx_lfc_refresh  = 16'h0000;
        cfg_tx_pfc_en       = 1'b0;
        cfg_tx_pfc_eth_dst  = 48'h000000000000;
        cfg_tx_pfc_eth_src  = 48'h000000000000;
        cfg_tx_pfc_eth_type = 16'h0000;
        cfg_tx_pfc_opcode   = 16'h0000;
        cfg_tx_pfc_quanta   = 16'h0000;
        cfg_tx_pfc_refresh  = 16'h0000;
        cfg_tx_enable       = 1'b0;
        // LFC Y PFC TX
        tx_lfc_resend       = 1'b0;
        tx_lfc_req          = 1'b0;
        tx_pfc_resend       = 1'b0;
        tx_pfc_req          = 8'h00;
        // Rx enable
        cfg_rx_enable       = 1'b0;
        // LFC Y PFC RX
        rx_lfc_en           = 1'b0;
        rx_lfc_ack          = 1'b0;
        rx_pfc_en           = 8'h00;
        rx_pfc_ack          = 8'h00;
        #100;
        rx_rst              = 1'b0;
        tx_rst              = 1'b0;
        #100;
        // Envia paquete
        tx_axis_tdata       = 64'h5555555555555555;
        tx_axis_tkeep       = 8'hFF;
        tx_axis_tvalid      = 1'b1;
        cfg_tx_enable       = 1'b1;
        cfg_rx_enable       = 1'b1;
        rx_lfc_en           = 1'b1;
        rx_lfc_ack          = 1'b1;
        rx_pfc_en           = 8'hFF;
        rx_pfc_ack          = 8'hFF;
        #1000;
        // Lfc y Pfc
        tx_lfc_req          = 1'b1;
        tx_pfc_req          = 8'hFF;
        cfg_tx_lfc_en       = 1'b1;
        cfg_tx_lfc_eth_dst  = 48'hFFFFFFFFFFFF;
        cfg_tx_lfc_eth_src  = 48'h333333333333;
        cfg_tx_lfc_eth_type = 16'h8808;
        cfg_tx_lfc_opcode   = 16'h8808;
        cfg_tx_lfc_quanta   = 16'h0001;
        cfg_tx_lfc_refresh  = 16'h0001;
        cfg_tx_pfc_en       = 1'b1;
        cfg_tx_pfc_eth_dst  = 48'h000000000000;
        cfg_tx_pfc_eth_src  = 48'h999999999999;
        cfg_tx_pfc_eth_type = 16'h8808;
        cfg_tx_pfc_opcode   = 16'h8809;
        cfg_tx_pfc_quanta   = 16'h0001;
        cfg_tx_pfc_refresh  = 16'h0001;
        // Pause 
        tx_pause_req        = 1'b1;
        tx_lfc_pause_en     = 1'b1;
        #1000;
        $finish;
    end


    always @(*) begin
        // Interfaz XGMII
        xgmii_rxc <= xgmii_txc;
        xgmii_rxd <= xgmii_txd;

        // Configuracion
        cfg_mcf_rx_eth_dst_mcast <= cfg_tx_lfc_eth_dst;
        cfg_mcf_rx_check_eth_dst_mcast <= 1'b1;
        cfg_mcf_rx_eth_dst_ucast <= cfg_tx_lfc_eth_dst;
        cfg_mcf_rx_check_eth_dst_ucast <= 1'b1;
        cfg_mcf_rx_eth_src <= cfg_tx_lfc_eth_src;
        cfg_mcf_rx_check_eth_src <= 1'b1;
        cfg_mcf_rx_eth_type <= cfg_tx_lfc_eth_type;
        cfg_mcf_rx_opcode_lfc <= cfg_tx_lfc_opcode;
        cfg_mcf_rx_check_opcode_lfc <= 1'b1;
        cfg_mcf_rx_opcode_pfc <= cfg_tx_pfc_opcode;
        cfg_mcf_rx_check_opcode_pfc <= 1'b1;
        cfg_mcf_rx_forward <= 1'b1;
        cfg_mcf_rx_enable <= cfg_rx_enable;
        cfg_rx_lfc_en <= cfg_tx_lfc_en;
        cfg_rx_lfc_opcode <= cfg_tx_lfc_opcode;
        cfg_rx_pfc_en <= cfg_tx_pfc_en;
        cfg_rx_pfc_opcode <= cfg_tx_pfc_opcode;

    end

endmodule