// FSM interna de 4 estados (IDLE/HOME/SEND/WAIT) de docs/M04_Mostrar-LCD.md, fusionada con la
// arquitectura de nivel03: no hay "show" desde la FSM principal, este modulo decodifica "state"
// y repinta solo cuando cambia lo que le corresponde mostrar (state, modo en SELECCION, mascara
// en JUEGO). letra_in se elimino del puerto: para redibujar la palabra completa con varias
// letras ya reveladas hace falta la palabra secreta entera, no solo la ultima letra recibida,
// asi que word/word_length se agregaron desde REG_Palabra-escogida (mismo origen que M07 y M11).
module mostrar_lcd (
  input logic        clk,
  input logic        rst,

  input logic [2:0]  i_state,        // desde M13_FSM, decide cual pantalla toca
  input logic        i_modo,         // desde M13_FSM, 0=FACIL 1=DIFICIL
  input logic [95:0] i_word,         // palabra escogida, desde REG_Palabra-escogida; 12 letras ASCII empacadas, letra 0 en los bits bajos
  input logic [3:0]  i_word_length,  // cuantas posiciones de i_word son validas
  input logic [11:0] i_mascara,      // posiciones ya reveladas, desde M07_Comparador-letra

  input logic [31:0] i_rdata,        // lo que devuelve PERIFERICO_LCD en la direccion que le estoy poniendo

  output logic [1:0]  o_addr,
  output logic        o_write_enable,
  output logic [31:0] o_wdata
  );

  // TODO: Revisar ADDR_CTRL_ESTADO/ADDR_DATOS con el frente de LCD, el enunciado no fija estas direcciones
  localparam logic [1:0] ADDR_CTRL_ESTADO = 2'b00;
  localparam logic [1:0] ADDR_DATOS       = 2'b01;

  localparam BIT_START = 0;
  localparam BIT_RS    = 1;
  localparam BIT_CLEAR = 2;
  localparam BIT_HOME  = 3;
  localparam BIT_BUSY  = 8;
  localparam BIT_DONE  = 9;

  // Codificacion de state, fijada por fsm.sv. PERDIO_INTENTOS y PERDIO_TIEMPO se unificaron en
  // un solo ST_PERDIO, ya no hay forma de distinguir la causa desde state.
  localparam logic [2:0] ST_SELECCION = 3'b000;
  localparam logic [2:0] ST_CARGA     = 3'b001;
  localparam logic [2:0] ST_JUEGO     = 3'b010;
  localparam logic [2:0] ST_GANO      = 3'b011;
  localparam logic [2:0] ST_PERDIO    = 3'b100;

  // FSM interna, codificacion fija por diseño (S1 S0): IDLE=00, HOME=01, SEND=10, WAIT=11
  localparam logic [1:0] IDLE = 2'b00;
  localparam logic [1:0] HOME = 2'b01;
  localparam logic [1:0] SEND = 2'b10;
  localparam logic [1:0] WAIT = 2'b11;

  logic [1:0] estado, estado_siguiente;
  // Dentro de SEND: 0 escribe el byte en REG_DATOS, 1 pulsa start/rs en REG_CTRL_ESTADO.
  // Son dos direcciones distintas del mismo bus, no caben en el mismo ciclo.
  logic byte_step, byte_step_siguiente;
  logic [3:0] pos, pos_siguiente; // CONT_POSICION, direccion dentro del mensaje

  // Contenido "activo": foto de lo que se esta enviando, tomada al entrar a HOME, para no
  // mezclar dos mensajes distintos si el contenido cambia a medio envio.
  logic [2:0]  act_state;
  logic        act_modo;
  logic [11:0] act_mascara;
  logic [3:0]  act_last_pos; // ultima posicion valida del mensaje activo (largo - 1)

  function automatic logic [7:0] f_byte(
      input logic [2:0] st,
      input logic       mo,
      input logic [3:0] p
    );
    logic [7:0] b;
    begin
      b = " ";
      case (st)
        ST_SELECCION: begin
          if (mo) begin // "MODO: DIFICIL", 13 caracteres
            case (p)
              4'd0: b = "M"; 4'd1: b = "O"; 4'd2: b = "D"; 4'd3:  b = "O"; 4'd4:  b = ":";
              4'd5: b = " "; 4'd6: b = "D"; 4'd7: b = "I"; 4'd8:  b = "F"; 4'd9:  b = "I";
              4'd10: b = "C"; 4'd11: b = "I"; 4'd12: b = "L";
              default: b = " ";
            endcase
          end
          else begin // "MODO: FACIL", 11 caracteres
            case (p)
              4'd0: b = "M"; 4'd1: b = "O"; 4'd2: b = "D"; 4'd3: b = "O"; 4'd4: b = ":";
              4'd5: b = " "; 4'd6: b = "F"; 4'd7: b = "A"; 4'd8: b = "C"; 4'd9: b = "I";
              4'd10: b = "L";
              default: b = " ";
            endcase
          end
        end
        ST_GANO: begin // "GANASTE", 7 caracteres
          case (p)
            4'd0: b = "G"; 4'd1: b = "A"; 4'd2: b = "N"; 4'd3: b = "A"; 4'd4: b = "S";
            4'd5: b = "T"; 4'd6: b = "E";
            default: b = " ";
          endcase
        end
        ST_PERDIO: begin // "PERDISTE", 8 caracteres, sin causa porque state ya no la distingue
          case (p)
            4'd0: b = "P"; 4'd1: b = "E"; 4'd2: b = "R"; 4'd3: b = "D";
            4'd4: b = "I"; 4'd5: b = "S"; 4'd6: b = "T"; 4'd7: b = "E";
            default: b = " ";
          endcase
        end
        default: b = " "; // SELECCION/CARGA sin pantalla asignada aqui no llegan a f_byte
      endcase
      f_byte = b;
    end
  endfunction

  // Largo (ultima posicion) de cada mensaje, se calcula una sola vez al entrar a HOME
  function automatic logic [3:0] f_last_pos(input logic [2:0] st, input logic mo, input logic [3:0] wlen);
    case (st)
      ST_SELECCION: f_last_pos = mo ? 4'd12 : 4'd10;
      ST_JUEGO:     f_last_pos = (wlen == 4'd0) ? 4'd0 : (wlen - 4'd1);
      ST_GANO:      f_last_pos = 4'd6;
      ST_PERDIO:    f_last_pos = 4'd7;
      default:      f_last_pos = 4'd0;
    endcase
  endfunction

  logic done;
  assign done = i_rdata[BIT_DONE];

  // busy: PERIFERICO_LCD sigue corriendo su encendido del HD44780, no atiende bus todavia
  logic busy;
  assign busy = i_rdata[BIT_BUSY];

  // "cambio" reemplaza al pulso show que tenia la FSM principal: se repinta cuando cambia el
  // state, o cuando cambia lo que compone la pantalla actual (modo en SELECCION, mascara en
  // JUEGO). Se compara contra la foto "activa", asi que si el contenido cambia otra vez a medio
  // envio, cambio se mantiene en 1 y en cuanto vuelve a IDLE arranca un nuevo envio con lo mas
  // reciente.
  logic cambio;
  assign cambio = (i_state != act_state)
                || (i_state == ST_SELECCION && i_modo    != act_modo)
                || (i_state == ST_JUEGO     && i_mascara != act_mascara);

  always_comb begin
    estado_siguiente    = estado;
    byte_step_siguiente = byte_step;
    pos_siguiente        = pos;

    case (estado)
      // CARGA no tiene pantalla propia (M04_Mostrar-LCD.md g), no dispara redibujado
      IDLE: if (cambio && i_state != ST_CARGA && !busy) begin
              estado_siguiente    = HOME;
              pos_siguiente       = 4'd0;
              byte_step_siguiente = 1'b0;
            end
      // Mismo truco de sub-paso que SEND: byte_step=0 emite home/clear, byte_step=1 espera done
      // antes de pasar a SEND. HOME no puede avanzar sin esperar done: el HD44780 tarda mucho
      // mas en un clear/home que en una escritura normal, y sin esta espera el primer byte del
      // mensaje se pisa con el propio home/clear (visto en simulacion con tb_mostrar_lcd.sv).
      HOME: if (byte_step == 1'b0)
              byte_step_siguiente = 1'b1;
            else if (done) begin
              estado_siguiente    = SEND;
              byte_step_siguiente = 1'b0;
            end
      SEND: if (byte_step == 1'b0)
              byte_step_siguiente = 1'b1;
            else begin
              estado_siguiente    = WAIT;
              byte_step_siguiente = 1'b0;
            end
      WAIT: if (done) begin
              if (pos == act_last_pos)
                estado_siguiente = IDLE;
              else begin
                estado_siguiente = SEND;
                pos_siguiente    = pos + 4'd1;
              end
            end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      estado       <= IDLE;
      byte_step    <= 1'b0;
      pos          <= 4'd0;
      act_state    <= 3'b111; // codigo no usado por M13_FSM, fuerza el primer redibujado
      act_modo     <= 1'b0;
      act_mascara  <= 12'b0;
      act_last_pos <= 4'd0;
    end
    else begin
      estado    <= estado_siguiente;
      byte_step <= byte_step_siguiente;
      pos       <= pos_siguiente;
      // Foto del contenido, tomada justo al arrancar el envio (IDLE -> HOME)
      if (estado == IDLE && estado_siguiente == HOME) begin
        act_state    <= i_state;
        act_modo     <= i_modo;
        act_mascara  <= i_mascara;
        act_last_pos <= f_last_pos(i_state, i_modo, i_word_length);
      end
    end
  end

  always_comb begin
    o_addr         = ADDR_CTRL_ESTADO;
    o_write_enable = 1'b0;
    o_wdata        = 32'b0;
    case (estado)
      // home + clear en el mismo golpe: home posiciona el cursor, clear borra lo que haya
      // quedado de un mensaje anterior mas largo que el nuevo. Solo se escribe una vez
      // (byte_step==0); mientras byte_step==1 el modulo solo esta esperando done, sin volver
      // a pulsar el comando.
      HOME: if (byte_step == 1'b0) begin
              o_write_enable      = 1'b1;
              o_wdata[BIT_CLEAR]  = 1'b1;
              o_wdata[BIT_HOME]   = 1'b1;
            end
      SEND: if (byte_step == 1'b0) begin
              o_addr         = ADDR_DATOS;
              o_write_enable = 1'b1;
              // Posiciones reveladas muestran la letra real de la palabra, el resto un guion bajo
              o_wdata[7:0]   = (act_state == ST_JUEGO) ? (act_mascara[pos] ? i_word[pos*8 +: 8] : "_")
                                                        : f_byte(act_state, act_modo, pos);
            end
            else begin
              o_write_enable     = 1'b1;
              o_wdata[BIT_START] = 1'b1;
              o_wdata[BIT_RS]    = 1'b1; // dato, no comando
            end
    endcase
  end

endmodule
