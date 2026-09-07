module transmisor_uart (
  input logic clk,
  input logic rst,
  input logic [2:0] i_state,       // desde la fsm
  input logic i_modo,              // desde la fsm
  input logic [1:0] i_letra_state, // 00 fallo, 01 acierto, 10 repetida, desde M07_Comparador-letra
  input logic i_letra_lista,       // pulso de un ciclo que acompaña a i_letra_state, desde M07
  input logic [2:0] i_try,         // intentos fallidos acumulados, desde M12_Contador-Intentos
  input logic [3:0] i_word_length, // longitud de la palabra, desde REG_Palabra-escogida
  input logic i_tx_rdy,            // pulso de 1 ciclo desde la UART, "ya mandé el byte anterior"

  output logic o_tx_start,   // pulso de 1 ciclo hacia la UART, "acá va un byte nuevo"
  output logic [7:0] o_tx_data // byte a transmitir, válido el mismo ciclo que o_tx_start
  );

  // Códigos de estado de la FSM principal 
  localparam JUEGO = 3'b010;
  localparam GANO = 3'b011;
  localparam PERDIO_INTENTOS = 3'b100;
  localparam PERDIO_TIEMPO = 3'b101;

  localparam IDLE = 2'b00;
  localparam SEND = 2'b01;
  localparam WAIT = 2'b10;

  //Detección de disparo: entrada a JUEGO, entrada a un estado de fin, y cada letra evaluada
  // (la repetida también manda trama, si no la PC se queda sin respuesta y vuelve a escribir)
  logic dec_juego, dec_juego_prev, pulso_ini;
  logic dec_fin, dec_fin_prev, pulso_fin;

  assign dec_juego = (i_state == JUEGO);
  assign dec_fin = (i_state == GANO) || (i_state == PERDIO_INTENTOS) || (i_state == PERDIO_TIEMPO);

  always_ff @(posedge clk) begin
    if (rst) begin
      dec_juego_prev <= 1'b0;
      dec_fin_prev <= 1'b0;
    end
    else begin
      dec_juego_prev <= dec_juego;
      dec_fin_prev <= dec_fin;
    end
  end

  assign pulso_ini = dec_juego & ~dec_juego_prev;
  assign pulso_fin = dec_fin & ~dec_fin_prev;

  //Banderas "pendiente", se quedan en alto hasta que la FSM interna las consume, para no
  // perder un evento que llega mientras se sigue enviando una trama anterior
  logic [1:0] estado, estado_sig;
  logic hay_pendiente, consumir;
  logic pend_ini, pend_ini_next;
  logic pend_letra, pend_letra_next;
  logic pend_fin, pend_fin_next;
  logic [1:0] pend_letra_val;
  logic [2:0] pend_try_val;
  logic [2:0] pend_fin_causa;

  assign hay_pendiente = pend_fin | pend_letra | pend_ini;
  assign consumir = (estado == IDLE) && hay_pendiente;

  // El set tiene prioridad sobre el clear si coinciden en el mismo ciclo, para no perder un
  // evento nuevo justo cuando se está consumiendo uno viejo del mismo tipo
  always_comb begin
    pend_ini_next = pend_ini;
    pend_letra_next = pend_letra;
    pend_fin_next = pend_fin;
    if (consumir) begin
      if (pend_fin) pend_fin_next = 1'b0;
      else if (pend_letra) pend_letra_next = 1'b0;
      else if (pend_ini) pend_ini_next = 1'b0;
    end
    if (pulso_ini) pend_ini_next = 1'b1;
    if (i_letra_lista) pend_letra_next = 1'b1;
    if (pulso_fin) pend_fin_next = 1'b1;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      pend_ini <= 1'b0;
      pend_letra <= 1'b0;
      pend_fin <= 1'b0;
    end
    else begin
      pend_ini <= pend_ini_next;
      pend_letra <= pend_letra_next;
      pend_fin <= pend_fin_next;
    end
    // valores capturados: se sobreescriben con el más reciente aunque el anterior siga sin atender
    if (i_letra_lista) begin
      pend_letra_val <= i_letra_state;
      pend_try_val <= i_try;
    end
    if (pulso_fin) pend_fin_causa <= i_state;
  end

  // Máquina de estados: IDLE decide cuál pendiente atender (prioridad fin > letra > inicio),
  // SEND pulsa tx_start con el byte actual, WAIT espera el pulso tx_rdy antes del siguiente byte
  logic [1:0] cnt_byte;
  logic [1:0] reg_len;
  logic [7:0] reg_trama [0:2];

  always_comb begin
    estado_sig = estado;
    case (estado)
      IDLE: if (hay_pendiente) estado_sig = SEND;
      SEND: estado_sig = WAIT;
      WAIT: if (i_tx_rdy) estado_sig = (cnt_byte == reg_len - 1) ? IDLE : SEND;
      default: estado_sig = IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) estado <= IDLE;
    else estado <= estado_sig;
  end

  always_ff @(posedge clk) begin
    if (rst) cnt_byte <= 2'd0;
    else if (consumir) cnt_byte <= 2'd0;
    else if ((estado == WAIT) && i_tx_rdy && (cnt_byte != reg_len - 1)) cnt_byte <= cnt_byte + 1'b1;
  end

  // Carga de la trama al consumir la pendiente de mayor prioridad
  always_ff @(posedge clk) begin
    if (consumir) begin
      if (pend_fin) begin
        reg_trama[0] <= 8'h46; // "F"
        reg_trama[1] <= {5'b0, pend_fin_causa};
        reg_len <= 2'd2;
      end
      else if (pend_letra) begin
        reg_trama[0] <= 8'h4C; // "L"
        reg_trama[1] <= {6'b0, pend_letra_val};
        reg_trama[2] <= {5'b0, pend_try_val};
        reg_len <= 2'd3;
      end
      else begin // pend_ini
        reg_trama[0] <= 8'h49; // "I"
        reg_trama[1] <= {7'b0, i_modo};
        reg_trama[2] <= {4'b0, i_word_length};
        reg_len <= 2'd3;
      end
    end
  end

  //4Salidas hacia la UART: tx_data siempre muestra el byte actual, tx_start solo pulsa en SEND
  assign o_tx_start = (estado == SEND);
  assign o_tx_data = reg_trama[cnt_byte];

endmodule
