`timescale 1ns/1ps

// Testbench del sistema completo pensado para la simulacion temporizada de Vivado
// (Post-Synthesis / Post-Implementation Timing Simulation), aunque tambien corre sobre el RTL
// con make sim TB=top_timesim.
//
// Diferencia con tb_top: en el netlist temporizado las senales internas ya no existen con su
// nombre (bank_word desaparece al plegarse la ROM en LUT, word y state quedan recortados), asi que
// aca NO se usa ninguna referencia jerarquica dut.* ni force. Todo se observa por los puertos:
// la letra entra como trama serial por rx_i y la validacion se comprueba decodificando en tx_o
// las tramas que la FPGA le manda a la PC (seccion 7.2 del informe).
//
// Como la palabra la escoge el LFSR y no se fuerza, la prueba no asume cual es. Comprueba lo que
// vale para cualquier palabra:
//   - la trama INICIO trae modo FACIL y una longitud valida (4 a 12)
//   - un byte que no es A-Z se descarta: no genera respuesta
//   - la primera 'A' se valida: trama LETRA con acierto o fallo, fallos coherentes con el
//     resultado y la mascara rellena con 1 por encima de la longitud
//   - la segunda 'A' sale como repetida y no cambia ni los fallos ni la mascara
//
// N_DEBOUNCE tiene que coincidir con el valor con que se sintetizo el top: en RTL es el 21 por
// defecto, y para la simulacion temporizada se implementa con uno menor y se le pasa al
// testbench con xelab -generic_top "N_DEBOUNCE=12". No se le pasa al dut porque el top del
// netlist ya no tiene parametros.
module tb_top_timesim #(
    parameter int N_DEBOUNCE = 21
);

    logic clk;
    logic rst;
    logic btn_sel;
    logic btn_ok;
    logic rx_i;

    logic        tx_o;
    logic        lcd_rs_o;
    logic        lcd_rw_o;
    logic        lcd_e_o;
    logic [7:0]  lcd_data_o;
    logic [6:0]  seg;
    logic [3:0]  an;
    logic        dp;
    logic [1:0]  state_led;
    logic        buzzer;

    int pruebas = 0;
    int errores = 0;

    top dut (
        .clk       (clk),
        .rst       (rst),
        .btn_sel   (btn_sel),
        .btn_ok    (btn_ok),
        .rx_i      (rx_i),
        .tx_o      (tx_o),
        .lcd_rs_o  (lcd_rs_o),
        .lcd_rw_o  (lcd_rw_o),
        .lcd_e_o   (lcd_e_o),
        .lcd_data_o(lcd_data_o),
        .seg       (seg),
        .an        (an),
        .dp        (dp),
        .state_led (state_led),
        .buzzer    (buzzer)
    );

    always #5 clk = ~clk;

    // Debounce de botones.sv, mismo calculo que tb_top.sv
    localparam int CICLOS_DEBOUNCE = (1 << (N_DEBOUNCE - 1)) + 20;

    // Baudaje: el nucleo RX muestrea con TICKS_X16=54 y el TX usa TICKS_BIT=868
    localparam int CICLOS_BIT_RX = 54 * 16;
    localparam int CICLOS_BIT_TX = 868;

    // Espera maxima de una respuesta: 5 bytes de 10 bits mas margen para el sondeo del bus
    localparam int CICLOS_RESPUESTA = 60 * CICLOS_BIT_TX;

    localparam logic [7:0] CAB_INICIO = 8'h49; // 'I'
    localparam logic [7:0] CAB_LETRA  = 8'h4C; // 'L'

    localparam logic [1:0] FALLO    = 2'b00;
    localparam logic [1:0] ACIERTO  = 2'b01;
    localparam logic [1:0] REPETIDA = 2'b10;

    task automatic anotar(input string nombre, input bit ok);
        pruebas++;
        if (ok) $display("OK    [%0t ns] %s", $time, nombre);
        else begin
            errores++;
            $display("FALLO [%0t ns] %s", $time, nombre);
        end
    endtask

    // Los estimulos cambian en el flanco de bajada, lejos del flanco activo, para no violar
    // setup/hold de los flip-flops de entrada en la simulacion con retardos
    task automatic enviar_byte(input logic [7:0] b);
        @(negedge clk);
        rx_i = 1'b0;
        repeat (CICLOS_BIT_RX) @(negedge clk);
        for (int i = 0; i < 8; i++) begin
            rx_i = b[i];
            repeat (CICLOS_BIT_RX) @(negedge clk);
        end
        rx_i = 1'b1;
        repeat (CICLOS_BIT_RX) @(negedge clk);
    endtask

    // Monitor de tx_o: hace de la PC y guarda cada byte recibido en una cola
    logic [7:0] rx_pc [$];

    initial begin : monitor_tx
        logic [7:0] b;
        forever begin
            @(negedge tx_o);
            repeat (CICLOS_BIT_TX / 2) @(posedge clk); // mitad del bit de arranque
            if (tx_o === 1'b0) begin                   // si no, fue un glitch y no un arranque
                for (int i = 0; i < 8; i++) begin
                    repeat (CICLOS_BIT_TX) @(posedge clk);
                    b[i] = tx_o;
                end
                repeat (CICLOS_BIT_TX) @(posedge clk); // bit de parada
                rx_pc.push_back(b);
            end
        end
    end

    // Espera hasta tener n bytes en la cola o hasta agotar el tiempo
    task automatic esperar_bytes(input int n, output bit llegaron);
        int espera = 0;
        while (rx_pc.size() < n && espera < CICLOS_RESPUESTA) begin
            @(posedge clk);
            espera++;
        end
        llegaron = (rx_pc.size() >= n);
    endtask

    logic [7:0]  trama [5];
    logic [3:0]  longitud;
    logic [11:0] relleno;
    logic [1:0]  resultado1;
    logic [2:0]  fallos1;
    logic [11:0] mascara1;
    bit          llegaron;

    initial begin
        clk     = 1'b0;
        rst     = 1'b1;
        btn_sel = 1'b0;
        btn_ok  = 1'b0;
        rx_i    = 1'b1; // linea serial en reposo

        // En el netlist de Vivado el GSR mantiene todo en reset los primeros 100 ns; el rst se
        // sostiene mas que eso para que el reset sincronico del diseño tambien se aplique
        repeat (20) @(negedge clk);
        rst = 1'b0;
        repeat (20) @(negedge clk);
        anotar("tras el reset tx_o queda en reposo", tx_o === 1'b1);

        // Pulsa btn_ok el tiempo suficiente para pasar el debounce real
        btn_ok = 1'b1;
        repeat (CICLOS_DEBOUNCE) @(negedge clk);
        btn_ok = 1'b0;

        // --- trama INICIO ---
        esperar_bytes(3, llegaron);
        anotar("al entrar a JUEGO la FPGA manda la trama INICIO de 3 bytes", llegaron);
        if (!llegaron) begin
            $display("\n%0d pruebas, %0d fallos", pruebas, errores);
            $fatal(1, "sin trama INICIO no se puede seguir");
        end
        for (int i = 0; i < 3; i++) trama[i] = rx_pc.pop_front();
        longitud = trama[2][3:0];
        anotar("la cabecera es 'I'", trama[0] === CAB_INICIO);
        anotar("el modo es FACIL (sin tocar btn_sel)", trama[1] === 8'h00);
        anotar("la longitud esta entre 4 y 12", longitud >= 4 && longitud <= 12);
        $display("      palabra de %0d letras", longitud);

        relleno = ~((12'd1 << longitud) - 12'd1); // 1 en las posiciones por encima de la longitud

        // --- byte que no es letra mayuscula ---
        enviar_byte("1");
        esperar_bytes(1, llegaron);
        anotar("un '1' se descarta: la FPGA no responde", !llegaron);

        enviar_byte("a");
        esperar_bytes(1, llegaron);
        anotar("una 'a' minuscula tambien se descarta", !llegaron);

        // --- primera A: recepcion y validacion ---
        enviar_byte("A");
        esperar_bytes(5, llegaron);
        anotar("la 'A' produce una trama LETRA de 5 bytes", llegaron);
        if (llegaron) begin
            for (int i = 0; i < 5; i++) trama[i] = rx_pc.pop_front();
            resultado1 = trama[1][1:0];
            fallos1    = trama[2][2:0];
            mascara1   = {trama[4][3:0], trama[3]};
            $display("      resultado=%b fallos=%0d mascara=%b", resultado1, fallos1, mascara1);
            anotar("la cabecera es 'L'", trama[0] === CAB_LETRA);
            anotar("la primera 'A' sale como acierto o fallo, nunca repetida",
                   resultado1 === ACIERTO || resultado1 === FALLO);
            anotar("fallos es 1 si fue fallo y 0 si fue acierto",
                   fallos1 === ((resultado1 === FALLO) ? 3'd1 : 3'd0));
            anotar("la mascara viene rellena con 1 por encima de la longitud",
                   (mascara1 & relleno) === relleno);
            anotar("si fue acierto se revelo al menos una posicion, si fue fallo ninguna",
                   (resultado1 === ACIERTO) ? ((mascara1 & ~relleno) !== 12'd0)
                                            : ((mascara1 & ~relleno) === 12'd0));
        end

        // --- segunda A: repetida ---
        enviar_byte("A");
        esperar_bytes(5, llegaron);
        anotar("la 'A' repetida tambien responde con una trama LETRA", llegaron);
        if (llegaron) begin
            for (int i = 0; i < 5; i++) trama[i] = rx_pc.pop_front();
            anotar("el resultado es repetida", trama[1][1:0] === REPETIDA);
            anotar("la repetida no gasta intento", trama[2][2:0] === fallos1);
            anotar("la repetida no cambia la mascara", {trama[4][3:0], trama[3]} === mascara1);
        end

        $display("\n%0d pruebas, %0d fallos", pruebas, errores);
        if (errores != 0) $fatal(1, "tb_top_timesim termino con fallos");
        else $display("=== TODAS LAS PRUEBAS PASARON ===");
        $finish;
    end

endmodule
