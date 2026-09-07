`timescale 1ns/1ps

// Testbench de temporizador. Corre con: make sim TB=temporizador (o make wave TB=temporizador)
//
// PRESCALER_RECARGA se sobreescribe a un valor chico (ver PRESC_TEST) para que un "segundo"
// del DUT dure unos pocos ciclos de clk en vez de 100_000_000 -- así se puede simular una
// cuenta regresiva completa (60 s, 45 s) sin esperar minutos de tiempo simulado real.
//
// Nota sobre el estilo: las comprobaciones y la espera de un tick se escriben como macros de
// preprocesador (`define), no como task/function. Se probo con task/function normales primero,
// pero en Icarus Verilog (probado en la version estable 12.0 y en la ultima de desarrollo) CUALQUIER
// llamada a una tarea o funcion dentro del bloque initial corrompe el siguiente @(posedge clk) del
// mismo proceso (el proceso "pierde" un flanco) -- reproducido de forma aislada y minimal, incluso
// con una tarea vacia que solo hace $display. Las macros no tienen ese problema porque son
// sustitucion de texto en tiempo de compilacion, no una llamada real en tiempo de simulacion.
module tb_temporizador;

    localparam logic [26:0] PRESC_TEST = 27'd3; // tick_1hz cada 4 ciclos de clk (cuenta 3,2,1,0)

    logic       clk;
    logic       rst;
    logic       start;
    logic       modo;
    logic [7:0] tiempo;
    logic       tiempo_agotado;

    int errores = 0;

    temporizador #(
        .PRESCALER_RECARGA(PRESC_TEST)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .modo(modo),
        .tiempo(tiempo),
        .tiempo_agotado(tiempo_agotado)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Empaqueta un valor decimal 0-99 al formato BCD {decenas, unidades} de la salida `tiempo`
    `define BCD(valor) {4'((valor) / 10), 4'((valor) % 10)}

    `define CHECK(nombre, got, expected) \
        if ((got) !== (expected)) begin \
            $display("FALLO [%0t ns] %s: se esperaba tiempo=%02h, se obtuvo %02h", $time, nombre, (expected), (got)); \
            errores = errores + 1; \
        end else begin \
            $display("OK    [%0t ns] %s: tiempo=%02h", $time, nombre, (got)); \
        end

    `define CHECK_BIT(nombre, got, expected) \
        if ((got) !== (expected)) begin \
            $display("FALLO [%0t ns] %s: se esperaba %0b, se obtuvo %0b", $time, nombre, (expected), (got)); \
            errores = errores + 1; \
        end else begin \
            $display("OK    [%0t ns] %s: %0b", $time, nombre, (got)); \
        end

    // Avanza exactamente un periodo de tick_1hz (PRESC_TEST+1 ciclos de clk). El prescaler
    // corre libre, sin resincronizarse con start, asi que el periodo entre pulsos siempre es
    // el mismo sin importar cuando ocurrio el ultimo start -- basta con esperar un periodo
    // completo para garantizar que paso exactamente un tick_1hz.
    //
    // El "#1" final es para dejar asentar las actualizaciones NBA antes de leer cualquier señal
    // del DUT justo despues: en pruebas se vio que, en este build de Icarus Verilog, leer una
    // señal en el mismo instante de simulacion que el flanco que la actualiza a veces devuelve
    // el valor viejo (no es un problema del diseño, sino de cuando el testbench lee el valor).
    `define ESPERA_TICK repeat (PRESC_TEST + 1) @(posedge clk); #1;

    initial begin
        $dumpfile("tb_temporizador.vcd");
        $dumpvars(0, tb_temporizador);

        // 1) Reset: tiempo en 0, tiempo_agotado en 0
        rst = 1'b1; start = 1'b0; modo = 1'b0;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;
        `CHECK("reset: tiempo", tiempo, `BCD(0))
        `CHECK_BIT("reset: tiempo_agotado", tiempo_agotado, 1'b0)

        // 2) Sin start, tiempo se queda en 0 y tiempo_agotado NO debe activarse solo:
        //    corrige el caso de "agotado falso" apenas sale del reset, antes de correr nunca.
        `ESPERA_TICK
        `ESPERA_TICK
        `CHECK("idle sin start: tiempo", tiempo, `BCD(0))
        `CHECK_BIT("idle sin start: tiempo_agotado", tiempo_agotado, 1'b0)

        // 3) start en modo facil (0) carga 60 s
        modo  = 1'b0;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        `CHECK("start facil: tiempo inicial", tiempo, `BCD(60))
        `CHECK_BIT("start facil: tiempo_agotado limpio", tiempo_agotado, 1'b0)

        // 4) Cuenta regresiva completa 60 -> 0, revisando el acarreo BCD en cada decena
        for (int i = 59; i >= 0; i = i - 1) begin
            `ESPERA_TICK
            `CHECK($sformatf("cuenta facil: %0d s restantes", i), tiempo, `BCD(i))
        end

        // 5) Al llegar a 0: tiempo_agotado se levanta, running se apaga solo y el tiempo
        //    ya no sigue bajando (no da la vuelta a 99).
        //    running/tiempo_agotado usan el "zero" del ciclo anterior, asi que reflejan el
        //    tiempo=0 recien escrito un ciclo de clk despues -- de ahi este @(posedge clk) extra.
        @(posedge clk); #1;
        `CHECK_BIT("fin de cuenta: tiempo_agotado", tiempo_agotado, 1'b1)
        `CHECK_BIT("fin de cuenta: running se apago solo", dut.running, 1'b0)
        `ESPERA_TICK
        `ESPERA_TICK
        `CHECK("fin de cuenta: tiempo se mantiene en 0", tiempo, `BCD(0))
        `CHECK_BIT("fin de cuenta: tiempo_agotado se mantiene", tiempo_agotado, 1'b1)

        // 6) Un nuevo start en modo dificil (1) recarga con 45 s y limpia tiempo_agotado
        modo  = 1'b1;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        `CHECK("start dificil: tiempo inicial", tiempo, `BCD(45))
        `CHECK_BIT("start dificil: tiempo_agotado se limpia", tiempo_agotado, 1'b0)

        // 7) Reiniciar a mitad de cuenta (start con running=1) vuelve a cargar el tiempo
        `ESPERA_TICK
        `ESPERA_TICK
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        `CHECK("restart a mitad de cuenta", tiempo, `BCD(45))

        // 8) Cuenta regresiva completa en modo dificil, cruzando otra decena (45 -> 40 -> ... -> 0)
        for (int i = 44; i >= 0; i = i - 1) begin
            `ESPERA_TICK
            `CHECK($sformatf("cuenta dificil: %0d s restantes", i), tiempo, `BCD(i))
        end
        @(posedge clk); #1; // ver nota de sincronizacion en la seccion 5
        `CHECK_BIT("fin de cuenta dificil: tiempo_agotado", tiempo_agotado, 1'b1)

        // 9) rst limpia todo de nuevo, incluso con tiempo_agotado en alto.
        //    Se mantiene 2 ciclos (igual que el reset inicial) para evitar una carrera entre
        //    el "rst=0" del testbench y el flanco en el que el DUT todavia debe ver rst=1.
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;
        `CHECK("rst final: tiempo", tiempo, `BCD(0))
        `CHECK_BIT("rst final: tiempo_agotado", tiempo_agotado, 1'b0)

        if (errores == 0)
            $display("\n=== TODAS LAS PRUEBAS PASARON ===");
        else
            $display("\n=== %0d PRUEBA(S) FALLARON ===", errores);

        $finish;
    end

endmodule
