`timescale 1ns/1ps

//Este Testbench valida el camino de juego completo (SELECCION -> CARGA -> JUEGO -> letra fallida -> letras correctas -> palabra completa -> GANO -> marcador incrementado), leyendo directo
// Se hardcodea la palabra carro.
//
// Alcance: valida el camino de juego completo (SELECCION -> CARGA -> JUEGO -> letra fallida ->
// letras correctas -> palabra completa -> GANO -> marcador incrementado), leyendo directo
// señales internas del DUT (dut.state, dut.mascara, etc.), igual que ya hace tb_lfsr.sv con
// dut.reg_lfsr. No verifica el contenido del LCD, del tono ni de la trama UART hacia la PC (cada
// uno ya tiene su propio testbench de modulo), ni espera los 3 s de fin_espera: M06_Ganadas ya
// incrementa num_ganadas en el mismo ciclo que se entra a GANO, sin necesitar esa espera.
module tb_top;

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

    // Codigos de estado de la fsm principal (docs/diseño/modulos/M13_FSM.md, h / fsm.sv)
    localparam logic [2:0] ST_SELECCION = 3'b000;
    localparam logic [2:0] ST_JUEGO     = 3'b010;
    localparam logic [2:0] ST_GANO      = 3'b011;

    // Debounce real de debounce.sv (N=21, fijo dentro de botones.sv), mismo calculo que
    // tb_botones.sv: 2**(N-1) ciclos estables mas margen
    localparam int N_DEBOUNCE      = 21;
    localparam int CICLOS_DEBOUNCE = (1 << (N_DEBOUNCE - 1)) + 20;

    // Baudaje real de periferico_uart (TICKS_X16=54 por defecto), mismo calculo que
    // tb_receptor_uart.sv
    localparam int CICLOS_BIT = 54 * 16;

    // Palabra de prueba fija "CARRO" (5 letras: C A R R O), mismo formato que empaqueta lfsr
    localparam logic [63:0] PALABRA_CARRO = {
        4'd5,                                     // longitud = 5
        5'd0, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0, // letra12..letra6, sin usar
        5'd14,                                     // letra5 = O
        5'd17,                                     // letra4 = R
        5'd17,                                     // letra3 = R
        5'd0,                                      // letra2 = A
        5'd2                                       // letra1 = C
    };

    task automatic anotar(input string nombre, input bit ok);
        pruebas++;
        if (ok) $display("OK    [%0t ns] %s", $time, nombre);
        else begin
            errores++;
            $display("FALLO [%0t ns] %s", $time, nombre);
        end
    endtask

    // Un bit por vez sobre rx_i: start en cero, ocho de dato (menos significativo primero), stop
    // en uno -- mismo patron que la tarea "serial" de tb_receptor_uart.sv
    task automatic enviar_letra(input logic [7:0] b);
        rx_i = 1'b0;
        repeat (CICLOS_BIT) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            rx_i = b[i];
            repeat (CICLOS_BIT) @(posedge clk);
        end
        rx_i = 1'b1;
        repeat (CICLOS_BIT) @(posedge clk);
    endtask

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

    initial begin
        clk     = 1'b0;
        rst     = 1'b1;
        btn_sel = 1'b0;
        btn_ok  = 1'b0;
        rx_i    = 1'b1; // linea serial en reposo

        // Fuerza una palabra conocida sin depender de que direccion escoja el LFSR
        // pseudoaleatorio, para que el resto del camino (JUEGO -> letras -> GANO) sea
        // determinista en la prueba, igual que antes de integrar el banco real.
        force dut.bank_word = PALABRA_CARRO;

        repeat (5) @(posedge clk);
        anotar("tras rst la fsm arranca en SELECCION", dut.state === ST_SELECCION);
        rst = 1'b0;

        // Pulsa btn_ok el tiempo suficiente para pasar el debounce real
        btn_ok = 1'b1;
        repeat (CICLOS_DEBOUNCE) @(posedge clk);
        btn_ok = 1'b0;

        repeat (20) @(posedge clk);
        anotar("ok confirmado, lfsr valida la palabra forzada y la fsm entra a JUEGO",
               dut.state === ST_JUEGO);
        anotar("lfsr capturo exactamente la palabra forzada", dut.word === PALABRA_CARRO);

        // Letra que no esta en CARRO, ejercita contador_intentos
        enviar_letra("Z");
        repeat (10) @(posedge clk);
        anotar("Z no esta en CARRO, cuenta como intento fallido", dut.intentos === 3'd1);
        anotar("la mascara sigue sin revelar nada nuevo", dut.mascara[4:0] === 5'b00000);

        // Adivina el resto de la palabra; R aparece dos veces y se revela con un solo envio
        enviar_letra("C");
        enviar_letra("A");
        enviar_letra("R");
        enviar_letra("O");
        repeat (20) @(posedge clk);

        anotar("con las 4 letras correctas la mascara queda completa", dut.mascara === 12'hFFF);
        anotar("la fsm pasa a GANO", dut.state === ST_GANO);
        anotar("el marcador de partidas ganadas sube a 1", dut.num_ganadas === 7'd1);
        anotar("los intentos fallidos no volvieron a subir", dut.intentos === 3'd1);

        $display("\n%0d pruebas, %0d fallos", pruebas, errores);
        if (errores != 0) $fatal(1, "tb_top termino con fallos");
        else $display("=== TODAS LAS PRUEBAS PASARON ===");
        $finish;
    end

endmodule
