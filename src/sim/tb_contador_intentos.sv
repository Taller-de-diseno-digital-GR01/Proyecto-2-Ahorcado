`timescale 1ns/1ps

module tb_contador_intentos;

  localparam MAX_INTENTOS = 6;
  localparam ANCHO = $clog2(MAX_INTENTOS+1);

  // el dut solo decodifica CARGA, JUEGO es cualquier otro estado que no lo limpie
  localparam logic [2:0] CARGA = 3'b001;
  localparam logic [2:0] JUEGO = 3'b010;

  logic clk_tb;
  logic rst_tb;
  logic i_try_tb;
  logic [2:0] i_state_tb;
  logic [ANCHO-1:0] o_intentos_tb;
  logic o_intentos_agotados_tb;

  int pruebas = 0;
  int errores = 0;

  contador_intentos #(.MAX_INTENTOS(MAX_INTENTOS)) dut (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_try(i_try_tb),
    .i_state(i_state_tb),
    .o_intentos(o_intentos_tb),
    .o_intentos_agotados(o_intentos_agotados_tb)
  );

  always #5 clk_tb = ~clk_tb;

  // el #1 despues del flanco deja que las salidas se asienten antes de mirarlas
  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  task automatic chequear(input string nombre,
                          input logic [ANCHO-1:0] esperado_intentos,
                          input logic esperado_agotados);
    pruebas++;
    if (o_intentos_tb === esperado_intentos && o_intentos_agotados_tb === esperado_agotados) begin
      $display("  ok     %s", nombre);
    end
    else begin
      errores++;
      $display("  FALLO  %s", nombre);
      $display("         o_intentos esperaba %0d y dio %0d, o_intentos_agotados esperaba %0b y dio %0b",
               esperado_intentos, o_intentos_tb, esperado_agotados, o_intentos_agotados_tb);
    end
  endtask

  initial begin
    $dumpfile("tb_contador_intentos.vcd");
    $dumpvars(0, tb_contador_intentos);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_try_tb = 1'b0;
    i_state_tb = JUEGO;

    $display("== tb_contador_intentos, MAX_INTENTOS=%0d ==", MAX_INTENTOS);

    ciclo();
    chequear("el reset deja la cuenta en cero", 0, 1'b0);
    rst_tb = 1'b0;

    repeat (4) ciclo();
    chequear("sin pulsos de fallo la cuenta no se mueve", 0, 1'b0);

    for (int n = 1; n <= MAX_INTENTOS; n++) begin
      i_try_tb = 1'b1;
      ciclo();
      i_try_tb = 1'b0;
      chequear($sformatf("fallo %0d de %0d", n, MAX_INTENTOS), n[ANCHO-1:0], (n == MAX_INTENTOS));
    end

    repeat (3) begin
      i_try_tb = 1'b1;
      ciclo();
      i_try_tb = 1'b0;
    end
    chequear("tres fallos de mas no le dan la vuelta a la cuenta", MAX_INTENTOS, 1'b1);

    i_state_tb = CARGA;
    ciclo();
    i_state_tb = JUEGO;
    chequear("CARGA limpia la cuenta de la partida anterior", 0, 1'b0);

    i_try_tb = 1'b1;
    ciclo();
    ciclo();
    i_try_tb = 1'b0;
    chequear("dos fallos seguidos en la partida nueva", 2, 1'b0);

    rst_tb = 1'b1;
    i_try_tb = 1'b1;
    ciclo();
    rst_tb = 1'b0;
    i_try_tb = 1'b0;
    chequear("el rst gana aunque llegue un try en el mismo ciclo", 0, 1'b0);

    i_try_tb = 1'b1;
    ciclo();
    i_try_tb = 1'b0;
    chequear("un fallo suelto despues del rst", 1, 1'b0);

    i_state_tb = CARGA;
    i_try_tb = 1'b1;
    ciclo();
    i_state_tb = JUEGO;
    i_try_tb = 1'b0;
    chequear("CARGA gana aunque llegue un try en el mismo ciclo", 0, 1'b0);

    $display("== %0d pruebas, %0d fallos ==", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_contador_intentos termino con fallos");
    $finish;
  end

endmodule
