// Harness de hardware para probar M04_Mostrar-LCD (src/design/mostrar_lcd.sv) junto con
// PERIFERICO_LCD (src/design/periferico_lcd.sv) sobre el PmodCLP real, suelto en la Basys3, sin
// top.sv integrado. No es RTL del proyecto: es un arnes de prueba descartable, ver
// src/fpga/harness/CONVENCION.txt.
//
// Uso:
//   make -f Makefile.windows fpga-bitstream SYNTH_TOP=top_mostrar_lcd FPGA_SRCS=" \
//     src/fpga/harness/top_mostrar_lcd.sv \
//     src/design/mostrar_lcd.sv src/design/periferico_lcd.sv \
//     src/design/botones.sv src/design/debounce.sv"
//   make -f Makefile.windows fpga-program SYNTH_TOP=top_mostrar_lcd
//
// Control fisico (solo usa pines ya descomentados en basys3.xdc, no hace falta tocar el xdc):
//   sw[2:0] elige state_hw, mismo codigo que M13_FSM: SELECCION=000, CARGA=001, JUEGO=010,
//           GANO=011, PERDIO=100
//   btn_sel alterna modo_reg (FACIL/DIFICIL) y reinicia mascara_reg, como si fuera M09+M13_FSM
//   btn_ok  revela la siguiente letra de la palabra de prueba (corre mascara_reg de a un bit),
//           como si fuera M07_Comparador-letra acertando letras en orden
//   rst     BTN_RST real de la tarjeta
module top_mostrar_lcd (
    input  logic       clk,
    input  logic       rst,
    input  logic [2:0] sw,
    input  logic       btn_sel,
    input  logic       btn_ok,

    output logic       lcd_rs_o,
    output logic       lcd_rw_o,
    output logic       lcd_e_o,
    output logic [7:0] lcd_data_o
);

    logic btn_ok_pulse, btn_sel_pulse;

    botones u_botones (
        .clk          (clk),
        .rst          (rst),
        .btn_ok       (btn_ok),
        .btn_sel      (btn_sel),
        .btn_ok_pulse (btn_ok_pulse),
        .btn_sel_pulse(btn_sel_pulse)
    );

    // state_hw ahora lo eligen los switches directo, mismo codigo que M13_FSM
    logic [2:0] state_hw;
    assign state_hw = sw;

    // Palabra de prueba fija "AHORCADO" (8 letras), empacada letra 0 en los bits bajos
    localparam logic [95:0] PALABRA_PRUEBA = {
        8'(" "), 8'(" "), 8'(" "), 8'(" "),  // letras 11..8, relleno sin usar
        8'("O"), 8'("D"), 8'("A"), 8'("C"),  // letras 7..4: O D A C
        8'("R"), 8'("O"), 8'("H"), 8'("A")   // letras 3..0: R O H A
    };
    localparam logic [3:0] LARGO_PRUEBA = 4'd8;

    logic        modo_reg;
    logic [11:0] mascara_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            modo_reg    <= 1'b0;
            mascara_reg <= 12'b0;
        end else if (btn_sel_pulse) begin
            modo_reg    <= ~modo_reg;
            mascara_reg <= 12'b0;
        end else if (btn_ok_pulse && mascara_reg != 12'h0FF) begin
            mascara_reg <= (mascara_reg << 1) | 12'b1;
        end
    end

    logic [1:0]  bus_addr;
    logic        bus_we;
    logic [31:0] bus_wdata;
    logic [31:0] bus_rdata;

    mostrar_lcd u_mostrar_lcd (
        .clk           (clk),
        .rst           (rst),
        .i_state       (state_hw),
        .i_modo        (modo_reg),
        .i_word        (PALABRA_PRUEBA),
        .i_word_length (LARGO_PRUEBA),
        .i_mascara     (mascara_reg),
        .i_rdata       (bus_rdata),
        .o_addr        (bus_addr),
        .o_write_enable(bus_we),
        .o_wdata       (bus_wdata)
    );

    periferico_lcd u_periferico_lcd (
        .clk_i         (clk),
        .rst_i         (rst),
        .write_enable_i(bus_we),
        .addr_i        (bus_addr),
        .wdata_i       (bus_wdata),
        .rdata_o       (bus_rdata),
        .lcd_rs_o      (lcd_rs_o),
        .lcd_rw_o      (lcd_rw_o),
        .lcd_e_o       (lcd_e_o),
        .lcd_data_o    (lcd_data_o)
    );

endmodule
