// Ver docs/diseño/modulos/M10_Receptor-UART.md
module receptor_uart (
  input logic clk,
  input logic rst,
  input logic [31:0] i_rdata, // lo que devuelve el periférico uart en la dirección que le estoy poniendo
  input logic [2:0] i_state, // desde la fsm, de acá solo me interesa JUEGO

  output logic [1:0] o_addr,
  output logic o_write_enable,
  output logic [31:0] o_wdata,
  output logic [7:0] o_letra, // hacia REG_Letra-in
  output logic o_valid_w // habilitación de carga de esa letra
  );

  // TODO: Revisar las direcciones cuando el frente de uart cierre el mapa de registros del periférico
  localparam ADDR_CTRL = 2'b00;
  localparam ADDR_DATOS_RX = 2'b10;
  localparam BIT_NEW_RX = 1;

  localparam JUEGO = 3'b010;

  localparam ESPERA = 2'b00;
  localparam LEE = 2'b01;
  localparam LIMPIA = 2'b10;

  logic [1:0] estado;
  logic new_rx;

  assign new_rx = i_rdata[BIT_NEW_RX]; // solo vale mientras o_addr esté apuntando al registro de control

  // 1. Sondeo del periférico, tres ciclos por byte contra los 87 us que tarda uno a 115200 baudios
  always_ff @(posedge clk) begin
    if (rst) begin
      estado <= ESPERA;
    end
    else begin
      case (estado)
        ESPERA: if (new_rx) estado <= LEE;
        LEE: estado <= LIMPIA;
        LIMPIA: estado <= ESPERA;
        default: estado <= ESPERA;
      endcase
    end
  end

endmodule
