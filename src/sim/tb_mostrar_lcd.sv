`timescale 1ns/1ps

// Testbench de mostrar_lcd. Corre con: make sim TB=mostrar_lcd (o make wave TB=mostrar_lcd)
//
// M13_FSM y PERIFERICO_LCD todavia no existen como .sv en el repo (solo en los documentos de
// diseño), asi que este testbench hace de las dos cosas a la vez: maneja i_state/i_modo como si
// fuera la FSM principal, y modela PERIFERICO_LCD con un stub de comportamiento (registro de
// pantalla de 16 caracteres + temporizador de busy/done) para poder verificar en simulacion que
// mostrar_lcd arma y manda los mensajes correctos, no solo que compila.
//
// El stub es deliberadamente permisivo con el hueco ya documentado en
// docs/diseño/modulos/M04_Mostrar-LCD.md h): HOME pasa a SEND sin esperar el done del propio
// home/clear. Si un PERIFERICO_LCD real tarda mas en ese comando que en una escritura normal,
// el primer byte del mensaje podria perderse ahi; este stub solo lo señala con un $display, no
// lo hace fallar, porque arreglarlo es un cambio de la tabla de estados documentada, no de este
// testbench (ver el aviso en la respuesta que acompaña este archivo).
//
// Nota de estilo, igual que en tb_temporizador.sv: las comprobaciones se escriben como macros
// (`define), no como task/function, porque en Icarus Verilog una llamada a tarea/funcion dentro
// del bloque initial corrompe el siguiente @(posedge clk) del mismo proceso.
module tb_mostrar_lcd;

  // Codificacion de state, igual que M13_FSM y que mostrar_lcd.sv
  localparam logic [2:0] ST_SELECCION       = 3'b000;
  localparam logic [2:0] ST_CARGA           = 3'b001;
  localparam logic [2:0] ST_JUEGO           = 3'b010;
  localparam logic [2:0] ST_GANO            = 3'b011;
  localparam logic [2:0] ST_PERDIO_INTENTOS = 3'b100;
  localparam logic [2:0] ST_PERDIO_TIEMPO   = 3'b101;

  // Codificacion de la FSM interna de mostrar_lcd, para poder esperar por hierarchical ref
  // (dut.estado), igual que tb_temporizador.sv usa dut.running.
  localparam logic [1:0] IDLE_ENC = 2'b00;
  localparam logic [1:0] HOME_ENC = 2'b01;
  localparam logic [1:0] SEND_ENC = 2'b10;
  localparam logic [1:0] WAIT_ENC = 2'b11;

  // Direcciones y bits del bus, deben coincidir con los localparam de mostrar_lcd.sv: este
  // stub hace las veces de PERIFERICO_LCD, asi que tiene que hablar el mismo contrato de bus.
  localparam logic [1:0] ADDR_CTRL_ESTADO = 2'b00;
  localparam logic [1:0] ADDR_DATOS       = 2'b01;
  localparam BIT_START = 0;
  localparam BIT_RS    = 1;
  localparam BIT_CLEAR = 2;
  localparam BIT_HOME  = 3;
  localparam BIT_BUSY  = 8;
  localparam BIT_DONE  = 9;

  localparam int BUSY_CYCLES_DATO = 2; // ciclos de "busy" simulados para start/rs
  localparam int BUSY_CYCLES_HOME = 4; // ciclos de "busy" simulados para clear/home (mas largo en HW real)

  logic clk;
  logic rst;

  logic [2:0]  i_state;
  logic        i_modo;
  logic [7:0]  i_word [0:11];
  logic [3:0]  i_word_length;
  logic [11:0] i_mascara;
  logic [31:0] i_rdata;

  logic [1:0]  o_addr;
  logic        o_write_enable;
  logic [31:0] o_wdata;

  int errores = 0;

  mostrar_lcd dut (
    .clk(clk),
    .rst(rst),
    .i_state(i_state),
    .i_modo(i_modo),
    .i_word(i_word),
    .i_word_length(i_word_length),
    .i_mascara(i_mascara),
    .i_rdata(i_rdata),
    .o_addr(o_addr),
    .o_write_enable(o_write_enable),
    .o_wdata(o_wdata)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ------------------------------------------------------------------
  // Stub de PERIFERICO_LCD: registro de pantalla de 16 caracteres, cursor que auto-incrementa
  // con cada byte de datos (como el DDRAM del HD44780 en modo de incremento), y un temporizador
  // que retrasa "done" unos ciclos para forzar a mostrar_lcd a sondear WAIT de verdad, no solo
  // ver done=1 de inmediato.
  // ------------------------------------------------------------------
  logic [7:0] screen [0:15];
  logic [3:0] cursor;
  logic [7:0] pending_byte;
  logic       busy, done;
  logic       timer_activo;
  int         timer;

  assign i_rdata = {22'b0, done, busy, 8'b0};

  always_ff @(posedge clk) begin
    if (rst) begin
      cursor       <= 4'd0;
      pending_byte <= 8'h00;
      busy         <= 1'b0;
      done         <= 1'b0;
      timer_activo <= 1'b0;
      for (int i = 0; i < 16; i = i + 1) screen[i] <= " ";
    end
    else begin
      done <= 1'b0; // done es un pulso de un ciclo

      if (timer_activo) begin
        if (timer == 0) begin
          busy         <= 1'b0;
          done         <= 1'b1;
          timer_activo <= 1'b0;
        end
        else timer <= timer - 1;
        // Aviso (no falla la prueba) del hueco documentado: HOME->SEND sin esperar done propio
        if (o_write_enable)
          $display("NOTA  [%0t ns] el stub seguia \"busy\" (home/clear o dato anterior) cuando mostrar_lcd ya escribio de nuevo (addr=%0d)", $time, o_addr);
      end
      else if (o_write_enable && o_addr == ADDR_CTRL_ESTADO && (o_wdata[BIT_CLEAR] || o_wdata[BIT_HOME])) begin
        for (int i = 0; i < 16; i = i + 1) screen[i] <= " ";
        cursor       <= 4'd0;
        busy         <= 1'b1;
        timer        <= BUSY_CYCLES_HOME;
        timer_activo <= 1'b1;
      end
      else if (o_write_enable && o_addr == ADDR_CTRL_ESTADO && o_wdata[BIT_START]) begin
        if (o_wdata[BIT_RS]) begin // dato: se escribe en la pantalla y el cursor avanza
          screen[cursor] <= pending_byte;
          cursor         <= cursor + 4'd1;
        end
        busy         <= 1'b1;
        timer        <= BUSY_CYCLES_DATO;
        timer_activo <= 1'b1;
      end
      else if (o_write_enable && o_addr == ADDR_DATOS) begin
        pending_byte <= o_wdata[7:0];
      end
    end
  end

  // Watchdog: si algo se queda esperando una transicion que no llega (p.ej. un "wait" mal
  // planteado, como el que causo el cuelgue original de este archivo), corta la simulacion en
  // vez de dejarla correr para siempre. 20000 ciclos de sobra para las 11 pruebas de abajo.
  initial begin
    repeat (20000) @(posedge clk);
    $display("FALLO: WATCHDOG, la simulacion no termino a tiempo (posible deadlock)");
    errores = errores + 1;
    $finish;
  end

  // ------------------------------------------------------------------
  // Macros de comprobacion (ver nota de estilo arriba)
  // ------------------------------------------------------------------
  `define CHECK_BIT(nombre, got, expected) \
      if ((got) !== (expected)) begin \
          $display("FALLO [%0t ns] %s: se esperaba %0b, se obtuvo %0b", $time, nombre, (expected), (got)); \
          errores = errores + 1; \
      end else begin \
          $display("OK    [%0t ns] %s: %0b", $time, nombre, (got)); \
      end

  // Compara screen[0..len-1] contra texto (literal de Verilog) y screen[len..15] contra espacios
  `define CHECK_SCREEN(nombre, texto, len) \
      begin \
          logic [8*(len)-1:0] __ref; \
          string __got; \
          logic  __ok; \
          __ref = texto; \
          __got = ""; \
          __ok  = 1'b1; \
          for (int __i = 0; __i < 16; __i = __i + 1) begin \
              __got = {__got, string'(screen[__i])}; \
              if (__i < (len)) begin \
                  if (screen[__i] !== __ref[8*((len)-1-__i) +: 8]) __ok = 1'b0; \
              end else begin \
                  if (screen[__i] !== " ") __ok = 1'b0; \
              end \
          end \
          if (__ok) $display("OK    [%0t ns] %s: pantalla=\"%s\"", $time, nombre, __got); \
          else begin \
              $display("FALLO [%0t ns] %s: pantalla=\"%s\", se esperaba \"%s\" (relleno con espacios)", $time, nombre, __got, texto); \
              errores = errores + 1; \
          end \
      end

  // Espera lo suficiente para que termine cualquier redibujado pendiente. No cazamos el flanco
  // IDLE->HOME con "wait": mostrar_lcd puede arrancar su redibujado en el mismo ciclo en que se
  // suelta rst (no espera ningun pulso externo), asi que un "wait(dut.estado==HOME_ENC)" puede
  // arrancar despues de que esa transicion ya paso, y quedarse esperando para siempre una que no
  // vuelve a ocurrir. El peor caso real (mensaje de 16 caracteres, con el primer byte pisado por
  // el propio home/clear, ver el aviso de mas arriba) tarda del orden de 100 ciclos; 150 de
  // margen alcanza siempre.
  `define WAIT_REDIBUJADO repeat (150) @(posedge clk); #1;

  initial begin
    $dumpfile("tb_mostrar_lcd.vcd");
    $dumpvars(0, tb_mostrar_lcd);

    rst           = 1'b1;
    i_state       = ST_SELECCION;
    i_modo        = 1'b0;
    i_mascara     = 12'b0;
    i_word_length = 4'd0;
    for (int k = 0; k < 12; k = k + 1) i_word[k] = " ";
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // No hay una comprobacion de "sigue en IDLE justo despues del reset": el redibujado arranca
    // solo, sin ningun pulso "show" externo (la sola diferencia entre state/modo actuales y la
    // foto activa, que arranca invalida a proposito, ya dispara el primer redibujado), y puede
    // arrancar en el mismo ciclo en que se suelta rst. Lo que importa es el resultado.
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("seleccion FACIL", "MODO: FACIL", 11)

    // 2) sel conmuta el modo (M09/M13_FSM ya resuelto): M04 lo ve como un cambio de modo y
    //    redibuja solo, sin que nadie se lo ordene.
    i_modo = 1'b1;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("seleccion DIFICIL", "MODO: DIFICIL", 13)

    // 3) CARGA no tiene pantalla propia: no debe disparar redibujado ni tocar el bus
    i_state = ST_CARGA;
    repeat (5) @(posedge clk);
    `CHECK_BIT("CARGA: no dispara redibujado", dut.estado, IDLE_ENC)
    `CHECK_SCREEN("CARGA: la pantalla se mantiene (DIFICIL)", "MODO: DIFICIL", 13)

    // 4) Entra a JUEGO con la palabra "GATO", nada revelado todavia (mascara = 0, como la deja
    //    M07_Comparador-letra recien limpiada en CARGA)
    i_word[0] = "G"; i_word[1] = "A"; i_word[2] = "T"; i_word[3] = "O";
    i_word_length = 4'd4;
    i_mascara     = 12'b0000_0000_0000;
    i_state       = ST_JUEGO;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("juego: nada revelado", "____", 4)

    // 5) M07 revela la G (posicion 0): mascara cambia, M04 redibuja solo
    i_mascara = 12'b0000_0000_0001;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("juego: G revelada", "G___", 4)

    // 6) Se revela tambien la T (posicion 2), sin perder la G ya pintada
    i_mascara = 12'b0000_0000_0101;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("juego: G y T reveladas", "G_T_", 4)

    // 7) Se revela la A: dispara un nuevo redibujado ("GAT_"). A medio camino de ESE redibujado
    //    se revela tambien la O (palabra completa). Verifica que "cambio" se mantenga en 1
    //    durante toda la rafaga en curso y que, al volver a IDLE, arranque sola una segunda
    //    rafaga con el contenido mas reciente -- sin quedar nunca una pantalla a medias.
    i_mascara = 12'b0000_0000_0111; // + A revelada, dispara el redibujado que arranca con "GAT_"
    wait (dut.estado == HOME_ENC);  // confirma que arranco esa primera rafaga
    i_mascara = 12'b0000_0000_1111; // + O revelada, a medio camino de la rafaga que ya arranco
    wait (dut.estado == IDLE_ENC);  // termina esa primera rafaga (arrancada con la foto "GAT_")
    @(posedge clk);                 // deja que "cambio" se evalue con la mascara mas nueva
    wait (dut.estado == HOME_ENC);  // arranca sola una segunda rafaga
    wait (dut.estado == IDLE_ENC);
    #1;
    `CHECK_SCREEN("juego: redibujado se actualiza aunque cambie a medio envio", "GATO", 4)

    // 8) Resultado: GANO
    i_state = ST_GANO;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("resultado: gano", "GANASTE", 7)

    // 9) Resultado: PERDIO_INTENTOS
    i_state = ST_PERDIO_INTENTOS;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("resultado: perdio por intentos", "PERDISTE: LETRAS", 16)

    // 10) Resultado: PERDIO_TIEMPO
    i_state = ST_PERDIO_TIEMPO;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("resultado: perdio por tiempo", "PERDISTE: TIEMPO", 16)

    // 11) fin_espera: la FSM vuelve sola a SELECCION para la siguiente partida
    i_state = ST_SELECCION;
    i_modo  = 1'b0;
    `WAIT_REDIBUJADO
    `CHECK_SCREEN("vuelta a seleccion FACIL", "MODO: FACIL", 11)

    if (errores == 0)
        $display("\n=== TODAS LAS PRUEBAS PASARON ===");
    else
        $display("\n=== %0d PRUEBA(S) FALLARON ===", errores);

    $finish;
  end

endmodule
