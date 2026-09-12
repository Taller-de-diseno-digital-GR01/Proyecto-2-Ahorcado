// Harness de hardware para probar M02_Generador-Tono (src/design/generador_tono.sv) suelto en
// la Basys3, sin top.sv integrado. No es RTL del proyecto: es un arnes de prueba descartable,
// ver src/fpga/harness/CONVENCION.txt.
//
// Uso:
//   make -f Makefile.windows fpga-bitstream SYNTH_TOP=top_generador_tono FPGA_SRCS=" \
//     src/fpga/harness/top_generador_tono.sv \
//     src/design/generador_tono.sv src/design/botones.sv src/design/debounce.sv"
//   make -f Makefile.windows fpga-program SYNTH_TOP=top_generador_tono
//
// Control fisico (solo usa pines ya descomentados en basys3.xdc, no hace falta tocar el xdc):
//   sw[1:0] = 2'b00 -> btn_ok dispara el tono de FALLO   (grave,  250 Hz)
//   sw[1:0] = 2'b01 -> btn_ok dispara el tono de ACIERTO (agudo, 1000 Hz)
//   sw[1]   = 1     -> btn_ok dispara el tono de FIN      (medio,  500 Hz), sw[0] no importa
//   btn_sel sin uso en esta prueba.
//   rst     BTN_RST real de la tarjeta, silencia el buzzer.
//
// i_state se hardcodea en SELECCION (000) en reposo: solo se fuerza a GANO (011) durante el
// mismo ciclo en que btn_ok dispara con sw[1]=1, para ejercitar el propio detector de flanco de
// generador_tono.sv (dec_fin/pulso_fin, ver M02_Generador-Tono.md seccion h) en vez de
// saltarselo desde el harness.
module top_generador_tono (
    input  logic       clk,
    input  logic       rst,
    input  logic [1:0] sw,
    input  logic       btn_sel,
    input  logic       btn_ok,
    output logic       buzzer
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

    localparam logic [2:0] SELECCION = 3'b000;
    localparam logic [2:0] GANO      = 3'b011;

    localparam logic [1:0] FALLO   = 2'b00;
    localparam logic [1:0] ACIERTO = 2'b01;

    logic [2:0] i_state_hw;
    logic [1:0] i_letra_state_hw;
    logic       i_letra_lista_hw;

    // hardcodeo: en reposo "no pasa nada" (SELECCION/FALLO/sin pulso); el unico evento real que
    // entra desde hardware es btn_ok_pulse, y sw elige a cual de los tres tonos se traduce.
    assign i_state_hw       = (sw[1] && btn_ok_pulse) ? GANO : SELECCION;
    assign i_letra_state_hw = sw[0] ? ACIERTO : FALLO;
    assign i_letra_lista_hw = (!sw[1]) && btn_ok_pulse;

    generador_tono u_generador_tono (
        .clk          (clk),
        .rst          (rst),
        .i_state      (i_state_hw),
        .i_letra_state(i_letra_state_hw),
        .i_letra_lista(i_letra_lista_hw),
        .o_sound      (buzzer)
    );

endmodule
