module contador_intentos #(parameter MAX_INTENTOS = 6) ( // el enunciado fija 6 letras incorrectas
  input logic clk,
  input logic rst,
  input logic i_try, // pulso de fallo, desde comparador_letra
  input logic [2:0] i_state, // desde la fsm, de acá solo me interesa CARGA

  output logic [$clog2(MAX_INTENTOS+1)-1:0] o_intentos, // acumulados, hacia el transmisor uart
  output logic o_intentos_agotados // hacia la fsm
  );

  localparam CARGA = 3'b001;

  logic [$clog2(MAX_INTENTOS+1)-1:0] cuenta;

  // El paso por CARGA es la señal de partida nueva, no hace falta que la fsm mande un clear aparte
  always_ff @(posedge clk) begin
    if (rst || i_state == CARGA) begin // el rst gana aunque llegue un try en el mismo ciclo
      cuenta <= 0;
    end
    else if (i_try && cuenta < MAX_INTENTOS) begin // satura, sin esto el try de más devuelve la cuenta a 0
      cuenta <= cuenta + 1;
    end
  end

  assign o_intentos = cuenta;
  assign o_intentos_agotados = (cuenta >= MAX_INTENTOS); // combinacional para que la fsm lo vea el mismo ciclo del sexto fallo

endmodule
