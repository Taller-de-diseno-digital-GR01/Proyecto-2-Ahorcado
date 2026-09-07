`timescale 1ns/1ps

module tb_comparador_letra;

  localparam WORD_MAXLEN = 12;
  localparam LETRA_WIDTH = 5;
  localparam LARGO_WIDTH = $clog2(WORD_MAXLEN+1);

  // el dut solo decodifica CARGA, JUEGO es cualquier otro estado que no recargue la palabra
  localparam logic [2:0] CARGA = 3'b001;
  localparam logic [2:0] JUEGO = 3'b010;

  localparam logic [1:0] FALLO = 2'b00;
  localparam logic [1:0] ACIERTO = 2'b01;
  localparam logic [1:0] REPETIDA = 2'b10;

  logic clk_tb;
  logic rst_tb;
  logic [7:0] i_letra_tb;
  logic i_letra_nueva_tb;
  logic [WORD_MAXLEN*LETRA_WIDTH-1:0] i_word_tb;
  logic [LARGO_WIDTH-1:0] i_word_length_tb;
  logic [2:0] i_state_tb;
  logic [1:0] o_letra_state_tb;
  logic o_letra_lista_tb;
  logic o_palabra_completa_tb;
  logic [WORD_MAXLEN-1:0] o_mascara_tb;
  logic o_try_tb;

  comparador_letra #(.WORD_MAXLEN(WORD_MAXLEN), .LETRA_WIDTH(LETRA_WIDTH)) dut (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_letra(i_letra_tb),
    .i_letra_nueva(i_letra_nueva_tb),
    .i_word(i_word_tb),
    .i_word_length(i_word_length_tb),
    .i_state(i_state_tb),
    .o_letra_state(o_letra_state_tb),
    .o_letra_lista(o_letra_lista_tb),
    .o_palabra_completa(o_palabra_completa_tb),
    .o_mascara(o_mascara_tb),
    .o_try(o_try_tb)
  );

  always #5 clk_tb = ~clk_tb;

  // el #1 despues del flanco deja que las salidas se asienten antes de mirarlas
  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  // letra 1 en los bits bajos, igual que como lo va a entregar el banco de palabras
  function automatic logic [WORD_MAXLEN*LETRA_WIDTH-1:0] empacar(input string palabra);
    empacar = '0;
    for (int i = 0; i < palabra.len(); i++)
      empacar[i*LETRA_WIDTH +: LETRA_WIDTH] = palabra[i] - 8'h41;
  endfunction

  task automatic cargar(input string palabra);
    i_word_tb = empacar(palabra);
    i_word_length_tb = palabra.len();
    i_state_tb = CARGA;
    ciclo();
    i_state_tb = JUEGO;
  endtask

  task automatic mandar(input logic [7:0] letra);
    i_letra_tb = letra;
    i_letra_nueva_tb = 1'b1;
    ciclo();
    i_letra_nueva_tb = 1'b0;
  endtask

  initial begin
    $dumpfile("tb_comparador_letra.vcd");
    $dumpvars(0, tb_comparador_letra);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_letra_tb = 8'h41;
    i_letra_nueva_tb = 1'b0;
    i_word_tb = '0;
    i_word_length_tb = '0;
    i_state_tb = JUEGO;

    $display("== tb_comparador_letra, WORD_MAXLEN=%0d ==", WORD_MAXLEN);

    ciclo();
    rst_tb = 1'b0;

    cargar("CASA");
    mandar("A");
    ciclo();

    $finish;
  end

endmodule
