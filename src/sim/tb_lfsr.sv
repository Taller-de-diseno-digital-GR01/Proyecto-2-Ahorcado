`timescale 1ns/1ps

// Testbench de lfsr. Corre con: make sim TB=lfsr (o make wave TB=lfsr)
//
// A diferencia de M02/M03/M11, acá no hace falta achicar ningún parámetro para simular rápido:
// el período del LFSR ya es de solo 63 ciclos con los valores de producción. No se instancia
// ningún REG_WBank real: el propio testbench hace de "ROM" combinacional, devolviendo en
// i_bank_word la dirección que el DUT pida en o_bank_addr (con relleno de ceros), así que
// después de una captura o_word[5:0] dice exactamente qué dirección quedó escogida, sin
// necesitar un banco de palabras real para la prueba.
//
// Nota sobre el estilo: igual que los demás testbenches del proyecto, las comprobaciones se
// escriben como macros de preprocesador (`define), no como task/function, por el problema de
// Icarus Verilog ya documentado en tb_temporizador.
module tb_lfsr;

    logic       clk;
    logic       rst;
    logic [2:0] i_state;
    logic       i_modo;
    logic [78:0] i_bank_word;

    logic [5:0] o_bank_addr;
    logic [78:0] o_word;
    logic       o_valid_word;

    int errores = 0;

    lfsr dut (
        .clk(clk),
        .rst(rst),
        .i_state(i_state),
        .i_modo(i_modo),
        .i_bank_word(i_bank_word),
        .o_bank_addr(o_bank_addr),
        .o_word(o_word),
        .o_valid_word(o_valid_word)
    );

    // "ROM" de prueba: devuelve la propia dirección pedida, con relleno de ceros
    assign i_bank_word = {73'b0, o_bank_addr};

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Códigos de estado, mismos que docs/diseño/modulos/M13_FSM.md, h
    localparam JUEGO = 3'b010; // "neutro": dec_carga=0
    localparam CARGA = 3'b001;

    localparam N_PALABRAS = 50;
    localparam N_PALABRAS_DIFICIL = 20;

    `define CHECK_BIT(nombre, got, expected) \
        if ((got) !== (expected)) begin \
            $display("FALLO [%0t ns] %s: se esperaba %0b, se obtuvo %0b", $time, nombre, (expected), (got)); \
            errores = errores + 1; \
        end else begin \
            $display("OK    [%0t ns] %s: %0b", $time, nombre, (got)); \
        end

    `define CHECK(nombre, got, expected) \
        if ((got) !== (expected)) begin \
            $display("FALLO [%0t ns] %s: se esperaba %0d, se obtuvo %0d", $time, nombre, (expected), (got)); \
            errores = errores + 1; \
        end else begin \
            $display("OK    [%0t ns] %s: %0d", $time, nombre, (got)); \
        end

    // Lleva state de JUEGO a CARGA, dejando pasar un ciclo primero para que dec_carga_prev se
    // asiente en 0 y la entrada a CARGA sea un flanco de verdad (mismo patrón que M02/M11)
    `define ENTRA_A_CARGA \
        i_state = JUEGO; \
        @(posedge clk); #1; \
        i_state = CARGA; \
        @(posedge clk); #1;

    int i;
    logic [63:0] visto; // un bit por valor posible del LFSR (1-63), para detectar repetidos
    logic [5:0] val;
    logic [5:0] direccion;
    logic [5:0] semilla_periodo;
    logic found;

    initial begin
        i_state = JUEGO;
        i_modo = 1'b0;

        rst = 1'b1;
        repeat (2) @(posedge clk);
        #1;

        // 1) La semilla tras rst es no nula (todo-ceros es punto fijo del XOR puro). Se revisa
        //    acá, todavía con rst en alto, porque el LFSR ya corre libre en cuanto rst baja --
        //    un @(posedge clk) más y ya habría avanzado un desplazamiento.
        `CHECK("reset: semilla del LFSR", dut.reg_lfsr, 6'b000001)
        rst = 1'b0;

        // 2) Período máximo: corre libre en JUEGO (no depende de state), nunca pasa por 0, y
        //    visita los 63 valores no nulos exactamente una vez antes de volver al punto de
        //    partida (se compara contra semilla_periodo, no contra la constante 1, porque un
        //    LFSR de período máximo vuelve a SU propio punto de partida, sea cual sea).
        semilla_periodo = dut.reg_lfsr;
        visto = 64'b0;
        visto[semilla_periodo] = 1'b1;
        for (i = 1; i <= 63; i = i + 1) begin
            @(posedge clk); #1;
            val = dut.reg_lfsr;
            `CHECK_BIT($sformatf("periodo: ciclo %0d no es cero", i), (val != 6'b0), 1'b1)
            if (i < 63) begin
                `CHECK_BIT($sformatf("periodo: ciclo %0d no se repite", i), visto[val], 1'b0)
                visto[val] = 1'b1;
            end
            else begin
                `CHECK("periodo: vuelve al punto de partida en el ciclo 63", val, semilla_periodo)
            end
        end

        // 3) Modo FACIL: la primera dirección válida que encuentra tiene que caer en 1-50
        i_modo = 1'b0;
        `ENTRA_A_CARGA
        found = 1'b0;
        for (i = 0; i < 70 && !found; i = i + 1) begin
            @(posedge clk); #1;
            if (o_valid_word) found = 1'b1;
        end
        `CHECK_BIT("facil: valid_word se levanta dentro de un periodo", found, 1'b1)
        direccion = o_word[5:0];
        `CHECK_BIT("facil: direccion capturada >= 1", (direccion >= 6'd1), 1'b1)
        `CHECK_BIT("facil: direccion capturada <= 50", (direccion <= N_PALABRAS[5:0]), 1'b1)

        // 4) pulso_carga limpia valid_word heredado: al volver a entrar a CARGA para la
        //    siguiente partida, valid_word cae a 0 de inmediato, antes de encontrar una
        //    direccion nueva.
        i_state = JUEGO;
        @(posedge clk); #1;
        i_state = CARGA;
        @(posedge clk); #1;
        `CHECK_BIT("pulso_carga: valid_word se limpia al reentrar a CARGA", o_valid_word, 1'b0)

        // 5) Modo DIFICIL: la primera direccion valida tiene que caer en el rango que arma
        //    ROM_IDX_DIFICIL con los parametros por defecto (placeholder: las ultimas
        //    N_PALABRAS_DIFICIL direcciones del banco, ver TODO en lfsr.sv)
        i_modo = 1'b1;
        found = 1'b0;
        for (i = 0; i < 70 && !found; i = i + 1) begin
            @(posedge clk); #1;
            if (o_valid_word) found = 1'b1;
        end
        `CHECK_BIT("dificil: valid_word se levanta dentro de un periodo", found, 1'b1)
        direccion = o_word[5:0];
        `CHECK_BIT("dificil: direccion capturada >= 31", (direccion >= (N_PALABRAS - N_PALABRAS_DIFICIL + 1)), 1'b1)
        `CHECK_BIT("dificil: direccion capturada <= 50", (direccion <= N_PALABRAS[5:0]), 1'b1)

        if (errores == 0)
            $display("\n=== TODAS LAS PRUEBAS PASARON ===");
        else
            $display("\n=== %0d PRUEBA(S) FALLARON ===", errores);

        $finish;
    end

endmodule
