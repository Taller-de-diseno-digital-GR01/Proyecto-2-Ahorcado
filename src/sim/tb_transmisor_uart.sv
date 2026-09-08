`timescale 1ns/1ps

// Testbench de transmisor_uart. Corre con: make sim TB=transmisor_uart (o make wave TB=transmisor_uart)
//
// No se instancia la UART real (UART/src/UART_tx.vhd): el testbench hace de "UART" a mano,
// contestando i_tx_rdy cuando le da la gana, para poder probar el handshake tx_start/tx_data/tx_rdy
// del lado de transmisor_uart sin meter VHDL a la simulación.
//
// Nota sobre el estilo: igual que tb_temporizador, las comprobaciones se escriben como macros de
// preprocesador (`define), no como task/function, por el mismo problema de Icarus Verilog
// documentado allá (una llamada a task/function dentro de un initial le come el siguiente
// @(posedge clk) del mismo proceso).
module tb_transmisor_uart;

    logic       clk;
    logic       rst;
    logic [2:0] i_state;
    logic       i_modo;
    logic [1:0] i_letra_state;
    logic       i_letra_lista;
    logic [2:0] i_try;
    logic [3:0] i_word_length;
    logic       i_tx_rdy;

    logic       o_tx_start;
    logic [7:0] o_tx_data;

    int errores = 0;

    transmisor_uart dut (
        .clk(clk),
        .rst(rst),
        .i_state(i_state),
        .i_modo(i_modo),
        .i_letra_state(i_letra_state),
        .i_letra_lista(i_letra_lista),
        .i_try(i_try),
        .i_word_length(i_word_length),
        .i_tx_rdy(i_tx_rdy),
        .o_tx_start(o_tx_start),
        .o_tx_data(o_tx_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Volcado de ondas para GTKWave. Ruta relativa porque el target 'sim' del Makefile hace
    // "cd src/build && vvp ..." antes de correr esto, así que vvp ya arranca con cwd=src/build/;
    // si se pusiera "src/build/tb_transmisor_uart.vcd" acá, quedaría src/build/src/build/...
    initial begin
        $dumpfile("tb_transmisor_uart.vcd");
        $dumpvars(0, tb_transmisor_uart);
    end

    // Códigos de estado, mismos que docs/diseño/modulos/M13_FSM.md, h
    localparam SELECCION = 3'b000;
    localparam JUEGO = 3'b010;
    localparam GANO = 3'b011;
    localparam PERDIO_INTENTOS = 3'b100;

    // Códigos de letra_state, mismo contrato que M07_Comparador-letra
    localparam FALLO = 2'b00;
    localparam ACIERTO = 2'b01;
    localparam REPETIDA = 2'b10;

    `define CHECK(nombre, got, expected) \
        if ((got) !== (expected)) begin \
            $display("FALLO [%0t ns] %s: se esperaba %02h, se obtuvo %02h", $time, nombre, (expected), (got)); \
            errores = errores + 1; \
        end else begin \
            $display("OK    [%0t ns] %s: %02h", $time, nombre, (got)); \
        end

    // Espera a que el DUT pida transmitir (o_tx_start=1), dejando el reloj asentado con #1
    `define ESPERA_TX_START \
        while (!o_tx_start) begin \
            @(posedge clk); #1; \
        end

    // Recibe un byte de la trama: espera tx_start, revisa tx_data, y contesta con un pulso de tx_rdy
    `define RECIBE_BYTE(nombre, esperado) \
        `ESPERA_TX_START \
        `CHECK(nombre, o_tx_data, esperado) \
        @(posedge clk); #1; \
        i_tx_rdy = 1'b1; \
        @(posedge clk); #1; \
        i_tx_rdy = 1'b0;

    initial begin
        i_state = SELECCION;
        i_modo = 1'b0;
        i_letra_state = FALLO;
        i_letra_lista = 1'b0;
        i_try = 3'd0;
        i_word_length = 4'd0;
        i_tx_rdy = 1'b0;

        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;

        // 1) En reposo, sin ningún evento, no debe pedir transmitir nada
        if (o_tx_start !== 1'b0) begin
            $display("FALLO [%0t ns] reset: o_tx_start no deberia estar en 1", $time);
            errores = errores + 1;
        end else begin
            $display("OK    [%0t ns] reset: o_tx_start en reposo", $time);
        end

        // 2) Entrada a JUEGO: trama INICIO con modo y word_length
        i_modo = 1'b1;
        i_word_length = 4'd7;
        i_state = JUEGO;
        `RECIBE_BYTE("INICIO byte0 (cabecera 'I')", 8'h49)
        `RECIBE_BYTE("INICIO byte1 (modo)", 8'h01)
        `RECIBE_BYTE("INICIO byte2 (word_length)", 8'h07)

        // 3) Letra acertada: trama LETRA con letra_state y try
        i_try = 3'd2;
        i_letra_state = ACIERTO;
        i_letra_lista = 1'b1;
        @(posedge clk); #1;
        i_letra_lista = 1'b0;
        `RECIBE_BYTE("LETRA acierto byte0 (cabecera 'L')", 8'h4C)
        `RECIBE_BYTE("LETRA acierto byte1 (letra_state)", 8'h01)
        `RECIBE_BYTE("LETRA acierto byte2 (try)", 8'h02)

        // 4) Letra repetida: también manda trama (no se descarta), con el mismo formato
        i_letra_state = REPETIDA;
        i_letra_lista = 1'b1;
        @(posedge clk); #1;
        i_letra_lista = 1'b0;
        `RECIBE_BYTE("LETRA repetida byte0 (cabecera 'L')", 8'h4C)
        `RECIBE_BYTE("LETRA repetida byte1 (letra_state)", 8'h02)
        `RECIBE_BYTE("LETRA repetida byte2 (try)", 8'h02)

        // 5) Entrada a un estado de fin: trama FIN con la causa, sin tercer byte
        i_state = GANO;
        `RECIBE_BYTE("FIN byte0 (cabecera 'F')", 8'h46)
        `RECIBE_BYTE("FIN byte1 (causa=GANO)", 8'h03)

        // 6) Prioridad: una letra nueva y un fin de partida pendientes al mismo tiempo.
        //    Primero se vuelve a un estado que no es ni JUEGO ni fin (para no arrastrar un
        //    pulso_ini/pulso_fin viejo), y luego se disparan letra y fin juntos en el mismo ciclo.
        i_state = SELECCION;
        @(posedge clk); #1;

        i_state = PERDIO_INTENTOS;
        i_try = 3'd4;
        i_letra_state = FALLO;
        i_letra_lista = 1'b1;
        @(posedge clk); #1;
        i_letra_lista = 1'b0;

        // El fin de partida tiene que salir primero...
        `RECIBE_BYTE("prioridad: FIN byte0 (cabecera 'F')", 8'h46)
        `RECIBE_BYTE("prioridad: FIN byte1 (causa=PERDIO_INTENTOS)", 8'h04)
        // ...y la letra que quedo pendiente se manda despues, no se pierde.
        `RECIBE_BYTE("prioridad: LETRA byte0 (cabecera 'L')", 8'h4C)
        `RECIBE_BYTE("prioridad: LETRA byte1 (letra_state=FALLO)", 8'h00)
        `RECIBE_BYTE("prioridad: LETRA byte2 (try)", 8'h04)

        // 7) Ya sin pendientes, se queda en reposo
        repeat (5) @(posedge clk);
        #1;
        if (o_tx_start !== 1'b0) begin
            $display("FALLO [%0t ns] reposo final: o_tx_start no deberia estar en 1", $time);
            errores = errores + 1;
        end else begin
            $display("OK    [%0t ns] reposo final: o_tx_start en reposo", $time);
        end

        if (errores == 0)
            $display("\n=== TODAS LAS PRUEBAS PASARON ===");
        else
            $display("\n=== %0d PRUEBA(S) FALLARON ===", errores);

        $finish;
    end

endmodule
