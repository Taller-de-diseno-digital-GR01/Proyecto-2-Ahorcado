// Ver docs/diseño/modulos/M12_Contador-Intentos.md
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

endmodule
