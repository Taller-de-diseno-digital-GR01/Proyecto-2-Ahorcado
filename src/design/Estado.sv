`timescale 1ns/1ps

// ============================================================
// M05_Estado
//
// Recibe el estado global desde M13_FSM, lo registra y lo
// decodifica en una salida sencilla de estado.
//
// Codificación de state proveniente de fsm.sv:
//   000 -> SELECCION
//   001 -> CARGA
//   010 -> JUEGO
//   011 -> GANO
//   100 -> PERDIO (intentos y tiempo comparten un solo estado)
//
// Codificación de state_led:
//   00 -> selección
//   01 -> carga/juego
//   10 -> resultado final
// ============================================================

module M05_Estado (
    input  logic       clk,
    input  logic       rst,
    input  logic [2:0] state,
    output logic [1:0] state_led
);

    logic [2:0] state_reg;

    // --------------------------------------------------------
    // Registro del estado
    // --------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            state_reg <= 3'b000;
        else
            state_reg <= state;
    end

    // --------------------------------------------------------
    // Decodificador de estado
    // --------------------------------------------------------
    always_comb begin
        case (state_reg)

            // SELECCION
            3'b000:
                state_led = 2'b00;

            // CARGA o JUEGO
            3'b001,
            3'b010:
                state_led = 2'b01;

            // Estados de resultado
            3'b011,
            3'b100,
            3'b101:
                state_led = 2'b10;

            default:
                state_led = 2'b00;

        endcase
    end

endmodule
