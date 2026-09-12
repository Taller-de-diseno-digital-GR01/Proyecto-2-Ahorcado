// Harness de hardware para probar M03_Temporizador (src/design/temporizador.sv), mostrando la
// cuenta regresiva real en el display de 7 segmentos de M01_Marcador (src/design/marcador.sv), y
// de paso M05_Estado (src/design/Estado.sv) para el LED de estado, suelto en la Basys3, sin
// top.sv integrado. No es RTL del proyecto: es un arnes de prueba descartable, ver
// src/fpga/harness/CONVENCION.txt.
//
// Uso:
//   make -f Makefile.windows fpga-bitstream SYNTH_TOP=top_temporizador FPGA_SRCS=" \
//     src/fpga/harness/top_temporizador.sv \
//     src/design/temporizador.sv src/design/marcador.sv src/design/Estado.sv \
//     src/design/botones.sv src/design/debounce.sv"
//   make -f Makefile.windows fpga-program SYNTH_TOP=top_temporizador
//
// state_hw es un mini remedo de fsm.sv, solo con las transiciones que le importan a esta
// prueba: SELECCION -> JUEGO por boton, y JUEGO -> PERDIO -> SELECCION automatico, siguiendo
// tiempo_agotado y o_fin_espera reales de temporizador.sv, igual que haria la fsm de verdad.
//
// Control fisico (solo usa pines ya descomentados en basys3.xdc, no hace falta tocar el xdc):
//   sw[0]   = modo (0 = facil 60 s, 1 = dificil 45 s), leido en continuo por temporizador.sv
//   btn_ok  desde SELECCION, dispara un pulso que fuerza state_hw a JUEGO, temporizador.sv
//           detecta ese flanco y arranca la cuenta regresiva con el tiempo inicial segun sw[0]
//   btn_sel desde JUEGO, aborta manualmente de vuelta a SELECCION (no forma parte del flujo
//           automatico, es solo para no depender de rst si se quiere cortar una prueba a medias)
//   rst     BTN_RST real de la tarjeta, reinicia todo a SELECCION con tiempo en 0
//
// Al llegar la cuenta a 0, state_hw pasa solo a PERDIO (tiempo_agotado); 3 s despues
// (o_fin_espera) vuelve solo a SELECCION, sin necesidad de botones -- exactamente lo que haria
// la FSM real del sistema completo.
//
// Display de 7 segmentos (marcador.sv): AN2/AN3 muestran el tiempo restante real (BCD directo
// de temporizador.sv), AN0/AN1 fijos en 00 (num_ganadas no entra en esta prueba)
//   state_led[1:0] = salida real de M05_Estado sobre state_hw (00 seleccion, 01 carga/juego,
//     10 resultado) -- la ventana de "10" dura los 3 s completos de o_fin_espera
//   LED[2] = tiempo_agotado de M03_Temporizador, se enciende al llegar la cuenta a 0 y se
//     mantiene hasta el siguiente arranque (btn_ok), igual que documenta M03_Temporizador.md
module top_temporizador (
    input  logic       clk,
    input  logic       rst,
    input  logic [0:0] sw,
    input  logic       btn_sel,
    input  logic       btn_ok,

    output logic [6:0] seg,
    output logic [3:0] an,
    output logic       dp,
    output logic [1:0] state_led,
    output logic [2:2] LED
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
    localparam logic [2:0] JUEGO     = 3'b010;
    localparam logic [2:0] PERDIO    = 3'b100;

    logic [7:0] tiempo_bcd;
    logic       tiempo_agotado;
    logic       fin_espera;

    // state_hw: mini remedo de fsm.sv, ver comentario de arriba
    logic [2:0] state_hw;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_hw <= SELECCION;
        end else begin
            case (state_hw)
                SELECCION: if (btn_ok_pulse)   state_hw <= JUEGO;
                JUEGO:     if (tiempo_agotado) state_hw <= PERDIO;
                           else if (btn_sel_pulse) state_hw <= SELECCION;
                PERDIO:    if (fin_espera)     state_hw <= SELECCION;
                default:   state_hw <= SELECCION;
            endcase
        end
    end

    temporizador u_temporizador (
        .clk           (clk),
        .rst           (rst),
        .i_state       (state_hw),
        .modo          (sw[0]),
        .tiempo        (tiempo_bcd),
        .tiempo_agotado(tiempo_agotado),
        .o_fin_espera  (fin_espera)
    );

    marcador u_marcador (
        .clk        (clk),
        .rst        (rst),
        .time_value (tiempo_bcd),
        .num_ganadas(7'd0),
        .seg        (seg),
        .an         (an),
        .dp         (dp)
    );

    Estado u_estado (
        .clk      (clk),
        .rst      (rst),
        .state    (state_hw),
        .state_led(state_led)
    );

    assign LED[2] = tiempo_agotado;

endmodule
