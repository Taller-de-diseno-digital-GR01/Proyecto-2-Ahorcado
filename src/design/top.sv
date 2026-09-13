
module top (
    input  logic       clk,
    input  logic       rst,
    input  logic       btn_sel,
    input  logic       btn_ok,
    //UART
    input  logic       rx_i,

    output logic       tx_o,
    //LCD
    output logic        lcd_rs_o,
    output logic        lcd_rw_o,
    output logic        lcd_e_o,
    output logic [7:0]  lcd_data_o,

    //7 segmentos
    output logic [6:0]  seg,
    output logic [3:0]  an,
    output logic        dp,

    //LEDs
    output logic [1:0]  state_led,
    output logic        buzzer
);

endmodule
