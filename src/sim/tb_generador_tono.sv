`timescale 1ns/1ps

// Testbench de generador_tono. Corre con: make sim TB=generador_tono (o make wave TB=generador_tono)
//
// Los parametros de frecuencia/duracion se sobreescriben a valores chicos (CLK_FREQ_HZ=1000,
// F_*_HZ y DUR_MS de un digito) para que los divisores y la duracion den contadores de un
// puñado de ciclos en vez de decenas de miles -- asi se puede simular una duracion completa de
// tono sin esperar milisegundos de tiempo simulado real. Los conteos esperados se leen directo
// de dut.N_ACIERTO/N_FALLO/N_FIN/DUR_CYCLES en vez de recalcularlos a mano, para no duplicar la
// formula del diseño.
//
// Nota sobre el estilo: igual que tb_temporizador y tb_transmisor_uart, las comprobaciones se
// escriben como macros de preprocesador (`define), no como task/function, por el mismo problema
// de Icarus Verilog documentado alla.
module tb_generador_tono;

    logic       clk;
    logic       rst;
    logic [2:0] i_state;
    logic [1:0] i_letra_state;
    logic       i_letra_lista;
    logic       o_sound;

    int errores = 0;

    generador_tono #(
        .CLK_FREQ_HZ(1000),
        .F_FALLO_HZ(25),   // grave, N mas grande de los tres
        .F_FIN_HZ(50),     // intermedio
        .F_ACIERTO_HZ(100),// agudo, N mas chico
        .DUR_MS(50)
    ) dut (
        .clk(clk),
        .rst(rst),
        .i_state(i_state),
        .i_letra_state(i_letra_state),
        .i_letra_lista(i_letra_lista),
        .o_sound(o_sound)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Códigos de estado, mismos que docs/diseño/modulos/M13_FSM.md, h
    localparam JUEGO = 3'b010; // "neutro": dec_fin=0, no dispara nada por si solo
    localparam GANO = 3'b011;
    localparam PERDIO_INTENTOS = 3'b100;
    localparam PERDIO_TIEMPO = 3'b101;

    // Códigos de letra_state, mismo contrato que M07_Comparador-letra
    localparam FALLO = 2'b00;
    localparam ACIERTO = 2'b01;
    localparam REPETIDA = 2'b10;

    `define CHECK_BIT(nombre, got, expected) \
        if ((got) !== (expected)) begin \
            $display("FALLO [%0t ns] %s: se esperaba %0b, se obtuvo %0b", $time, nombre, (expected), (got)); \
            errores = errores + 1; \
        end else begin \
            $display("OK    [%0t ns] %s: %0b", $time, nombre, (got)); \
        end

    // Dispara una letra evaluada: un ciclo de i_letra_lista con el codigo dado
    `define PULSA_LETRA(codigo) \
        i_letra_state = (codigo); \
        i_letra_lista = 1'b1; \
        @(posedge clk); #1; \
        i_letra_lista = 1'b0;

    // Lleva state de JUEGO a un estado de fin, dejando pasar un ciclo primero para que
    // dec_fin_prev se asiente en 0 y la entrada a ese estado sea un flanco de verdad
    `define DISPARA_FIN(estado_fin) \
        i_state = JUEGO; \
        @(posedge clk); #1; \
        i_state = (estado_fin); \
        @(posedge clk); #1;

    initial begin
        i_state = JUEGO;
        i_letra_state = FALLO;
        i_letra_lista = 1'b0;

        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;

        // 1) En reposo, sin ningún disparo, silencio
        `CHECK_BIT("reset: o_sound", o_sound, 1'b0)

        // 2) Acierto: el primer toggle tiene que salir exactamente N_ACIERTO+1 ciclos despues
        `PULSA_LETRA(ACIERTO)
        `CHECK_BIT("acierto: silencio justo tras el disparo", o_sound, 1'b0)
        repeat (dut.N_ACIERTO) @(posedge clk);
        #1;
        `CHECK_BIT("acierto: silencio justo antes del primer toggle", o_sound, 1'b0)
        @(posedge clk); #1;
        `CHECK_BIT("acierto: primer toggle", o_sound, 1'b1)

        // 3) Un fallo, unos ciclos despues, interrumpe el tono de acierto que seguia sonando:
        //    reinicia el divisor y la duracion, y el siguiente toggle sale con el periodo de
        //    fallo, no con el resto del periodo de acierto que estaba corriendo.
        repeat (2) @(posedge clk); #1;
        `PULSA_LETRA(FALLO)
        `CHECK_BIT("interrupcion: silencio justo al reiniciar con fallo", o_sound, 1'b0)
        repeat (dut.N_FALLO) @(posedge clk);
        #1;
        `CHECK_BIT("interrupcion: silencio justo antes del primer toggle de fallo", o_sound, 1'b0)
        @(posedge clk); #1;
        `CHECK_BIT("interrupcion: primer toggle de fallo", o_sound, 1'b1)

        // 4) La duracion es comun a los tres tonos: pasado DUR_CYCLES+1 ciclos desde que sono
        //    fallo, se apaga sola y ya no vuelve a togglear aunque el divisor lo permitiria.
        repeat (dut.DUR_CYCLES - dut.N_FALLO) @(posedge clk);
        #1;
        `CHECK_BIT("fin de duracion: silencio", o_sound, 1'b0)
        repeat (5) @(posedge clk);
        #1;
        `CHECK_BIT("fin de duracion: se mantiene en silencio", o_sound, 1'b0)

        // 5) Letra repetida no dispara ningun tono
        `PULSA_LETRA(REPETIDA)
        repeat (10) @(posedge clk);
        #1;
        `CHECK_BIT("repetida: no dispara tono", o_sound, 1'b0)
        `CHECK_BIT("repetida: reg_enable se mantiene apagado", dut.reg_enable, 1'b0)

        // 6) Entrada a GANO: mismo mecanismo de tono, con el periodo de fin
        `DISPARA_FIN(GANO)
        `CHECK_BIT("fin(GANO): silencio justo tras el disparo", o_sound, 1'b0)
        repeat (dut.N_FIN) @(posedge clk);
        #1;
        `CHECK_BIT("fin(GANO): silencio justo antes del primer toggle", o_sound, 1'b0)
        @(posedge clk); #1;
        `CHECK_BIT("fin(GANO): primer toggle", o_sound, 1'b1)

        // Deja que el tono de GANO termine su duracion completa antes de seguir, para no
        // arrastrar un reg_enable=1 a las pruebas siguientes
        repeat (dut.DUR_CYCLES - dut.N_FIN) @(posedge clk);
        #1;
        `CHECK_BIT("fin(GANO): se apago solo tras su duracion", dut.reg_enable, 1'b0)

        // 7) PERDIO_INTENTOS y PERDIO_TIEMPO tambien cuentan como fin de partida (mismo tono)
        `DISPARA_FIN(PERDIO_INTENTOS)
        `CHECK_BIT("fin(PERDIO_INTENTOS): carga el periodo de fin", dut.reg_n, dut.N_FIN)
        repeat (dut.DUR_CYCLES + 1) @(posedge clk); #1;

        `DISPARA_FIN(PERDIO_TIEMPO)
        `CHECK_BIT("fin(PERDIO_TIEMPO): carga el periodo de fin", dut.reg_n, dut.N_FIN)
        repeat (dut.DUR_CYCLES + 1) @(posedge clk); #1;

        // 8) Prioridad: si un acierto y una entrada a fin coinciden en el mismo ciclo, gana fin,
        //    igual que decide la tabla del MUX 3:1 del diseño (fin > acierto > fallo)
        i_state = JUEGO;
        @(posedge clk); #1;
        i_state = PERDIO_TIEMPO;
        i_letra_state = ACIERTO;
        i_letra_lista = 1'b1;
        @(posedge clk); #1;
        i_letra_lista = 1'b0;
        `CHECK_BIT("prioridad: carga el periodo de fin, no el de acierto", dut.reg_n, dut.N_FIN)

        if (errores == 0)
            $display("\n=== TODAS LAS PRUEBAS PASARON ===");
        else
            $display("\n=== %0d PRUEBA(S) FALLARON ===", errores);

        $finish;
    end

endmodule
