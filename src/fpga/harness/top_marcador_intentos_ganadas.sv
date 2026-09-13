// Harness de hardware para probar M01_Marcador (src/design/marcador.sv) junto con
// M12_Contador-Intentos (src/design/contador_intentos.sv) y M06_Ganadas (src/design/Ganadas.sv)
// suelto en la Basys3, sin top.sv integrado. No es RTL del proyecto: es un arnes de prueba
// descartable, ver src/fpga/harness/CONVENCION.txt.
//
// Uso:
//   make -f Makefile.windows fpga-bitstream SYNTH_TOP=top_marcador_intentos_ganadas FPGA_SRCS=" \
//     src/fpga/harness/top_marcador_intentos_ganadas.sv \
//     src/design/marcador.sv src/design/contador_intentos.sv src/design/Ganadas.sv \
//     src/design/botones.sv src/design/debounce.sv"
//   make -f Makefile.windows fpga-program SYNTH_TOP=top_marcador_intentos_ganadas
//
// Control fisico (solo usa pines ya descomentados en basys3.xdc, no hace falta tocar el xdc):
//   sw[2:0] hace de state[2:0] a mano, no hay fsm real en este arnes
//     001 CARGA   reinicia contador_intentos a 0 (M06_Ganadas lo ignora, solo le importa GANO)
//     011 GANO    la entrada a este estado desde otro distinto suma una partida ganada
//     el resto de codigos no tiene efecto especial para estos dos modulos
//   btn_ok  dispara un pulso de i_try hacia contador_intentos, como si una letra hubiera fallado
//   btn_sel sin uso en esta prueba
//   rst     BTN_RST real de la tarjeta, reinicia los tres modulos a la vez
//
// Display de 7 segmentos de marcador.sv, reusando su bus time_value (BCD) para mostrar los
// intentos en vez del tiempo real de M03_Temporizador ya que ese modulo no entra en esta
// prueba -- o_intentos nunca pasa de un digito (0-6), asi que su binario ya es identico a su
// BCD, se empaca directo en el nibble de unidades sin necesitar conversion:
//   AN0/AN1 unidades/decenas de num_ganadas real, sale de M06_Ganadas
//   AN2/AN3 unidades/decenas de o_intentos real, sale de M12_Contador-Intentos
//   state_led[0] = o_intentos_agotados de M12_Contador-Intentos, se enciende al llegar a 6 fallos
//   state_led[1] sin uso en esta prueba, fijo en 0
module top_marcador_intentos_ganadas (
    input  logic       clk,
    input  logic       rst,
    input  logic [2:0] sw,
    input  logic       btn_sel,
    input  logic       btn_ok,

    output logic [6:0] seg,
    output logic [3:0] an,
    output logic       dp,
    output logic [1:0] state_led
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

    // state[2:0] a mano desde los switches, no hay fsm real en este arnes
    logic [2:0] state_hw;
    assign state_hw = sw;

    logic [2:0] intentos;
    logic       intentos_agotados;

    contador_intentos u_contador_intentos (
        .clk                (clk),
        .rst                (rst),
        .i_try              (btn_ok_pulse),
        .i_state            (state_hw),
        .o_intentos         (intentos),
        .o_intentos_agotados(intentos_agotados)
    );

    logic [6:0] num_ganadas;

    M06_Ganadas u_ganadas (
        .clk        (clk),
        .rst        (rst),
        .state      (state_hw),
        .num_ganadas(num_ganadas)
    );

    marcador u_marcador (
        .clk        (clk),
        .rst        (rst),
        .time_value ({4'b0, 1'b0, intentos}),
        .num_ganadas(num_ganadas),
        .seg        (seg),
        .an         (an),
        .dp         (dp)
    );

    assign state_led = {1'b0, intentos_agotados};

endmodule
