`timescale 1ns/1ps

module tb_M06_Ganadas;

    logic clk;
    logic rst;
    logic [2:0] state;
    logic [6:0] num_ganadas;

    integer errores;

    localparam logic [2:0] SELECCION        = 3'b000;
    localparam logic [2:0] CARGA            = 3'b001;
    localparam logic [2:0] JUEGO            = 3'b010;
    localparam logic [2:0] GANO             = 3'b011;
    localparam logic [2:0] PERDIO_INTENTOS  = 3'b100;
    localparam logic [2:0] PERDIO_TIEMPO    = 3'b101;

    M06_Ganadas dut (
        .clk         (clk),
        .rst         (rst),
        .state       (state),
        .num_ganadas (num_ganadas)
    );

    always #5 clk = ~clk;


    task automatic esperar_ciclos(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask


    task automatic comprobar(
        input integer esperado,
        input string mensaje
    );
        begin
            if (num_ganadas !== esperado[6:0]) begin
                $display(
                    "ERROR: %s -> num_ganadas=%0d, esperado=%0d",
                    mensaje,
                    num_ganadas,
                    esperado
                );
                errores = errores + 1;
            end
            else begin
                $display(
                    "OK: %s -> num_ganadas=%0d",
                    mensaje,
                    num_ganadas
                );
            end
        end
    endtask


    // Simula una partida ganada completa:
    // JUEGO -> GANO -> SELECCION
    task automatic ganar_partida;
        begin
            state = JUEGO;
            esperar_ciclos(2);

            state = GANO;

            // Se requieren dos ciclos:
            // 1) contador_ganadas incrementa
            // 2) num_ganadas registra el contador actualizado
            esperar_ciclos(2);

            state = SELECCION;
            esperar_ciclos(1);
        end
    endtask


    initial begin

        $dumpfile("tb_M06_Ganadas.vcd");
        $dumpvars(0, tb_M06_Ganadas);

        clk     = 1'b0;
        rst     = 1'b1;
        state   = SELECCION;
        errores = 0;

        esperar_ciclos(2);
        rst = 1'b0;
        esperar_ciclos(1);

        // ----------------------------------------------------
        // Caso 1: después de reset debe estar en 0
        // ----------------------------------------------------
        comprobar(0, "despues de reset");

        // ----------------------------------------------------
        // Caso 2: perder una partida NO incrementa
        // ----------------------------------------------------
        state = JUEGO;
        esperar_ciclos(1);

        state = PERDIO_INTENTOS;
        esperar_ciclos(2);

        comprobar(0, "derrota por intentos no incrementa");

        state = SELECCION;
        esperar_ciclos(1);

        // ----------------------------------------------------
        // Caso 3: primera victoria
        // ----------------------------------------------------
        ganar_partida();
        comprobar(1, "primera partida ganada");

        // ----------------------------------------------------
        // Caso 4: permanecer varios ciclos en GANO
        // debe contar UNA sola vez
        // ----------------------------------------------------
        state = JUEGO;
        esperar_ciclos(1);

        state = GANO;
        esperar_ciclos(5);

        comprobar(2, "GANO sostenido cuenta una sola vez");

        state = SELECCION;
        esperar_ciclos(1);

        // ----------------------------------------------------
        // Caso 5: tercera victoria
        // ----------------------------------------------------
        ganar_partida();
        comprobar(3, "tercera partida ganada");

        // ----------------------------------------------------
        // Caso 6: derrota por tiempo NO incrementa
        // ----------------------------------------------------
        state = JUEGO;
        esperar_ciclos(1);

        state = PERDIO_TIEMPO;
        esperar_ciclos(2);

        comprobar(3, "derrota por tiempo no incrementa");

        // ----------------------------------------------------
        // Caso 7: reset borra el acumulado
        // ----------------------------------------------------
        rst = 1'b1;
        esperar_ciclos(2);

        comprobar(0, "reset borra partidas ganadas");

        rst = 1'b0;

        $display("");
        $display("============================================");

        if (errores == 0)
            $display("M06: TODOS LOS CASOS PASARON.");
        else
            $display("M06: SE ENCONTRARON %0d ERRORES.", errores);

        $display("============================================");

        #20;
        $finish;
    end

endmodule
