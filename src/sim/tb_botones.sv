`timescale 1ns/1ps

// Testbench de botones (M09_Botones, src/design/botones.sv + debounce.sv). Corre con:
// make -f Makefile.windows sim TB=botones (o make wave TB=botones)
//
// botones.sv no expone N como parametro (lo fija internamente en 21 dentro de las dos
// instancias de debounce), asi que no hay forma de acortarlo desde este testbench sin tocar
// el RTL, cosa que no corresponde para poder correr rapido una prueba -- se simula el N=21
// real. Con N=21, debounce.sv solo actualiza button_out cuando su contador interno alcanza
// 2**(N-1) = 1 048 576 ciclos estables (bit N-1 del contador en 1), asi que cada escenario
// espera ese numero de ciclos de clk. Sigue siendo rapido de correr, son ciclos de
// simulacion, no tiempo real.
//
// En vez de intentar acertar el ciclo exacto del pulso de un elemento tan largo, se llevan
// contadores acumulados (cont_ok/cont_sel) de cuantas veces se vio cada pulso durante toda
// la corrida, y se revisa el incremento esperado despues de cada escenario -- mismo
// resultado, sin depender de acertar un ciclo puntual entre un millon.
module tb_botones;

    localparam int N = 21;                       // igual al fijado dentro de botones.sv
    localparam int DEBOUNCE_CYCLES = (1 << (N-1)) + 20; // 2**(N-1) mas margen

    logic clk;
    logic rst;
    logic btn_ok, btn_sel;
    logic btn_ok_pulse, btn_sel_pulse;

    int errores = 0;
    int cont_ok = 0;
    int cont_sel = 0;

    botones dut (
        .clk          (clk),
        .rst          (rst),
        .btn_ok       (btn_ok),
        .btn_sel      (btn_sel),
        .btn_ok_pulse (btn_ok_pulse),
        .btn_sel_pulse(btn_sel_pulse)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (btn_ok_pulse)  cont_ok  = cont_ok + 1;
        if (btn_sel_pulse) cont_sel = cont_sel + 1;
    end

    `define CHECK_EQ(nombre, got, expected) \
        if ((got) !== (expected)) begin \
            $display("FALLO [%0t ns] %s: se esperaba %0d, se obtuvo %0d", $time, nombre, (expected), (got)); \
            errores = errores + 1; \
        end else begin \
            $display("OK    [%0t ns] %s: %0d", $time, nombre, (got)); \
        end

    `define ESPERA_DEBOUNCE repeat (DEBOUNCE_CYCLES) @(posedge clk);

    initial begin
        btn_ok  = 1'b0;
        btn_sel = 1'b0;

        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;

        // 1) En reposo, sin presiones, sin pulsos todavia
        `CHECK_EQ("reset: cont_ok", cont_ok, 0)
        `CHECK_EQ("reset: cont_sel", cont_sel, 0)

        // 2) Presion limpia de btn_ok, sin rebote: un solo pulso tras el periodo de debounce
        btn_ok = 1'b1;
        `ESPERA_DEBOUNCE
        `CHECK_EQ("ok limpio: un pulso", cont_ok, 1)
        `CHECK_EQ("ok limpio: sel no se contamina", cont_sel, 0)

        // 3) Soltar btn_ok: el flanco de bajada del boton debounced no genera pulso, el
        //    detector de flanco de botones.sv solo dispara en subida
        btn_ok = 1'b0;
        `ESPERA_DEBOUNCE
        `CHECK_EQ("ok soltado: sin pulso nuevo", cont_ok, 1)

        // 4) Presion con rebote de btn_sel: varias transiciones rapidas (muy por debajo del
        //    periodo de debounce) antes de asentarse en 1, deben verse como un solo pulso
        btn_sel = 1'b1; repeat (3) @(posedge clk);
        btn_sel = 1'b0; repeat (2) @(posedge clk);
        btn_sel = 1'b1; repeat (4) @(posedge clk);
        btn_sel = 1'b0; repeat (1) @(posedge clk);
        btn_sel = 1'b1; // queda asentado en 1 desde aqui
        `ESPERA_DEBOUNCE
        `CHECK_EQ("sel con rebote: un solo pulso", cont_sel, 1)
        `CHECK_EQ("sel con rebote: ok no se contamina", cont_ok, 1)

        // 5) Soltar btn_sel y esperar a que se asiente en 0 antes del siguiente escenario
        btn_sel = 1'b0;
        `ESPERA_DEBOUNCE

        // 6) Presion simultanea de ambos botones: cada uno dispara su propio pulso, sin
        //    interferirse entre si
        btn_ok  = 1'b1;
        btn_sel = 1'b1;
        `ESPERA_DEBOUNCE
        `CHECK_EQ("simultaneo: ok", cont_ok, 2)
        `CHECK_EQ("simultaneo: sel", cont_sel, 2)

        if (errores == 0)
            $display("\n=== TODAS LAS PRUEBAS PASARON ===");
        else
            $display("\n=== %0d PRUEBA(S) FALLARON ===", errores);

        $finish;
    end

endmodule
