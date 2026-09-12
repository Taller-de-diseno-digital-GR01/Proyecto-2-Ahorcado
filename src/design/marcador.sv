`timescale 1ns/1ps

// ============================================================
// M01_Marcador
//
// Entradas:
//   time_value         -> valor proveniente de M03_Temporizador
//   num_ganadas  -> valor proveniente de M06_Ganadas
//
// Salidas:
//   seg[6:0] -> segmentos abcdefg, activos en bajo
//   an[3:0]  -> selección de dígito, activa en bajo
//   dp       -> punto decimal, apagado
// ============================================================

module marcador #(
    parameter REFRESH_BITS = 18
)(
    input  logic       clk,
    input  logic       rst,
    input  logic [6:0] time_value,
    input  logic [6:0] num_ganadas,

    output logic [6:0] seg,
    output logic [3:0] an,
    output logic       dp
);

    logic [6:0] time_value_reg;
    logic [6:0] ganadas_reg;
    logic [1:0] selector;
    logic [3:0] digito_bcd;

    reg_tiempo REG_TIEMPO (
        .clk      (clk),
        .rst      (rst),
        .time_value_in  (time_value),
        .time_value_out (time_value_reg)
    );

    reg_ganadas REG_GANADAS (
        .clk             (clk),
        .rst             (rst),
        .num_ganadas_in  (num_ganadas),
        .num_ganadas_out (ganadas_reg)
    );

    contador_refresco #(
        .REFRESH_BITS(REFRESH_BITS)
    ) CONT_REFRESCO (
        .clk      (clk),
        .rst      (rst),
        .selector (selector)
    );

    selector_digito SELECTOR_DIGITO (
        .time_value_value  (time_value_reg),
        .num_ganadas (ganadas_reg),
        .selector    (selector),
        .digito_bcd  (digito_bcd),
        .an          (an)
    );

    decod_bcd_7seg DECODIFICADOR (
        .bcd (digito_bcd),
        .seg (seg)
    );

    // Punto decimal apagado
    assign dp = 1'b1;

endmodule


module reg_tiempo (
    input  logic       clk,
    input  logic       rst,
    input  logic [6:0] time_value_in,
    output logic [6:0] time_value_out
);

    always_ff @(posedge clk) begin
        if (rst)
            time_value_out <= 7'd0;
        else
            time_value_out <= time_value_in;
    end

endmodule


module reg_ganadas (
    input  logic       clk,
    input  logic       rst,
    input  logic [6:0] num_ganadas_in,
    output logic [6:0] num_ganadas_out
);

    always_ff @(posedge clk) begin
        if (rst)
            num_ganadas_out <= 7'd0;
        else
            num_ganadas_out <= num_ganadas_in;
    end

endmodule



module contador_refresco #(
    parameter REFRESH_BITS = 18
)(
    input  logic       clk,
    input  logic       rst,
    output logic [1:0] selector
);

    logic [REFRESH_BITS-1:0] contador;

    always_ff @(posedge clk) begin
        if (rst)
            contador <= '0;
        else
            contador <= contador + 1'b1;
    end

    assign selector = contador[REFRESH_BITS-1 -: 2];

endmodule


// ============================================================
// Selector de dígito
//
// AN0 -> unidades de partidas ganadas
// AN1 -> decenas de partidas ganadas
// AN2 -> unidades del tiempo
// AN3 -> decenas del tiempo
// ============================================================
module selector_digito (
    input  logic [6:0] time_value_value,
    input  logic [6:0] num_ganadas,
    input  logic [1:0] selector,

    output logic [3:0] digito_bcd,
    output logic [3:0] an
);

    logic [3:0] time_value_decenas;
    logic [3:0] time_value_unidades;
    logic [3:0] win_decenas;
    logic [3:0] win_unidades;

    always_comb begin

        time_value_decenas  = time_value_value / 10;
        time_value_unidades = time_value_value % 10;

        win_decenas   = num_ganadas / 10;
        win_unidades  = num_ganadas % 10;

        digito_bcd = 4'd0;
        an         = 4'b1111;

        case (selector)

            2'b00: begin
                digito_bcd = win_unidades;
                an         = 4'b1110;
            end

            2'b01: begin
                digito_bcd = win_decenas;
                an         = 4'b1101;
            end

            2'b10: begin
                digito_bcd = time_value_unidades;
                an         = 4'b1011;
            end

            2'b11: begin
                digito_bcd = time_value_decenas;
                an         = 4'b0111;
            end

            default: begin
                digito_bcd = 4'd0;
                an         = 4'b1111;
            end

        endcase
    end

endmodule


// ============================================================
// Decodificador BCD -> 7 segmentos
//
// seg[6:0] = abcdefg
// Salidas activas en bajo
// ============================================================
module decod_bcd_7seg (
    input  logic [3:0] bcd,
    output logic [6:0] seg
);

    always_comb begin
        case (bcd)
            4'd0: seg = 7'b1000000;
            4'd1: seg = 7'b1111001;
            4'd2: seg = 7'b0100100;
            4'd3: seg = 7'b0110000;
            4'd4: seg = 7'b0011001;
            4'd5: seg = 7'b0010010;
            4'd6: seg = 7'b0000010;
            4'd7: seg = 7'b1111000;
            4'd8: seg = 7'b0000000;
            4'd9: seg = 7'b0010000;
            default: seg = 7'b1111111;
        endcase
    end

endmodule
