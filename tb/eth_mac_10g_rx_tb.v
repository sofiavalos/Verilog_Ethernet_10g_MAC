module eth_mac_10g_rx_tb;

    // Parameters
    parameter DATA_WIDTH                = 64                                                                                                            ;                                    
    parameter KEEP_WIDTH                = (DATA_WIDTH/8)                                                                                                ;                        
    parameter CTRL_WIDTH                = (DATA_WIDTH/8)                                                                                                ;                        
    parameter ENABLE_PADDING            = 1                                                                                                             ;     
    parameter ENABLE_DIC                = 1                                                                                                             ;                                    
    parameter MIN_FRAME_LENGTH          = 64                                                                                                            ;                                                                         
    parameter PTP_TS_ENABLE             = 1                                                                                                             ;
    parameter PTP_TS_FMT_TOD            = 1                                                                                                             ;
    parameter PTP_TS_WIDTH              = PTP_TS_FMT_TOD ? 96 : 64                                                                                      ;          
    parameter TX_PTP_TS_CTRL_IN_TUSER   = 0                                                                                                             ;                    
    parameter TX_PTP_TAG_ENABLE         = PTP_TS_ENABLE                                                                                                 ;                                
    parameter TX_PTP_TAG_WIDTH          = 16                                                                                                            ;                                   
    parameter TX_USER_WIDTH             = (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? TX_PTP_TAG_WIDTH : 0) + (TX_PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1      ;
    parameter RX_USER_WIDTH             = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1                                                                        ;  
    parameter PFC_ENABLE                = 0                                                                                                             ;                                                                           
    parameter PAUSE_ENABLE              = PFC_ENABLE                                                                                                    ;                                                                                                                 

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
    wire [1                         : 0] rx_start_packet                                                                                                ;
    wire                                 rx_error_bad_frame                                                                                             ;
    wire                                 rx_error_bad_fcs                                                                                               ;
    reg                                  cfg_rx_enable;
                   

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
        xgmii_rxc                       = {CTRL_WIDTH{1'b0}}                                                                                            ;
        xgmii_rxd                       = {DATA_WIDTH{1'b0}}                                                                                            ;
        cfg_rx_enable                   = 1'b0                                                                                                          ;
        #100                                                                                                                                            ;       
        @(posedge rx_clk)                                                                                                                               ;                          
        rx_rst = 1'b0                                                                                                                                   ;    
    end

    `define TEST4 

    `ifdef TEST1
        initial begin
            #100                                                                                                                                        ;               
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_START}                                                                                    ;
            xgmii_rxc = {{CTRL_WIDTH - 1 {1'b0}}, 1'b1}                                                                                                 ;         
            cfg_rx_enable = 1'b1                                                                                                                        ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;  
            xgmii_rxc = {CTRL_WIDTH {1'b0}}                                                                                                             ;
            xgmii_rxd = {DATA_WIDTH {1'b0}}                                                                                                             ;                            
            #60                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;                          
            xgmii_rxc = {CTRL_WIDTH {1'b1}}                                                                                                             ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_TERM}                                                                                     ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {DATA_WIDTH {XGMII_IDLE}}                                                                                                       ;      
            #80                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            $finish                                                                                                                                     ; 
        end
    `elsif TEST2
        initial begin
            #100                                                                                                                                        ;               
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_START}                                                                                    ;
            xgmii_rxc = {{CTRL_WIDTH - 1 {1'b0}}, 1'b1}                                                                                                 ;         
            cfg_rx_enable = 1'b1                                                                                                                        ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;  
            xgmii_rxc = {CTRL_WIDTH {1'b0}}                                                                                                             ;
            xgmii_rxd = {DATA_WIDTH {1'b0}}                                                                                                             ;
            #1870                                                                                                                                       ;
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxc = {CTRL_WIDTH {1'b1}}                                                                                                             ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_TERM}                                                                                     ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {DATA_WIDTH {XGMII_IDLE}}                                                                                                       ;      
            #80                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            $finish                                                                                                                                     ;       
        end
    `elsif TEST3
        initial begin
            #100                                                                                                                                        ;               
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_START}                                                                                    ;
            xgmii_rxc = {{CTRL_WIDTH - 1 {1'b0}}, 1'b1}                                                                                                 ;         
            cfg_rx_enable = 1'b1                                                                                                                        ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;  
            xgmii_rxc = {CTRL_WIDTH {1'b0}}                                                                                                             ;
            xgmii_rxd = {DATA_WIDTH / 2 {2'b01}}                                                                                                        ;
            #50                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {{(DATA_WIDTH / 2) - 8 {2'b10}}, 1'b0}                                                                                          ;                            
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;                          
            xgmii_rxc = {CTRL_WIDTH {1'b1}}                                                                                                             ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_TERM}                                                                                     ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {DATA_WIDTH {XGMII_IDLE}}                                                                                                       ;      
            #80                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            $finish                                                                                                                                     ;
        end
    `elsif TEST4
        initial begin
            #100                                                                                                                                        ;               
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_START}                                                                                    ;
            xgmii_rxc = {{CTRL_WIDTH - 1 {1'b0}}, 1'b1}                                                                                                 ;         
            cfg_rx_enable = 1'b1                                                                                                                        ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;  
            xgmii_rxc = {CTRL_WIDTH {1'b0}}                                                                                                             ;
            xgmii_rxd = {DATA_WIDTH/2 {2'b10}}                                                                                                          ;
            #1880                                                                                                                                       ;
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxc = {CTRL_WIDTH {1'b1}}                                                                                                             ;
            xgmii_rxd = {{DATA_WIDTH - 1 {XGMII_IDLE}}, XGMII_TERM}                                                                                     ;
            #10                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            xgmii_rxd = {DATA_WIDTH {XGMII_IDLE}}                                                                                                       ;      
            #80                                                                                                                                         ;
            @(posedge rx_clk)                                                                                                                           ;
            $finish                                                                                                                                     ;       
        end
    `endif	

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
        .rx_ptp_ts                      (                               )                                                                               ,
        .tx_axis_ptp_ts                 (                               )                                                                               ,
        .tx_axis_ptp_ts_tag             (                               )                                                                               ,
        .tx_axis_ptp_ts_valid           (                               )                                                                               ,
        .tx_lfc_req                     (                               )                                                                               ,
        .tx_lfc_resend                  (                               )                                                                               ,
        .rx_lfc_en                      (                               )                                                                               ,
        .rx_lfc_req                     (                               )                                                                               ,
        .rx_lfc_ack                     (                               )                                                                               ,
        .tx_pfc_req                     (                               )                                                                               ,
        .tx_pfc_resend                  (                               )                                                                               ,
        .rx_pfc_en                      (                               )                                                                               ,
        .rx_pfc_req                     (                               )                                                                               ,
        .rx_pfc_ack                     (                               )                                                                               ,
        .tx_lfc_pause_en                (                               )                                                                               ,
        .tx_pause_req                   (                               )                                                                               , 
        .tx_pause_ack                   (                               )                                                                               , 
        .tx_start_packet                (                               )                                                                               ,
        .tx_error_underflow             (                               )                                                                               ,
        .rx_start_packet                (rx_start_packet                )                                                                               ,
        .rx_error_bad_frame             (rx_error_bad_frame             )                                                                               ,
        .rx_error_bad_fcs               (rx_error_bad_fcs               )                                                                               ,
        .stat_tx_mcf                    (                               )                                                                               ,
        .stat_rx_mcf                    (                               )                                                                               ,
        .stat_tx_lfc_pkt                (                               )                                                                               ,
        .stat_tx_lfc_xon                (                               )                                                                               ,
        .stat_tx_lfc_xoff               (                               )                                                                               ,
        .stat_tx_lfc_paused             (                               )                                                                               ,
        .stat_tx_pfc_pkt                (                               )                                                                               ,
        .stat_tx_pfc_xon                (                               )                                                                               ,
        .stat_tx_pfc_xoff               (                               )                                                                               ,
        .stat_tx_pfc_paused             (                               )                                                                               ,
        .stat_rx_lfc_pkt                (                               )                                                                               ,
        .stat_rx_lfc_xon                (                               )                                                                               ,
        .stat_rx_lfc_xoff               (                               )                                                                               ,
        .stat_rx_lfc_paused             (                               )                                                                               ,
        .stat_rx_pfc_pkt                (                               )                                                                               ,
        .stat_rx_pfc_xon                (                               )                                                                               ,
        .stat_rx_pfc_xoff               (                               )                                                                               ,
        .stat_rx_pfc_paused             (                               )                                                                               ,
        .cfg_ifg                        (                               )                                                                               ,
        .cfg_tx_enable                  (                               )                                                                               ,
        .cfg_rx_enable                  (cfg_rx_enable                  )                                                                               ,
        .cfg_mcf_rx_eth_dst_mcast       (                               )                                                                               ,
        .cfg_mcf_rx_check_eth_dst_mcast (                               )                                                                               ,
        .cfg_mcf_rx_eth_dst_ucast       (                               )                                                                               ,
        .cfg_mcf_rx_check_eth_dst_ucast (                               )                                                                               ,
        .cfg_mcf_rx_eth_src             (                               )                                                                               ,
        .cfg_mcf_rx_check_eth_src       (                               )                                                                               ,
        .cfg_mcf_rx_eth_type            (                               )                                                                               ,
        .cfg_mcf_rx_opcode_lfc          (                               )                                                                               ,
        .cfg_mcf_rx_check_opcode_lfc    (                               )                                                                               ,
        .cfg_mcf_rx_opcode_pfc          (                               )                                                                               ,
        .cfg_mcf_rx_check_opcode_pfc    (                               )                                                                               ,
        .cfg_mcf_rx_forward             (                               )                                                                               ,
        .cfg_mcf_rx_enable              (                               )                                                                               ,
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
        .cfg_rx_lfc_opcode              (                               )                                                                               ,
        .cfg_rx_lfc_en                  (                               )                                                                               ,
        .cfg_rx_pfc_opcode              (                               )                                                                               ,
        .cfg_rx_pfc_en                  (                               )                                                                                
    )                                                                                                                                                   ;                                                                          
    
    
endmodule   
