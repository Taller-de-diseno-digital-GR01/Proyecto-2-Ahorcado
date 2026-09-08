module generador_tono #(
  parameter CLK_FREQ_HZ = 100_000_000,
  parameter F_ACIERTO_HZ = 1000, // agudo, "positivo"
  parameter F_FALLO_HZ = 250,    // grave, "negativo"
  parameter F_FIN_HZ = 500,      // intermedio, distinguible de los otros dos
  parameter DUR_MS = 150         // duración común a los tres tonos
) (
  input logic clk,
  input logic rst,
  input logic [2:0] i_state, // desde la fsm, de acá solo interesan GANO/PERDIO_INTENTOS/PERDIO_TIEMPO
  input logic [1:0] i_letra_state, // 00 fallo, 01 acierto, 10 repetida, desde M07_Comparador-letra
  input logic i_letra_lista, // pulso de un ciclo que acompaña a i_letra_state, desde M07

  output logic o_sound // onda cuadrada de audio, hacia BUZZER
  );

  // Códigos de estado de la FSM principal
  localparam GANO = 3'b011;
  localparam PERDIO_INTENTOS = 3'b100;
  localparam PERDIO_TIEMPO = 3'b101;

  // Códigos de letra_state, mismo contrato que M07_Comparador-letra
  localparam FALLO = 2'b00;
  localparam ACIERTO = 2'b01;
  localparam REPETIDA = 2'b10; // no dispara tono, "se ignora sin penalizar"

  // N = f_clk / (2 * f_tono) - 1
  localparam int N_ACIERTO = CLK_FREQ_HZ / (2 * F_ACIERTO_HZ) - 1;
  localparam int N_FALLO   = CLK_FREQ_HZ / (2 * F_FALLO_HZ) - 1;
  localparam int N_FIN     = CLK_FREQ_HZ / (2 * F_FIN_HZ) - 1;
  localparam int N_MAX = (N_ACIERTO > N_FALLO)
    ? ((N_ACIERTO > N_FIN) ? N_ACIERTO : N_FIN) 
    : ((N_FALLO > N_FIN) ? N_FALLO : N_FIN);
  localparam int DIV_WIDTH = $clog2(N_MAX + 1);

  localparam int DUR_CYCLES = (CLK_FREQ_HZ / 1000) * DUR_MS - 1;
  localparam int DUR_WIDTH = $clog2(DUR_CYCLES + 1);

  //Detector de entrada a un estado de fin de partida (mismo patrón de flanco que M09_Botones)
  logic dec_fin, dec_fin_prev, pulso_fin;

  assign dec_fin = (i_state == GANO) || (i_state == PERDIO_INTENTOS) || (i_state == PERDIO_TIEMPO);

  always_ff @(posedge clk) begin
    if (rst) dec_fin_prev <= 1'b0;
    else dec_fin_prev <= dec_fin;
  end

  assign pulso_fin = dec_fin & ~dec_fin_prev;

  //Disparo y selección de tono, prioridad fin > acierto > fallo (repetida no dispara nada)
  logic trig;
  logic [DIV_WIDTH-1:0] next_n;

  assign trig = pulso_fin | (i_letra_lista && (i_letra_state == ACIERTO)) | (i_letra_lista && (i_letra_state == FALLO));

  always_comb begin
    if (pulso_fin) next_n = N_FIN[DIV_WIDTH-1:0];
    else if (i_letra_lista && (i_letra_state == ACIERTO)) next_n = N_ACIERTO[DIV_WIDTH-1:0];
    else next_n = N_FALLO[DIV_WIDTH-1:0]; // solo importa cuando trig=1 y ninguna de las anteriores, o sea fallo
  end

  logic [DIV_WIDTH-1:0] reg_n;

  always_ff @(posedge clk) begin
    if (rst) reg_n <= '0;
    else if (trig) reg_n <= next_n;
  end

  //REG_ENABLE y CONT_DURACION: cada trig interrumpe y reinicia el tono que estuviera sonando
  logic reg_enable;
  logic [DUR_WIDTH-1:0] cont_duracion;

  always_ff @(posedge clk) begin
    if (rst) begin
      reg_enable <= 1'b0;
      cont_duracion <= '0;
    end
    else if (trig) begin
      reg_enable <= 1'b1;
      cont_duracion <= '0;
    end
    else if (reg_enable) begin
      if (cont_duracion == DUR_CYCLES[DUR_WIDTH-1:0]) begin
        reg_enable <= 1'b0;
        cont_duracion <= '0;
      end
      else cont_duracion <= cont_duracion + 1'b1;
    end
  end

  // CONT_DIVISOR y REG_ONDA: generación de la onda cuadrada, arranca siempre desde silencio
  logic [DIV_WIDTH-1:0] cont_divisor;
  logic reg_onda;

  always_ff @(posedge clk) begin
    if (rst) begin
      cont_divisor <= '0;
      reg_onda <= 1'b0;
    end
    else if (trig) begin
      cont_divisor <= '0;
      reg_onda <= 1'b0;
    end
    else if (reg_enable) begin
      if (cont_divisor == reg_n) begin
        cont_divisor <= '0;
        reg_onda <= ~reg_onda;
      end
      else cont_divisor <= cont_divisor + 1'b1;
    end
    else begin
      cont_divisor <= '0;
      reg_onda <= 1'b0; // reposo, mantiene silencio
    end
  end

  // sound = REG_ONDA AND REG_ENABLE, para que el buzzer quede en 0 franco entre tonos
  assign o_sound = reg_onda & reg_enable;

endmodule
