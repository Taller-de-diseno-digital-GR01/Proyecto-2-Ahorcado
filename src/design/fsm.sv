// FSM principal, docs/M13_FSM.md, con el ajuste de juntar los dos estados de derrota en uno
// solo: PERDIO se alcanza tanto por i_intentos_agotados como por i_tiempo_agotado, sin guardar
// la causa. El codigo 3'b101 que antes era PERDIO_TIEMPO queda libre, junto con 3'b110 y 3'b111,
// y cae en el mismo default que esos dos.
module fsm (
  input logic clk,
  input logic rst,

  input logic i_sel,               // pulso de cambio de modo, desde botones
  input logic i_ok,                // pulso de confirmacion, desde botones
  input logic i_valid_word,        // palabra lista en REG_Palabra-escogida, desde lfsr
  input logic i_palabra_completa,  // todas las posiciones reveladas, desde comparador_letra
  input logic i_intentos_agotados, // seis letras incorrectas, desde contador_intentos
  input logic i_tiempo_agotado,    // cuenta regresiva en cero, desde temporizador
  input logic i_fin_espera,        // se cumplieron los 3 s de resultado, desde temporizador

  output logic [2:0] o_state, // hacia todos los modulos que decodifican el estado
  output logic       o_modo   // 0 FACIL, 1 DIFICIL, hacia los modulos que necesitan la dificultad
  );

  // Codificacion de state, contrato publico que decodifican los demas modulos
  localparam logic [2:0] SELECCION = 3'b000;
  localparam logic [2:0] CARGA     = 3'b001;
  localparam logic [2:0] JUEGO     = 3'b010;
  localparam logic [2:0] GANO      = 3'b011;
  localparam logic [2:0] PERDIO    = 3'b100;
  // 3'b101, 3'b110 y 3'b111 no se usan, el default de la logica de siguiente estado los manda a
  // SELECCION para no dejar estados colgados ni inferir un latch.

  logic [2:0] estado, estado_siguiente;
  logic       modo;

  always_comb begin
    estado_siguiente = estado; // valor por defecto, evita latch

    case (estado)
      SELECCION: if (i_ok) 
        estado_siguiente = CARGA;
                 // sel se queda en SELECCION, solo conmuta modo en el bloque secuencial
      CARGA: if (i_valid_word) 
        estado_siguiente = JUEGO;
      JUEGO: if (i_palabra_completa)       
                estado_siguiente = GANO;
            else if (i_intentos_agotados) 
               estado_siguiente = PERDIO;
            else if (i_tiempo_agotado)    
                estado_siguiente = PERDIO;
      GANO: if (i_fin_espera) 
        estado_siguiente = SELECCION;
      PERDIO: if (i_fin_espera) 
        estado_siguiente = SELECCION;
        default:   estado_siguiente = SELECCION; // 101, 110, 111
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      estado <= SELECCION;
      modo   <= 1'b0; // arranca en FACIL
    end
    else begin
      estado <= estado_siguiente;
      if (estado == SELECCION && i_sel) modo <= ~modo; // congelado fuera de SELECCION
    end
  end

  assign o_state = estado;
  assign o_modo  = modo;

endmodule
