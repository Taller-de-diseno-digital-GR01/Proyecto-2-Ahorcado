`timescale 1ns/1ps

// Testbench de fsm (M13_FSM). Corre con: make sim TB=fsm (o make wave TB=fsm)
//
// Nota de estilo, igual que en tb_mostrar_lcd.sv / tb_temporizador.sv: las comprobaciones se
// escriben como macros (`define), no como task/function, porque en Icarus Verilog una llamada
// a tarea/funcion dentro del bloque initial corrompe el siguiente @(posedge clk) del mismo
// proceso.
module tb_fsm;

  // Codificacion de state, igual que fsm.sv
  localparam logic [2:0] ST_SELECCION = 3'b000;
  localparam logic [2:0] ST_CARGA     = 3'b001;
  localparam logic [2:0] ST_JUEGO     = 3'b010;
  localparam logic [2:0] ST_GANO      = 3'b011;
  localparam logic [2:0] ST_PERDIO    = 3'b100;

  logic clk;
  logic rst;

  logic i_sel;
  logic i_ok;
  logic i_valid_word;
  logic i_palabra_completa;
  logic i_intentos_agotados;
  logic i_tiempo_agotado;
  logic i_fin_espera;

  logic [2:0] o_state;
  logic       o_modo;

  int errores = 0;

  fsm dut (
    .clk(clk),
    .rst(rst),
    .i_sel(i_sel),
    .i_ok(i_ok),
    .i_valid_word(i_valid_word),
    .i_palabra_completa(i_palabra_completa),
    .i_intentos_agotados(i_intentos_agotados),
    .i_tiempo_agotado(i_tiempo_agotado),
    .i_fin_espera(i_fin_espera),
    .o_state(o_state),
    .o_modo(o_modo)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Watchdog: corta la simulacion si algo se queda esperando una transicion que no llega.
  initial begin
    repeat (2000) @(posedge clk);
    $display("FALLO: WATCHDOG, la simulacion no termino a tiempo (posible deadlock)");
    errores = errores + 1;
    $finish;
  end

  // ------------------------------------------------------------------
  // Macros de comprobacion (ver nota de estilo arriba)
  // ------------------------------------------------------------------
  `define CHECK_STATE(nombre, expected) \
      if (o_state !== (expected)) begin \
          $display("FALLO [%0t ns] %s: se esperaba state=%0b, se obtuvo %0b", $time, nombre, (expected), o_state); \
          errores = errores + 1; \
      end else begin \
          $display("OK    [%0t ns] %s: state=%0b", $time, nombre, o_state); \
      end

  `define CHECK_MODO(nombre, expected) \
      if (o_modo !== (expected)) begin \
          $display("FALLO [%0t ns] %s: se esperaba modo=%0b, se obtuvo %0b", $time, nombre, (expected), o_modo); \
          errores = errores + 1; \
      end else begin \
          $display("OK    [%0t ns] %s: modo=%0b", $time, nombre, o_modo); \
      end

  // Baja todos los pulsos de entrada a 0, para no arrastrar un pulso de la prueba anterior.
  `define CLEAR_PULSOS \
      i_sel               = 1'b0; \
      i_ok                = 1'b0; \
      i_valid_word        = 1'b0; \
      i_palabra_completa  = 1'b0; \
      i_intentos_agotados = 1'b0; \
      i_tiempo_agotado    = 1'b0; \
      i_fin_espera        = 1'b0;

  initial begin
    $dumpfile("tb_fsm.vcd");
    $dumpvars(0, tb_fsm);

    rst = 1'b1;
    `CLEAR_PULSOS
    repeat (3) @(posedge clk);
    #1;
    `CHECK_STATE("reset: arranca en SELECCION", ST_SELECCION)
    `CHECK_MODO("reset: arranca en FACIL", 1'b0)

    rst = 1'b0;
    @(posedge clk); #1;

    // 1) i_sel conmuta el modo mientras se esta en SELECCION
    i_sel = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("sel: se mantiene en SELECCION", ST_SELECCION)
    `CHECK_MODO("sel: conmuta a DIFICIL", 1'b1)

    // 2) un segundo pulso de sel vuelve a FACIL
    i_sel = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_MODO("sel: conmuta de vuelta a FACIL", 1'b0)

    // 3) sel de nuevo a DIFICIL, y se confirma la eleccion con i_ok: pasa a CARGA
    i_sel = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    i_ok = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("ok: pasa a CARGA", ST_CARGA)
    `CHECK_MODO("ok: conserva DIFICIL elegido en SELECCION", 1'b1)

    // 4) en CARGA, i_sel ya no debe afectar el modo (queda congelado fuera de SELECCION)
    i_sel = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("CARGA: sel no cambia de estado", ST_CARGA)
    `CHECK_MODO("CARGA: modo congelado, ignora sel", 1'b1)

    // 5) i_valid_word: la palabra ya esta lista, pasa a JUEGO
    i_valid_word = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("valid_word: pasa a JUEGO", ST_JUEGO)

    // 6) en JUEGO, ni sel ni ok deben moverla mientras no haya un desenlace
    i_sel = 1'b1;
    i_ok  = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("JUEGO: sel/ok no la mueven", ST_JUEGO)

    // 7) i_palabra_completa: gana la partida
    i_palabra_completa = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("palabra_completa: pasa a GANO", ST_GANO)

    // 8) en GANO se espera i_fin_espera para volver a SELECCION
    @(posedge clk); #1;
    `CHECK_STATE("GANO: se mantiene sin fin_espera", ST_GANO)
    i_fin_espera = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("fin_espera: GANO vuelve a SELECCION", ST_SELECCION)
    `CHECK_MODO("vuelta a SELECCION: modo se conserva (DIFICIL)", 1'b1)

    // 9) repite el ciclo pero pierde por intentos agotados
    i_ok = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    i_valid_word = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("segundo ciclo: llega a JUEGO", ST_JUEGO)

    i_intentos_agotados = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("intentos_agotados: pasa a PERDIO", ST_PERDIO)

    i_fin_espera = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("fin_espera: PERDIO vuelve a SELECCION", ST_SELECCION)

    // 10) tercer ciclo, pierde por tiempo agotado (misma PERDIO, sin causa distinguible)
    i_ok = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    i_valid_word = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS

    i_tiempo_agotado = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("tiempo_agotado: tambien pasa a PERDIO", ST_PERDIO)

    i_fin_espera = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("fin_espera: PERDIO vuelve a SELECCION otra vez", ST_SELECCION)

    // 11) rst asincrono/sincrono desde cualquier estado vuelve a SELECCION y a modo FACIL
    i_ok = 1'b1;
    @(posedge clk); #1;
    `CLEAR_PULSOS
    `CHECK_STATE("antes del rst de en medio: en CARGA", ST_CARGA)
    rst = 1'b1;
    @(posedge clk); #1;
    rst = 1'b0;
    `CHECK_STATE("rst en medio de una partida: vuelve a SELECCION", ST_SELECCION)
    `CHECK_MODO("rst en medio de una partida: vuelve a FACIL", 1'b0)

    if (errores == 0)
        $display("\n=== TODAS LAS PRUEBAS PASARON ===");
    else
        $display("\n=== %0d PRUEBA(S) FALLARON ===", errores);

    $finish;
  end

endmodule
