module eth_mac_10g_rx_tb;

    // Parameters
    parameter DATA_WIDTH                = 64                                                                                                 ;                                    
    parameter KEEP_WIDTH                = (DATA_WIDTH/8)                                                                                            ;                        
    parameter CTRL_WIDTH                = (DATA_WIDTH/8)                                                                                            ;                        
    parameter ENABLE_PADDING            = 1                                                                                                         ;     
    parameter ENABLE_DIC                = 1                                                                                                         ;                                    
    parameter MIN_FRAME_LENGTH          = 64                                                                                                        ;                                                                         
    parameter PTP_TS_ENABLE             = 1                                                                                                         ;
    parameter PTP_TS_FMT_TOD            = 1                                                                                                         ;
    parameter PTP_TS_WIDTH              = PTP_TS_FMT_TOD ? 96 : 64                                                                                  ;          
    parameter TX_PTP_TS_CTRL_IN_TUSER   = 0                                                                                                         ;                    
    parameter TX_PTP_TAG_ENABLE         = PTP_TS_ENABLE                                                                                             ;                                
    parameter TX_PTP_TAG_WIDTH          = 16                                                                                                        ;                                   
    parameter TX_USER_WIDTH             = (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? TX_PTP_TAG_WIDTH : 0) + (TX_PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1  ;
    parameter RX_USER_WIDTH             = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1                                                                    ;  
    parameter PFC_ENABLE                = 0                                                                                                         ;                                                                           
    parameter PAUSE_ENABLE              = PFC_ENABLE                                                                                                ;
    parameter TOTAL_PACKETS_WIDTH       = 8                                                                                                         ;           

    //Ports
    reg                                  rx_clk                                                                                                         ;
    reg                                  rx_rst                                                                                                         ;
    wire [DATA_WIDTH            - 1 : 0] rx_axis_tdata                                                                                                  ;
    wire [KEEP_WIDTH            - 1 : 0] rx_axis_tkeep                                                                                                  ;
    wire                                 rx_axis_tvalid                                                                                                 ;
    wire                                 rx_axis_tlast                                                                                                  ;
    wire [RX_USER_WIDTH         - 1 : 0] rx_axis_tuser                                                                                                  ;
    reg  [DATA_WIDTH            - 1 : 0] xgmii_rxd                                                                                                      ;
    reg  [CTRL_WIDTH            - 1 : 0] xgmii_rxc                                                                                                      ;
    reg  [PTP_TS_WIDTH          - 1 : 0] rx_ptp_ts                                                                                                      ;
    reg                                  rx_lfc_en                                                                                                      ;
    wire                                 rx_lfc_req                                                                                                     ;
    reg                                  rx_lfc_ack                                                                                                     ;
    reg  [7                         : 0] rx_pfc_en                                                                                                      ;
    wire [7                         : 0] rx_pfc_req                                                                                                     ;
    reg  [7                         : 0] rx_pfc_ack                                                                                                     ;
    wire [1                         : 0] rx_start_packet                                                                                                ;
    wire                                 rx_error_bad_frame                                                                                             ;
    wire                                 rx_error_bad_fcs                                                                                               ;
    wire                                 stat_rx_mcf                                                                                                    ;
    wire                                 stat_rx_lfc_pkt                                                                                                ;
    wire                                 stat_rx_lfc_xon                                                                                                ;
    wire                                 stat_rx_lfc_xoff                                                                                               ;
    wire                                 stat_rx_lfc_paused                                                                                             ;
    wire                                 stat_rx_pfc_pkt                                                                                                ;
    wire [7                         : 0] stat_rx_pfc_xon                                                                                                ;
    wire [7                         : 0] stat_rx_pfc_xoff                                                                                               ;
    wire [7                         : 0] stat_rx_pfc_paused                                                                                             ;
    reg  [7                         : 0] cfg_ifg                                                                                                        ;   
    reg                                  cfg_rx_enable                                                                                                  ;
    reg [47                         : 0] cfg_mcf_rx_eth_dst_mcast                                                                                       ;
    reg                                  cfg_mcf_rx_check_eth_dst_mcast                                                                                 ;
    reg [47                         : 0] cfg_mcf_rx_eth_dst_ucast                                                                                       ;
    reg                                  cfg_mcf_rx_check_eth_dst_ucast                                                                                 ;
    reg [47                         : 0] cfg_mcf_rx_eth_src                                                                                             ;
    reg                                  cfg_mcf_rx_check_eth_src                                                                                       ;
    reg [15                         : 0] cfg_mcf_rx_eth_type                                                                                            ;
    reg [15                         : 0] cfg_mcf_rx_opcode_lfc                                                                                          ;
    reg                                  cfg_mcf_rx_check_opcode_lfc                                                                                    ;
    reg [15                         : 0] cfg_mcf_rx_opcode_pfc                                                                                          ;
    reg                                  cfg_mcf_rx_check_opcode_pfc                                                                                    ;
    reg                                  cfg_mcf_rx_forward                                                                                             ;
    reg                                  cfg_mcf_rx_enable                                                                                              ;
    reg [15                         : 0] cfg_rx_lfc_opcode                                                                                              ;
    reg                                  cfg_rx_lfc_en                                                                                                  ;
    reg [15                         : 0] cfg_rx_pfc_opcode                                                                                              ;
    reg                                  cfg_rx_pfc_en                                                                                                  ;
    reg [TOTAL_PACKETS_WIDTH    - 1 : 0] payload_packets                                                                                                ;        
    reg [DATA_WIDTH - 1 : 0] payload;
                   

    localparam [7:0]
        ETH_PRE = 8'h55                                                                                                                                 ,
        ETH_SFD = 8'hD5                                                                                                                                 ;

    localparam [7:0]
        XGMII_IDLE = 8'h07                                                                                                                              ,
        XGMII_START = 8'hfb                                                                                                                             ,
        XGMII_TERM = 8'hfd                                                                                                                              ,
        XGMII_ERROR = 8'hfe                                                                                                                             ;

    integer i                                                                                                                                           ;                  

    always #5  rx_clk =~ rx_clk                                                                                                                         ;

    initial begin
        rx_clk                          = 1'b0                                                                                                          ;
        rx_rst                          = 1'b1                                                                                                          ;
        #100                                                                                                                                            ;       
        @(posedge rx_clk) rx_rst = 1'b0                                                                                                                 ;
        xgmii_rxc                       = {CTRL_WIDTH{1'b0}}                                                                                            ;
        xgmii_rxd                       = {DATA_WIDTH{1'b0}}                                                                                            ;
        cfg_rx_enable                   = 1'b0                                                                                                          ;
        cfg_mcf_rx_eth_dst_mcast        = {48{1'b0}}                                                                                                    ;
        cfg_mcf_rx_check_eth_dst_mcast  = 1'b0                                                                                                          ;
        cfg_mcf_rx_eth_dst_ucast        = {48{1'b0}}                                                                                                    ;
        cfg_mcf_rx_check_eth_dst_ucast  = 1'b0                                                                                                          ;
        cfg_mcf_rx_eth_src              = {48{1'b0}}                                                                                                    ;
        cfg_mcf_rx_check_eth_src        = 1'b0                                                                                                          ;
        cfg_mcf_rx_eth_type             = {16{1'b0}}                                                                                                    ;
        cfg_mcf_rx_opcode_lfc           = {16{1'b0}}                                                                                                    ;
        cfg_mcf_rx_check_opcode_lfc     = 1'b0                                                                                                          ;
        cfg_mcf_rx_opcode_pfc           = {16{1'b0}}                                                                                                    ;
        cfg_mcf_rx_check_opcode_pfc     = 1'b0                                                                                                          ;
        cfg_mcf_rx_forward              = 1'b0                                                                                                          ;
        cfg_mcf_rx_enable               = 1'b0                                                                                                          ;
        cfg_rx_lfc_opcode               = {16{1'b0}}                                                                                                    ;
        cfg_rx_lfc_en                   = 1'b0                                                                                                          ;
        cfg_rx_pfc_opcode               = {16{1'b0}}                                                                                                    ;
        cfg_rx_pfc_en                   = 1'b0                                                                                                          ;
        rx_lfc_en                       = 1'b0                                                                                                          ;
        rx_lfc_ack                      = 1'b0                                                                                                          ;
        rx_pfc_en                       = 8'b0                                                                                                          ;
        rx_pfc_ack                      = 8'b0                                                                                                          ;
        cfg_rx_lfc_opcode               = {16{1'b0}}                                                                                                    ;
        cfg_rx_lfc_en                   = 1'b0                                                                                                          ;
        cfg_rx_pfc_opcode               = {16{1'b0}}                                                                                                    ;
        cfg_rx_pfc_en                   = 1'b0                                                                                                          ;
        @(posedge rx_clk)                                                                                                                               ;
        rx_rst = 1'b0                                                                                                                                   ;
        xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_START}                                                                                        ;
        xgmii_rxc = {CTRL_WIDTH{1'b0}}                                                                                                                  ;
        cfg_rx_enable = 1'b1                                                                                                                            ;
        #10                                                                                                                                           ;
        @(posedge rx_clk)                                                                                                                               ;  
        rx_payload_packet(8);
        xgmii_rxc = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_TERM};
        #10;
        @(posedge rx_clk);
        rx_iddle_packet();
        #100;
        @(posedge rx_clk);
        
        $finish                                                                                                                                         ;    
    end


    task rx_iddle_packet()                                                                                                                              ;
    begin                                                                                      
        xgmii_rxd = {DATA_WIDTH /2 {XGMII_IDLE}}                                                                                                                                                                                               ;
        xgmii_rxc = {CTRL_WIDTH {1'b0}}                                                                                                                 ;
    end                                                                                     
    endtask                                                                                     

    task rx_start_packet_initial()                                                                                                                      ;
    begin                                                                                       
        xgmii_rxd = {ETH_SFD, {6{ETH_PRE}}, XGMII_START}                                                                                                ;
        xgmii_rxc = {{CTRL_WIDTH - 1 {1'b0}}, 1'b1}                                                                                                     ;
    end                                                                                     
    endtask                                                                                     

    task rx_error_packet()                                                                                                                              ;
    begin                                                                                       
        xgmii_rxd = {XGMII_TERM, {7{XGMII_ERROR}}}                                                                                                      ;
        xgmii_rxc = {CTRL_WIDTH {1'b1}}                                                                                                                 ;
    end 
    endtask 

    task rx_term_packet()                                                                                                                               ;            
    begin                                                                                                       
        xgmii_rxd = {XGMII_TERM, {7{XGMII_IDLE}}}                                                                                                       ;      
        xgmii_rxc = {CTRL_WIDTH {1'b0}}                                                                                                                 ;      
    end 
    endtask 

    task rx_payload_packet(input [TOTAL_PACKETS_WIDTH -1 : 0] total_packets)                                                                            ;
    begin   
        payload = {DATA_WIDTH{1'b0}}                                                                                                                    ;
        for(i = 0; i < total_packets; i = i + 1) begin  
            payload[7  : 0 ] = payload[63 : 56]                                                                                                         ;
            payload[15 : 8 ] = payload[7  : 0 ] + 1                                                                                                     ;
            payload[23 : 16] = payload[15 : 8 ] + 1                                                                                                     ;
            payload[31 : 24] = payload[23 : 16] + 1                                                                                                     ;
            payload[39 : 32] = payload[31 : 24] + 1                                                                                                     ;
            payload[47 : 40] = payload[39 : 32] + 1                                                                                                     ;
            payload[63 : 56] = payload[55 : 48] + 1                                                                                                     ;
            xgmii_rxd        = payload                                                                                                                  ;
            xgmii_rxc        = {CTRL_WIDTH {1'b0}}                                                                                                      ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
        end
    end
    endtask

    eth_mac_10g 
    #(  
        .DATA_WIDTH                     (DATA_WIDTH                     )                                                                               ,
        .KEEP_WIDTH                     (KEEP_WIDTH                     )                                                                               ,
        .CTRL_WIDTH                     (CTRL_WIDTH                     )                                                                               ,
        .ENABLE_PADDING                 (ENABLE_PADDING                 )                                                                               ,
        .ENABLE_DIC                     (ENABLE_DIC                     )                                                                               ,
        .MIN_FRAME_LENGTH               (MIN_FRAME_LENGTH               )                                                                               ,
        .PTP_TS_ENABLE                  (PTP_TS_ENABLE                  )                                                                               ,
        .PTP_TS_FMT_TOD                 (PTP_TS_FMT_TOD                 )                                                                               ,
        .PTP_TS_WIDTH                   (PTP_TS_WIDTH                   )                                                                               ,
        .TX_PTP_TS_CTRL_IN_TUSER        (TX_PTP_TS_CTRL_IN_TUSER        )                                                                               ,
        .TX_PTP_TAG_ENABLE              (TX_PTP_TAG_ENABLE              )                                                                               ,
        .TX_PTP_TAG_WIDTH               (TX_PTP_TAG_WIDTH               )                                                                               ,
        .TX_USER_WIDTH                  (TX_USER_WIDTH                  )                                                                               ,
        .RX_USER_WIDTH                  (RX_USER_WIDTH                  )                                                                               ,
        .PFC_ENABLE                     (PFC_ENABLE                     )                                                                               ,
        .PAUSE_ENABLE                   (PAUSE_ENABLE                   )                                                                               
    )                                                                               
    dut 
    (   
        .rx_rst                         (rx_rst                         )                                                                               ,
        .tx_clk                         (                               )                                                                               ,
        .rx_clk                         (rx_clk                         )                                                                               ,
        .tx_rst                         (                               )                                                                               ,
        .tx_axis_tdata                  (                               )                                                                               ,
        .tx_axis_tkeep                  (                               )                                                                               ,
        .tx_axis_tvalid                 (                               )                                                                               ,
        .tx_axis_tready                 (                               )                                                                               ,
        .tx_axis_tlast                  (                               )                                                                               ,
        .tx_axis_tuser                  (                               )                                                                               ,
        .rx_axis_tdata                  (rx_axis_tdata                  )                                                                               ,
        .rx_axis_tkeep                  (rx_axis_tkeep                  )                                                                               ,
        .rx_axis_tvalid                 (rx_axis_tvalid                 )                                                                               ,
        .rx_axis_tlast                  (rx_axis_tlast                  )                                                                               ,
        .rx_axis_tuser                  (rx_axis_tuser                  )                                                                               ,
        .xgmii_rxd                      (xgmii_rxd                      )                                                                               ,
        .xgmii_rxc                      (xgmii_rxc                      )                                                                               ,
        .xgmii_txd                      (                               )                                                                               ,
        .xgmii_txc                      (                               )                                                                               ,
        .tx_ptp_ts                      (                               )                                                                               ,
        .rx_ptp_ts                      (rx_ptp_ts                      )                                                                               ,
        .tx_axis_ptp_ts                 (                               )                                                                               ,
        .tx_axis_ptp_ts_tag             (                               )                                                                               ,
        .tx_axis_ptp_ts_valid           (                               )                                                                               ,
        .tx_lfc_req                     (                               )                                                                               ,
        .tx_lfc_resend                  (                               )                                                                               ,
        .rx_lfc_en                      (rx_lfc_en                      )                                                                               ,
        .rx_lfc_req                     (rx_lfc_req                     )                                                                               ,
        .rx_lfc_ack                     (rx_lfc_ack                     )                                                                               ,
        .tx_pfc_req                     (                               )                                                                               ,
        .tx_pfc_resend                  (                               )                                                                               ,
        .rx_pfc_en                      (rx_pfc_en                      )                                                                               ,
        .rx_pfc_req                     (rx_pfc_req                     )                                                                               ,
        .rx_pfc_ack                     (rx_pfc_ack                     )                                                                               ,
        .tx_lfc_pause_en                (                               )                                                                               ,
        .tx_pause_req                   (                               )                                                                               , 
        .tx_pause_ack                   (                               )                                                                               , 
        .tx_start_packet                (                               )                                                                               ,
        .tx_error_underflow             (                               )                                                                               ,
        .rx_start_packet                (rx_start_packet                )                                                                               ,
        .rx_error_bad_frame             (rx_error_bad_frame             )                                                                               ,
        .rx_error_bad_fcs               (rx_error_bad_fcs               )                                                                               ,
        .stat_tx_mcf                    (                               )                                                                               ,
        .stat_rx_mcf                    (stat_rx_mcf                    )                                                                               ,
        .stat_tx_lfc_pkt                (                               )                                                                               ,
        .stat_tx_lfc_xon                (                               )                                                                               ,
        .stat_tx_lfc_xoff               (                               )                                                                               ,
        .stat_tx_lfc_paused             (                               )                                                                               ,
        .stat_tx_pfc_pkt                (                               )                                                                               ,
        .stat_tx_pfc_xon                (                               )                                                                               ,
        .stat_tx_pfc_xoff               (                               )                                                                               ,
        .stat_tx_pfc_paused             (                               )                                                                               ,
        .stat_rx_lfc_pkt                (stat_rx_lfc_pkt                )                                                                               ,
        .stat_rx_lfc_xon                (stat_rx_lfc_xon                )                                                                               ,
        .stat_rx_lfc_xoff               (stat_rx_lfc_xoff               )                                                                               ,
        .stat_rx_lfc_paused             (stat_rx_lfc_paused             )                                                                               ,
        .stat_rx_pfc_pkt                (stat_rx_pfc_pkt                )                                                                               ,
        .stat_rx_pfc_xon                (stat_rx_pfc_xon                )                                                                               ,
        .stat_rx_pfc_xoff               (stat_rx_pfc_xoff               )                                                                               ,
        .stat_rx_pfc_paused             (stat_rx_pfc_paused             )                                                                               ,
        .cfg_ifg                        (cfg_ifg                        )                                                                               ,
        .cfg_tx_enable                  (                               )                                                                               ,
        .cfg_rx_enable                  (cfg_rx_enable                  )                                                                               ,
        .cfg_mcf_rx_eth_dst_mcast       (cfg_mcf_rx_eth_dst_mcast       )                                                                               ,
        .cfg_mcf_rx_check_eth_dst_mcast (cfg_mcf_rx_check_eth_dst_mcast )                                                                               ,
        .cfg_mcf_rx_eth_dst_ucast       (cfg_mcf_rx_eth_dst_ucast       )                                                                               ,
        .cfg_mcf_rx_check_eth_dst_ucast (cfg_mcf_rx_check_eth_dst_ucast )                                                                               ,
        .cfg_mcf_rx_eth_src             (cfg_mcf_rx_eth_src             )                                                                               ,
        .cfg_mcf_rx_check_eth_src       (cfg_mcf_rx_check_eth_src       )                                                                               ,
        .cfg_mcf_rx_eth_type            (cfg_mcf_rx_eth_type            )                                                                               ,
        .cfg_mcf_rx_opcode_lfc          (cfg_mcf_rx_opcode_lfc          )                                                                               ,
        .cfg_mcf_rx_check_opcode_lfc    (cfg_mcf_rx_check_opcode_lfc    )                                                                               ,
        .cfg_mcf_rx_opcode_pfc          (cfg_mcf_rx_opcode_pfc          )                                                                               ,
        .cfg_mcf_rx_check_opcode_pfc    (cfg_mcf_rx_check_opcode_pfc    )                                                                               ,
        .cfg_mcf_rx_forward             (cfg_mcf_rx_forward             )                                                                               ,
        .cfg_mcf_rx_enable              (cfg_mcf_rx_enable              )                                                                               ,
        .cfg_tx_lfc_eth_dst             (                               )                                                                               ,
        .cfg_tx_lfc_eth_src             (                               )                                                                               ,
        .cfg_tx_lfc_eth_type            (                               )                                                                               ,
        .cfg_tx_lfc_opcode              (                               )                                                                               ,
        .cfg_tx_lfc_en                  (                               )                                                                               ,
        .cfg_tx_lfc_quanta              (                               )                                                                               ,
        .cfg_tx_lfc_refresh             (                               )                                                                               ,
        .cfg_tx_pfc_eth_dst             (                               )                                                                               ,
        .cfg_tx_pfc_eth_src             (                               )                                                                               ,
        .cfg_tx_pfc_eth_type            (                               )                                                                               ,
        .cfg_tx_pfc_opcode              (                               )                                                                               ,
        .cfg_tx_pfc_en                  (                               )                                                                               ,
        .cfg_tx_pfc_quanta              (                               )                                                                               ,
        .cfg_tx_pfc_refresh             (                               )                                                                               ,
        .cfg_rx_lfc_opcode              (cfg_rx_lfc_opcode              )                                                                               ,
        .cfg_rx_lfc_en                  (cfg_rx_lfc_en                  )                                                                               ,
        .cfg_rx_pfc_opcode              (cfg_rx_pfc_opcode              )                                                                               ,
        .cfg_rx_pfc_en                  (cfg_rx_pfc_en                  )                                                                                
    )                                                                                                                                                   ;                                                                          
    
    
endmodule   