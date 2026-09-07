`timescale 1ns/1ps

// ============================================================
// M06_Ganadas
//
// Cuenta partidas ganadas al detectar la ENTRADA al estado GANO.
//
// Codificación relevante de M13_FSM:
//   000 -> SELECCION
//   001 -> CARGA
//   010 -> JUEGO
//   011 -> GANO
//   100 -> PERDIO_INTENTOS
//   101 -> PERDIO_TIEMPO
//
// El contador se satura en 99.
// rst devuelve el acumulado a 0.
// ============================================================

module M06_Ganadas (
    input  logic       clk,
    input  logic       rst,
    input  logic [2:0] state,
    output logic [6:0] num_ganadas
);

    localparam logic [2:0] GANO = 3'b011;

    logic [2:0] state_prev;
    logic [6:0] contador_ganadas;

    logic entrada_gano;


    assign entrada_gano = (state == GANO) && (state_prev != GANO);


    // --------------------------------------------------------
    // Registro del estado anterior
    // --------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            state_prev <= 3'b000;
        else
            state_prev <= state;
    end


    // --------------------------------------------------------
    // Contador ascendente de partidas ganadas
    // --------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            contador_ganadas <= 7'd0;

        else if (entrada_gano) begin
            if (contador_ganadas < 7'd99)
                contador_ganadas <= contador_ganadas + 1'b1;
            else
                contador_ganadas <= contador_ganadas;
        end
    end


    // --------------------------------------------------------
    // Registro de salida
    // --------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            num_ganadas <= 7'd0;
        else
            num_ganadas <= contador_ganadas;
    end

endmodule
