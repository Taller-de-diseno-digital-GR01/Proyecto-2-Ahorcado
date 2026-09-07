`timescale 1ns/1ps

module tb_M01_Marcador;

    logic clk;
    logic rst;

    logic [6:0] time;
    logic [6:0] num_ganadas;

    logic [6:0] seg;
    logic [3:0] an;
    logic       dp;

    integer errores;

    // Se usa un contador pequeño únicamente para acelerar la simulación.
    // El diseño real conserva REFRESH_BITS = 18.
    M01_Marcador #(
        .REFRESH_BITS(4)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .time        (time),
        .num_ganadas (num_ganadas),
        .seg         (seg),
        .an          (an),
        .dp          (dp)
    );


    // Clock de simulación: período = 10 ns
    always #5 clk = ~clk;


    // --------------------------------------------------------
    // Función auxiliar:
    // entrega el patrón esperado para un dígito decimal.
    // --------------------------------------------------------
    function automatic [6:0] seg_esperado(input integer digito);
        begin
            case (digito)
                0: seg_esperado = 7'b0000001;
                1: seg_esperado = 7'b1001111;
                2: seg_esperado = 7'b0010010;
                3: seg_esperado = 7'b0000110;
                4: seg_esperado = 7'b1001100;
                5: seg_esperado = 7'b0100100;
                6: seg_esperado = 7'b0100000;
                7: seg_esperado = 7'b0001111;
                8: seg_esperado = 7'b0000000;
                9: seg_esperado = 7'b0000100;
                default: seg_esperado = 7'b1111111;
            endcase
        end
    endfunction


    // --------------------------------------------------------
    // Comprueba una combinación determinada de an y seg
    // --------------------------------------------------------
    task automatic comprobar_salida(
        input [3:0] an_esperado,
        input integer digito_esperado
    );
        begin
            if (an !== an_esperado) begin
                $display(
                    "ERROR t=%0t: an=%b, esperado=%b",
                    $time, an, an_esperado
                );
                errores = errores + 1;
            end

            if (seg !== seg_esperado(digito_esperado)) begin
                $display(
                    "ERROR t=%0t: seg=%b, esperado=%b para digito %0d",
                    $time,
                    seg,
                    seg_esperado(digito_esperado),
                    digito_esperado
                );
                errores = errores + 1;
            end
            else begin
                $display(
                    "OK    t=%0t: an=%b seg=%b -> digito %0d",
                    $time, an, seg, digito_esperado
                );
            end
        end
    endtask


    // --------------------------------------------------------
    // Espera hasta que aparezca cierto ánodo y comprueba
    // el dígito mostrado.
    // --------------------------------------------------------
    task automatic esperar_y_comprobar(
        input [3:0] an_objetivo,
        input integer digito_esperado
    );
        begin
            wait (an == an_objetivo);
            #1;
            comprobar_salida(an_objetivo, digito_esperado);

            // Evita comprobar dos veces el mismo período de refresco.
            wait (an != an_objetivo);
        end
    endtask


    // --------------------------------------------------------
    // Prueba completa de un valor de tiempo y de ganadas
    // --------------------------------------------------------
    task automatic probar_valores(
        input integer tiempo_prueba,
        input integer ganadas_prueba
    );
        integer t_decenas;
        integer t_unidades;
        integer g_decenas;
        integer g_unidades;
        begin
            time        = tiempo_prueba;
            num_ganadas = ganadas_prueba;

            // Esperar a que los registros internos capturen los datos
            @(posedge clk);
            @(posedge clk);

            t_decenas  = tiempo_prueba / 10;
            t_unidades = tiempo_prueba % 10;

            g_decenas  = ganadas_prueba / 10;
            g_unidades = ganadas_prueba % 10;

            $display("");
            $display("--------------------------------------------");
            $display(
                "Probando time=%0d, num_ganadas=%0d",
                tiempo_prueba, ganadas_prueba
            );
            $display("--------------------------------------------");

            // AN0 = unidades de ganadas
            esperar_y_comprobar(4'b1110, g_unidades);

            // AN1 = decenas de ganadas
            esperar_y_comprobar(4'b1101, g_decenas);

            // AN2 = unidades de tiempo
            esperar_y_comprobar(4'b1011, t_unidades);

            // AN3 = decenas de tiempo
            esperar_y_comprobar(4'b0111, t_decenas);
        end
    endtask


    initial begin

        $dumpfile("tb_M01_Marcador.vcd");
        $dumpvars(0, tb_M01_Marcador);

        clk         = 1'b0;
        rst         = 1'b1;
        time        = 7'd0;
        num_ganadas = 7'd0;
        errores     = 0;

        // Reset
        repeat (3) @(posedge clk);
        rst = 1'b0;

        // ----------------------------------------------------
        // CASO 1
        // Tiempo = 45 segundos
        // Ganadas = 07
        //
        // Display esperado:
        // AN3 AN2 AN1 AN0
        //  4   5   0   7
        // ----------------------------------------------------
        probar_valores(45, 7);

        // ----------------------------------------------------
        // CASO 2
        // Tiempo = 60 segundos
        // Ganadas = 12
        //
        // Display esperado:
        //  6   0   1   2
        // ----------------------------------------------------
        probar_valores(60, 12);

        // ----------------------------------------------------
        // CASO 3
        // Tiempo = 09 segundos
        // Ganadas = 25
        //
        // Display esperado:
        //  0   9   2   5
        // ----------------------------------------------------
        probar_valores(9, 25);

        // ----------------------------------------------------
        // CASO 4
        // Tiempo = 00
        // Ganadas = 99
        //
        // Display esperado:
        //  0   0   9   9
        // ----------------------------------------------------
        probar_valores(0, 99);

        $display("");
        $display("============================================");

        if (errores == 0)
            $display("TEST FINALIZADO: TODOS LOS CASOS PASARON.");
        else
            $display(
                "TEST FINALIZADO: SE ENCONTRARON %0d ERRORES.",
                errores
            );

        $display("============================================");

        #50;
        $finish;
    end

endmodule
