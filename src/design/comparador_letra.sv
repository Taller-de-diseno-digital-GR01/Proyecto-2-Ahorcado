// Ver docs/diseño/modulos/M07_Comparador-letra.md
module comparador_letra #(parameter WORD_MAXLEN = 12, parameter LETRA_WIDTH = 5) (
  input logic clk,
  input logic rst,
  input logic [7:0] i_letra, // ascii, tal como salió del uart
  input logic i_letra_nueva, // estrobo de un ciclo desde REG_Letra-in
  input logic [WORD_MAXLEN*LETRA_WIDTH-1:0] i_word, // palabra de la partida, letra 1 en los bits bajos
  input logic [$clog2(WORD_MAXLEN+1)-1:0] i_word_length,
  input logic [2:0] i_state, // desde la fsm, de acá solo me interesa CARGA

  output logic [1:0] o_letra_state, // 00 fallo, 01 acierto, 10 repetida
  output logic o_letra_lista, // estrobo que acompaña a o_letra_state
  output logic o_palabra_completa, // hacia la fsm
  output logic [WORD_MAXLEN-1:0] o_mascara, // posiciones reveladas, hacia el lcd y el transmisor
  output logic o_try // pulso de fallo, hacia contador_intentos
  );

  localparam CARGA = 3'b001;
  localparam FALLO = 2'b00;
  localparam ACIERTO = 2'b01;
  localparam REPETIDA = 2'b10;

endmodule
