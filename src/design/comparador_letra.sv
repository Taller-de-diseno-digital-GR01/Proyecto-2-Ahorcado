module comparador_letra #(parameter WORD_MAXLEN = 12, parameter LETRA_WIDTH = 5) (
  input logic clk,
  input logic rst,
  input logic [7:0] i_letra, // ascii, tal como salió del uart
  input logic i_letra_nueva, // pulso de un ciclo desde REG_Letra-in
  input logic [WORD_MAXLEN*LETRA_WIDTH-1:0] i_word, // palabra de la partida, letra 1 en los bits bajos
  input logic [$clog2(WORD_MAXLEN+1)-1:0] i_word_length, // +1 para que tengamos suficientes bits. Mejor que sobre a que falte
  input logic [2:0] i_state, // desde la fsm, de acá solo interesa CARGA

  output logic [1:0] o_letra_state, // 00 fallo, 01 acierto, 10 repetida
  output logic o_letra_lista, // pulso que acompaña a o_letra_state
  output logic o_palabra_completa, // hacia la fsm
  output logic [WORD_MAXLEN-1:0] o_mascara, // posiciones reveladas, hacia el lcd y el transmisor
  output logic o_try // pulso de fallo, hacia contador_intentos
  );

  // EStados
  localparam CARGA = 3'b001;
  localparam FALLO = 2'b00;
  localparam ACIERTO = 2'b01;
  localparam REPETIDA = 2'b10;

  // 1. Comparación paralela, un comparador por posición, así una letra revela todas sus ocurrencias de un solo golpe
  logic [WORD_MAXLEN-1:0] coincide, relleno;
  logic [LETRA_WIDTH-1:0] codigo;
  logic hay_coincidencia;

  assign codigo = i_letra - 8'h41; // el uart manda ascii pero el banco guarda la letra

  always_comb begin
    for (int i = 0; i < WORD_MAXLEN; i++) begin
      relleno[i] = (i >= i_word_length); // posiciones del registro que no son parte de esta palabra
      coincide[i] = !relleno[i] && (i_word[i*LETRA_WIDTH +: LETRA_WIDTH] == codigo);
    end
  end

  assign hay_coincidencia = (coincide != '0); // lo mismo que |coincide, junta todo el vector en un solo bit

  // 2. Lo que el módulo se acuerda de la partida, cuáles posiciones ya se revelaron y cuáles letras ya llegaron
  logic [WORD_MAXLEN-1:0] mascara;
  logic [25:0] usadas; // un bit por letra del alfabeto, el receptor ya filtró A-Z así que el índice nunca se sale
  logic ya_usada;

  assign ya_usada = usadas[codigo];

  always_ff @(posedge clk) begin
    if (rst) begin
      mascara <= '0;
      usadas <= '0;
    end
    // La máscara arranca con el relleno en unos para que el and de palabra completa sirva igual con 4 letras que con 12
    else if (i_state == CARGA) begin
      mascara <= relleno;
      usadas <= '0;
    end
    else if (i_letra_nueva && !ya_usada) begin
      usadas[codigo] <= 1'b1;
      mascara <= mascara | coincide; // si la letra falló, coincide viene en ceros y esto no cambia nada
    end
  end

  // 3. Evaluación de la letra, sale un ciclo después del pulso, alineada con la actualización de la máscara
  always_ff @(posedge clk) begin
    o_letra_lista <= 1'b0;
    o_try <= 1'b0;
    if (rst) begin
      o_letra_state <= FALLO;
    end
    else if (i_letra_nueva && i_state != CARGA) begin // en CARGA la mascara ignora la letra, la evaluacion tiene que ignorarla igual
      o_letra_lista <= 1'b1; // la repetida también avisa, si no la pc se queda sin respuesta y vuelve a escribir
      if (ya_usada) begin
        o_letra_state <= REPETIDA; // no gasta intento ni toca el temporizador, es lo que pide el enunciado
      end
      else if (hay_coincidencia) begin
        o_letra_state <= ACIERTO;
      end
      else begin
        o_letra_state <= FALLO;
        o_try <= 1'b1;
      end
    end
  end

  // 4. Salidas continuas
  assign o_mascara = mascara;
  assign o_palabra_completa = (mascara == '1); // lo mismo que &mascara, se levanta el mismo ciclo en que la última letra revela la última posición

endmodule
