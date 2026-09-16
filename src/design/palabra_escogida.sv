module palabra_escogida #(
  parameter int WORD_MAXLEN = 12,
  parameter int LETRA_WIDTH = 5
) (
  // Palabra ya seleccionada por el LFSR:
  // {longitud[3:0], letra_WORD_MAXLEN[4:0], ..., letra1[4:0]}
  input  logic [WORD_MAXLEN*LETRA_WIDTH+3:0] i_word_packed,

  // Palabra codificada en 5 bits por letra, util para comparacion.
  output logic [WORD_MAXLEN*LETRA_WIDTH-1:0] o_word_codes,
  output logic [3:0]                         o_word_length,

  // Version ASCII de la palabra, util para el LCD.
  // Empacada como WORD_MAXLEN caracteres de 8 bits: caracter 0 en los bits
  // menos significativos (o_word_ascii[7:0]), caracter 1 en [15:8], etc.
  output logic [WORD_MAXLEN*8-1:0]           o_word_ascii
);

  assign o_word_codes  = i_word_packed[WORD_MAXLEN*LETRA_WIDTH-1:0];
  assign o_word_length = i_word_packed[WORD_MAXLEN*LETRA_WIDTH +: 4];

  always_comb begin
    for (int pos = 0; pos < WORD_MAXLEN; pos++) begin
      if (pos < o_word_length)
        o_word_ascii[pos*8 +: 8] = 8'h41 + i_word_packed[pos*LETRA_WIDTH +: LETRA_WIDTH];
      else
        o_word_ascii[pos*8 +: 8] = 8'h20;
    end
  end

endmodule
