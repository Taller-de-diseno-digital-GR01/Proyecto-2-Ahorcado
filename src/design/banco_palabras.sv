// TODO: Hacer la documentación de esto
module banco_palabras #(
  parameter int N_PALABRAS  = 50,
  parameter int WORD_MAXLEN = 12, // columnas del lcd
  parameter int LETRA_WIDTH = 5   // A-Z como código 0-25
) (
  // direcciones 1 a N_PALABRAS, igual que REG_LFSR
  input  logic [$clog2(N_PALABRAS + 1) - 1:0] i_bank_addr,
  // {longitud[3:0], letra_WORD_MAXLEN[4:0], ..., letra1[4:0]}, letra1 en los bits bajos
  output logic [WORD_MAXLEN * LETRA_WIDTH + 3:0] o_bank_word
);

  localparam int LONGITUD_WIDTH = $clog2(WORD_MAXLEN + 1);
  localparam logic [LETRA_WIDTH-1:0] RELLENO = '0;

  // Direcciones 1-32: grupo FACIL_DIFICIL (6 a 12 letras). Direcciones 33-50: grupo SOLO_FACIL
  // (4 a 5 letras). El orden importa, ver la nota de arriba sobre lfsr.sv y N_PALABRAS_DIFICIL.
  logic [WORD_MAXLEN*8-1:0]  rom_ascii    [1:N_PALABRAS];
  logic [LONGITUD_WIDTH-1:0] rom_longitud [1:N_PALABRAS];

  initial begin
    rom_ascii[1]  = "CIUDAD";       rom_longitud[1]  = 4'd6;
    rom_ascii[2]  = "PUENTE";       rom_longitud[2]  = 4'd6;
    rom_ascii[3]  = "CAMINO";       rom_longitud[3]  = 4'd6;
    rom_ascii[4]  = "BOSQUE";       rom_longitud[4]  = 4'd6;
    rom_ascii[5]  = "CONEJO";       rom_longitud[5]  = 4'd6;
    rom_ascii[6]  = "PLANTA";       rom_longitud[6]  = 4'd6;
    rom_ascii[7]  = "SEMANA";       rom_longitud[7]  = 4'd6;
    rom_ascii[8]  = "ESPEJO";       rom_longitud[8]  = 4'd6;
    rom_ascii[9]  = "PIEDRA";       rom_longitud[9]  = 4'd6;
    rom_ascii[10] = "CUERDA";       rom_longitud[10] = 4'd6;
    rom_ascii[11] = "MEMORIA";      rom_longitud[11] = 4'd7;
    rom_ascii[12] = "VENTANA";      rom_longitud[12] = 4'd7;
    rom_ascii[13] = "ESCUELA";      rom_longitud[13] = 4'd7;
    rom_ascii[14] = "TECLADO";      rom_longitud[14] = 4'd7;
    rom_ascii[15] = "SEMILLA";      rom_longitud[15] = 4'd7;
    rom_ascii[16] = "BOTELLA";      rom_longitud[16] = 4'd7;
    rom_ascii[17] = "CAMPANA";      rom_longitud[17] = 4'd7;
    rom_ascii[18] = "CUCHARA";      rom_longitud[18] = 4'd7;
    rom_ascii[19] = "CUADERNO";     rom_longitud[19] = 4'd8;
    rom_ascii[20] = "ELEFANTE";     rom_longitud[20] = 4'd8;
    rom_ascii[21] = "ESTRELLA";     rom_longitud[21] = 4'd8;
    rom_ascii[22] = "MARTILLO";     rom_longitud[22] = 4'd8;
    rom_ascii[23] = "PANTALLA";     rom_longitud[23] = 4'd8;
    rom_ascii[24] = "INVIERNO";     rom_longitud[24] = 4'd8;
    rom_ascii[25] = "MARIPOSA";     rom_longitud[25] = 4'd8;
    rom_ascii[26] = "BICICLETA";    rom_longitud[26] = 4'd9;
    rom_ascii[27] = "CARRETERA";    rom_longitud[27] = 4'd9;
    rom_ascii[28] = "CIRCUITOS";    rom_longitud[28] = 4'd9;
    rom_ascii[29] = "TRANSISTOR";   rom_longitud[29] = 4'd10;
    rom_ascii[30] = "CONDENSADOR";  rom_longitud[30] = 4'd11;
    rom_ascii[31] = "LABORATORIO";  rom_longitud[31] = 4'd11;
    rom_ascii[32] = "AMPLIFICADOR"; rom_longitud[32] = 4'd12;

    rom_ascii[33] = "CASA";  rom_longitud[33] = 4'd4;
    rom_ascii[34] = "LUNA";  rom_longitud[34] = 4'd4;
    rom_ascii[35] = "MESA";  rom_longitud[35] = 4'd4;
    rom_ascii[36] = "NUBE";  rom_longitud[36] = 4'd4;
    rom_ascii[37] = "RANA";  rom_longitud[37] = 4'd4;
    rom_ascii[38] = "FLOR";  rom_longitud[38] = 4'd4;
    rom_ascii[39] = "GATO";  rom_longitud[39] = 4'd4;
    rom_ascii[40] = "PATO";  rom_longitud[40] = 4'd4;
    rom_ascii[41] = "PERRO"; rom_longitud[41] = 4'd5;
    rom_ascii[42] = "CIELO"; rom_longitud[42] = 4'd5;
    rom_ascii[43] = "TIGRE"; rom_longitud[43] = 4'd5;
    rom_ascii[44] = "PLAYA"; rom_longitud[44] = 4'd5;
    rom_ascii[45] = "QUESO"; rom_longitud[45] = 4'd5;
    rom_ascii[46] = "FUEGO"; rom_longitud[46] = 4'd5;
    rom_ascii[47] = "CARRO"; rom_longitud[47] = 4'd5;
    rom_ascii[48] = "RELOJ"; rom_longitud[48] = 4'd5;
    rom_ascii[49] = "VERDE"; rom_longitud[49] = 4'd5;
    rom_ascii[50] = "LIBRO"; rom_longitud[50] = 4'd5;
  end

  // Convierte ASCII 'A'..'Z' al codigo de 5 bits usado por el resto del diseño:
  // A=0, B=1, ..., Z=25.
  function automatic logic [LETRA_WIDTH-1:0] ascii_a_codigo(input logic [7:0] c);
    begin
      if ((c >= 8'h41) && (c <= 8'h5A))
        ascii_a_codigo = c - 8'h41;
      else
        ascii_a_codigo = RELLENO;
    end
  endfunction

  // Lectura combinacional de la direccion solicitada por el LFSR y empaque de la palabra.
  // Formato de salida:
  // {longitud[3:0], letra_WORD_MAXLEN[4:0], ..., letra2[4:0], letra1[4:0]}
  always_comb begin
    o_bank_word = '0;

    if ((i_bank_addr >= 1) && (i_bank_addr <= N_PALABRAS)) begin
      // Longitud en los 4 bits superiores.
      o_bank_word[WORD_MAXLEN*LETRA_WIDTH +: 4] = rom_longitud[i_bank_addr];

      // letra1 queda en los bits menos significativos.
      for (int pos = 0; pos < WORD_MAXLEN; pos++) begin
        if (pos < rom_longitud[i_bank_addr]) begin
          o_bank_word[pos*LETRA_WIDTH +: LETRA_WIDTH] =
            ascii_a_codigo(
              rom_ascii[i_bank_addr][((rom_longitud[i_bank_addr]-1-pos)*8) +: 8]
            );
        end
        else begin
          o_bank_word[pos*LETRA_WIDTH +: LETRA_WIDTH] = RELLENO;
        end
      end
    end
  end

endmodule
