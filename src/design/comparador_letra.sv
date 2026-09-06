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

  // 1. Comparación paralela, un comparador por posición, así una letra revela todas sus ocurrencias de un solo golpe
  logic [WORD_MAXLEN-1:0] coincide, relleno;
  logic [LETRA_WIDTH-1:0] codigo;
  logic hay_coincidencia;

  assign codigo = i_letra - 8'h41; // el uart manda ascii pero el banco guarda la letra como índice A=0

  always_comb begin
    for (int i = 0; i < WORD_MAXLEN; i++) begin
      relleno[i] = (i >= i_word_length); // posiciones del registro que no son parte de esta palabra
      coincide[i] = !relleno[i] && (i_word[i*LETRA_WIDTH +: LETRA_WIDTH] == codigo);
    end
  end

  assign hay_coincidencia = |coincide;

endmodule
