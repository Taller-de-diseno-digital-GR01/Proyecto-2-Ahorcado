module lfsr #(
  parameter N_PALABRAS = 50,         // mínimo que exige el enunciado
  parameter N_PALABRAS_DIFICIL = 20, // subconjunto de palabras de 6+ letras
  parameter WORD_MAXLEN = 15,        // columnas del PmodCLP, igual límite que M04/M11
  parameter LETRA_WIDTH = 5          // alcanza para 26 códigos (A-Z)
) (
  input logic clk,
  input logic rst,
  input logic [2:0] i_state, // desde la fsm, de acá solo interesa CARGA
  input logic i_modo,        // FACIL=0, DIFICIL=1, desde la fsm
  input logic [WORD_MAXLEN*LETRA_WIDTH+3:0] i_bank_word, // leído de REG_WBank en o_bank_addr, combinacional

  output logic [$clog2(N_PALABRAS + 1) - 1:0] o_bank_addr, // hacia REG_WBank, direcciones 1-50
  output logic [WORD_MAXLEN*LETRA_WIDTH+3:0] o_word,       // hacia REG_Palabra-escogida
  output logic o_valid_word                                 // hacia M13_FSM
  );

  localparam CARGA = 3'b001;

  // 6 bits para 50 palabras ($clog2(51)=6), cubre 1-63 con margen sin ensanchar el registro
  localparam int LFSR_WIDTH = $clog2(N_PALABRAS + 1);
  // 5 bits fijos: son los LSB del LFSR que se reutilizan como índice hacia ROM_IDX_DIFICIL (0-31)
  localparam int IDX_DIFICIL_WIDTH = 5;

  //REG_LFSR: registro de desplazamiento de período máximo, x^6+x^5+1, corre libre sin depender de state
  logic [LFSR_WIDTH-1:0] reg_lfsr;
  logic feedback;

  assign feedback = reg_lfsr[LFSR_WIDTH-1] ^ reg_lfsr[LFSR_WIDTH-2];

  always_ff @(posedge clk) begin
    if (rst) reg_lfsr <= {{(LFSR_WIDTH - 1) {1'b0}}, 1'b1}; // semilla no nula, todo-ceros es punto fijo
    else reg_lfsr <= {reg_lfsr[LFSR_WIDTH-2:0], feedback};
  end

  //Detección de entrada a CARGA (mismo detector de flanco que M02/M11 sobre sus propios eventos)
  logic dec_carga, dec_carga_prev, pulso_carga;

  assign dec_carga = (i_state == CARGA);

  always_ff @(posedge clk) begin
    if (rst) dec_carga_prev <= 1'b0;
    else dec_carga_prev <= dec_carga;
  end

  assign pulso_carga = dec_carga & ~dec_carga_prev;

  // ROM_IDX_DIFICIL: direcciones (dentro del banco de 50) de las palabras de 6+ letras.
  // TODO: mapeo lineal como placeholder (últimas N_PALABRAS_DIFICIL direcciones del banco);
  // reemplazar por el contenido real de REG_WBank.
  logic [LFSR_WIDTH-1:0] rom_idx_dificil [0:N_PALABRAS_DIFICIL-1];

  always_comb begin
    for (int i = 0; i < N_PALABRAS_DIFICIL; i++) begin
      rom_idx_dificil[i] = (N_PALABRAS - N_PALABRAS_DIFICIL + 1 + i);
    end
  end

  // Validez del índice y dirección según modo
  logic [IDX_DIFICIL_WIDTH-1:0] idx_dificil;
  logic valido_facil, valido_dificil, valido;
  logic [LFSR_WIDTH-1:0] addr_dificil, bank_addr_comb;

  assign idx_dificil = reg_lfsr[IDX_DIFICIL_WIDTH-1:0];
  assign valido_facil = (reg_lfsr <= N_PALABRAS[LFSR_WIDTH-1:0]);
  assign valido_dificil = (idx_dificil < N_PALABRAS_DIFICIL);
  assign valido = i_modo ? valido_dificil : valido_facil;

  assign addr_dificil = rom_idx_dificil[idx_dificil];
  assign bank_addr_comb = i_modo ? addr_dificil : reg_lfsr;
  assign o_bank_addr = bank_addr_comb;

  // REG_CARGADO y REG_WORD_SEL: captura la primera dirección válida tras entrar a CARGA
  logic reg_cargado;
  logic [WORD_MAXLEN*LETRA_WIDTH+3:0] reg_word_sel;

  always_ff @(posedge clk) begin
    if (rst) begin
      reg_cargado <= 1'b0;
    end
    else if (pulso_carga) begin
      reg_cargado <= 1'b0; // no dejar valid_word "heredado" de la partida anterior
    end
    else if (dec_carga && valido && !reg_cargado) begin
      reg_cargado <= 1'b1;
      reg_word_sel <= i_bank_word;
    end
  end

  assign o_valid_word = reg_cargado;
  assign o_word = reg_word_sel;

endmodule
