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

  initial begin
    $dumpfile("tb_contador_intentos.vcd");
    $dumpvars(0, tb_contador_intentos);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_try_tb = 1'b0;
    i_state_tb = JUEGO;

    ciclo();
    rst_tb = 1'b0;
    repeat (4) ciclo();

    $finish;
  end

endmodule
