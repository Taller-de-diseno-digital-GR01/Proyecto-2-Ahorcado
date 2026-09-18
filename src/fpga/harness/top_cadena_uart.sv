// Harness de hardware para probar la cadena UART completa (M10_Receptor-UART +
// M11_Transmisor-UART + ARBITRO_UART + PERIFERICO_UART) sobre el cable USB-serial real de la
// Basys3, junto con M07_Comparador-letra y M12_Contador-Intentos para que la evaluacion de
// letras sea real, no simulada a mano. No es RTL del proyecto: es un arnes de prueba
// descartable, ver src/fpga/harness/CONVENCION.txt.
//
// Uso:
//   make -f Makefile.windows fpga-bitstream SYNTH_TOP=top_cadena_uart FPGA_SRCS=" \
//     src/fpga/harness/top_cadena_uart.sv \
//     src/design/receptor_uart.sv src/design/transmisor_uart.sv src/design/arbitro_uart.sv \
//     src/design/periferico_uart.sv src/design/uart_rx.sv src/design/uart_tx.sv \
//     src/design/comparador_letra.sv src/design/contador_intentos.sv"
//   make -f Makefile.windows fpga-program SYNTH_TOP=top_cadena_uart
//
// Conectar por USB a una terminal serial (PuTTY, screen, etc.) a 115200 baudios, 8N1, sin
// control de flujo -- es el mismo puerto COM que usa Vivado para JTAG (el FTDI de la Basys3 es
// de dos canales).
//
// Palabra de prueba fija "GATO" (4 letras), en el formato de 5 bits/letra que espera
// comparador_letra (A=0..Z=25), no ASCII.
//
// Control fisico (solo usa pines ya descomentados en basys3.xdc, no hace falta tocar el xdc):
//   sw[2:0] hace de state_hw a mano, mismo codigo que M13_FSM: SELECCION=000, CARGA=001,
//           JUEGO=010, GANO=011, PERDIO=100
//     - pasar por CARGA reinicia comparador_letra (mascara/usadas) y contador_intentos
//     - entrar a JUEGO dispara la trama "I" (inicio) del transmisor
//     - entrar a GANO/PERDIO dispara la trama "F" (fin) del transmisor
//   rst     BTN_RST real de la tarjeta
//   Escribir una letra A-Z mayuscula desde la terminal estando en JUEGO: el receptor se la
//   entrega a comparador_letra, que evalua contra "GATO" y dispara la trama "L" (letra) de
//   vuelta por el mismo puerto -- deberia verse la respuesta en la terminal.
//
// LEDs de apoyo (la confirmacion real es lo que llega a la terminal; esto es solo para depurar
// sin mirarla):
//   LED[2]   o_intentos_agotados (M12)
//   LED[5:3] o_intentos[2:0] (M12)
//   LED[7:6] o_letra_state (M07): 00 fallo, 01 acierto, 10 repetida
//   LED[8]   o_palabra_completa (M07)
//   state_led[1:0] = sw[1:0], solo para confirmar que el switch se leyo
module top_cadena_uart (
    input  logic        clk,
    input  logic        rst,
    input  logic [2:0]  sw,

    input  logic         rx_i,
    output logic         tx_o,

    output logic [15:2] LED,
    output logic [1:0]  state_led
);

    logic [2:0] state_hw;
    assign state_hw = sw;
    assign state_led = sw[1:0];

    // Palabra de prueba fija "GATO", codigo de 5 bits por letra (A=0..Z=25), letra 0 en bits bajos
    localparam logic [59:0] PALABRA_PRUEBA = {
        5'd0, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,  // letras 11..4, relleno sin usar
        5'd14, 5'd19, 5'd0, 5'd6                          // letras 3..0: O T A G -> "GATO"
    };
    localparam logic [3:0] LARGO_PRUEBA = 4'd4;

    // --- Bus compartido: ARBITRO_UART entre receptor y transmisor, PERIFERICO_UART al fondo ---
    logic [1:0]  rx_addr;
    logic        rx_we;
    logic [31:0] rx_wdata;
    logic [31:0] rx_rdata;

    logic [1:0]  tx_addr;
    logic        tx_we;
    logic [31:0] tx_wdata;
    logic [31:0] tx_rdata;
    logic        bus_libre;

    logic [1:0]  per_addr;
    logic        per_we;
    logic [31:0] per_wdata;
    logic [31:0] per_rdata;

    arbitro_uart u_arbitro (
        .i_rx_addr (rx_addr), .i_rx_we (rx_we), .i_rx_wdata (rx_wdata), .o_rx_rdata (rx_rdata),
        .i_tx_addr (tx_addr), .i_tx_we (tx_we), .i_tx_wdata (tx_wdata), .o_tx_rdata (tx_rdata),
        .o_tx_bus_libre (bus_libre),
        .o_addr (per_addr), .o_we (per_we), .o_wdata (per_wdata), .i_rdata (per_rdata)
    );

    periferico_uart u_periferico (
        .clk_i (clk), .rst_i (rst),
        .write_enable_i (per_we), .addr_i (per_addr), .wdata_i (per_wdata), .rdata_o (per_rdata),
        .rx_i (rx_i), .tx_o (tx_o)
    );

    // --- M10_Receptor-UART: entrega letras a M07 ---
    logic [7:0] letra_in;
    logic       letra_nueva;

    receptor_uart u_receptor (
        .clk (clk), .rst (rst),
        .i_rdata (rx_rdata), .i_state (state_hw),
        .o_addr (rx_addr), .o_write_enable (rx_we), .o_wdata (rx_wdata),
        .o_letra (letra_in), .o_valid_w (letra_nueva)
    );

    // --- M07_Comparador-letra: evaluacion real contra la palabra de prueba ---
    logic [1:0]  letra_state;
    logic        letra_lista;
    logic        palabra_completa;
    logic [11:0] mascara;
    logic        try_pulse;

    comparador_letra u_comparador (
        .clk (clk), .rst (rst),
        .i_letra (letra_in), .i_letra_nueva (letra_nueva),
        .i_word (PALABRA_PRUEBA), .i_word_length (LARGO_PRUEBA), .i_state (state_hw),
        .o_letra_state (letra_state), .o_letra_lista (letra_lista),
        .o_palabra_completa (palabra_completa), .o_mascara (mascara), .o_try (try_pulse)
    );

    // --- M12_Contador-Intentos ---
    logic [2:0] intentos;
    logic       intentos_agotados;

    contador_intentos u_contador (
        .clk (clk), .rst (rst),
        .i_try (try_pulse), .i_state (state_hw),
        .o_intentos (intentos), .o_intentos_agotados (intentos_agotados)
    );

    // --- M11_Transmisor-UART: manda tramas I/L/F segun los eventos de arriba ---
    transmisor_uart u_transmisor (
        .clk (clk), .rst (rst),
        .i_state (state_hw), .i_modo (1'b0),
        .i_letra_state (letra_state), .i_letra_lista (letra_lista),
        .i_intentos (intentos), .i_word_length (LARGO_PRUEBA), .i_mascara (mascara),
        .i_rdata (tx_rdata), .i_bus_libre (bus_libre),
        .o_write_enable (tx_we), .o_addr (tx_addr), .o_wdata (tx_wdata)
    );

    assign LED[2]    = intentos_agotados;
    assign LED[5:3]  = intentos;
    assign LED[7:6]  = letra_state;
    assign LED[8]    = palabra_completa;
    assign LED[15:9] = '0;

endmodule
