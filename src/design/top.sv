//TODO: Nos hace falta agregar lo del banco de palabaras 
module top (
    input  logic       clk,
    input  logic       rst,
    input  logic       btn_sel,
    input  logic       btn_ok,
    //UART
    input  logic       rx_i,

    output logic       tx_o,
    //LCD
    output logic        lcd_rs_o,
    output logic        lcd_rw_o,
    output logic        lcd_e_o,
    output logic [7:0]  lcd_data_o,

    //7 segmentos
    output logic [6:0]  seg,
    output logic [3:0]  an,
    output logic        dp,

    //LEDs
    output logic [1:0]  state_led,
    output logic        buzzer
);

    // M09_Botones: filtra y detecta flanco de BTN_SEL/BTN_OK, entrega pulsos limpios a la FSM
    logic sel_pulse, ok_pulse;

    botones u_botones (
        .clk          (clk),
        .rst          (rst),
        .btn_ok       (btn_ok),
        .btn_sel      (btn_sel),
        .btn_ok_pulse (ok_pulse),
        .btn_sel_pulse(sel_pulse)
    );

    logic valid_word; // UART a Fsm: detecta palabra completa y valida, entrega señal a la FSM
    logic palabra_completa; //UART a Fsm: detecta palabra completa y valida, entrega señal a la FSM
    logic intentos_agotados; // contador de intentos a Fsm: detecta que se agotaron los intentos, entrega señal a la FSM
    logic tiempo_agotado; // temporizador -a Fsm: detecta que se agotó el tiempo, entrega señal a la FSM
    logic fin_espera; // temporizador a Fsm: detecta que se agotó el tiempo de espera, entrega señal a la FSM

    // M13_FSM: estado global de la partida
    logic [2:0] state;
    logic       modo;

    fsm u_fsm (
        .clk                (clk),
        .rst                (rst),
        .i_sel              (sel_pulse),
        .i_ok               (ok_pulse),
        .i_valid_word       (valid_word),
        .i_palabra_completa (palabra_completa),
        .i_intentos_agotados(intentos_agotados),
        .i_tiempo_agotado   (tiempo_agotado),
        .i_fin_espera       (fin_espera),
        .o_state            (state),
        .o_modo             (modo)
    );

    // M03_Temporizador: cuenta regresiva de la partida y los 3 s de resultado en pantalla
    logic [7:0] tiempo;

    temporizador u_temporizador (
        .clk           (clk),
        .rst           (rst),
        .i_state       (state),
        .modo          (modo),
        .tiempo        (tiempo),
        .tiempo_agotado(tiempo_agotado),
        .o_fin_espera  (fin_espera)
    );

    // comparador palabra a con palabra
    logic try;

    // M12_Contador-Intentos: cuenta fallos de la partida en curso
    logic [2:0] intentos;

    contador_intentos u_contador_intentos (
        .clk                (clk),
        .rst                (rst),
        .i_try              (try), //Señal que indica que se realizó un intento
        .i_state            (state),
        .o_intentos         (intentos),
        .o_intentos_agotados(intentos_agotados)
    );

    // M08_LFSR: escoge la palabra secreta al entrar a CARGA
    // TODO: banco de palabras (REG_WBank) pendiente.
    // Stub temporal: bank_word fijo en 0, mismo ancho que los parametros por defecto de lfsr
    // (WORD_MAXLEN=15, LETRA_WIDTH=5 -> WORD_MAXLEN*LETRA_WIDTH+4 = 79 bits).
    localparam int BANK_ADDR_WIDTH = 6;  // $clog2(50+1)
    localparam int WORD_WIDTH      = 79; // WORD_MAXLEN*LETRA_WIDTH+4

    logic [BANK_ADDR_WIDTH-1:0] bank_addr;
    logic [WORD_WIDTH-1:0]      bank_word_stub;
    logic [WORD_WIDTH-1:0]      word;

    assign bank_word_stub = '0;

    lfsr u_lfsr (
        .clk         (clk),
        .rst         (rst),
        .i_state     (state),
        .i_modo      (modo),
        .i_bank_word (bank_word_stub),
        .o_bank_addr (bank_addr),
        .o_word      (word),
        .o_valid_word(valid_word)
    );
    //Corregi el ancho de bits del modulos: lsfr tiene 79 bits, comparador_letra tiene 75 bits, transmisor_uart tiene 75 bits, mostrar_lcd tiene 60 bits.
    // M07_Comparador-letra: WORD_MAXLEN se sobreescribe a 15 (en vez del default 12) para que
    // coincida con el formato que empaqueta lfsr (M08_LFSR.md, h): word[78:0] =
    // {longitud[3:0], letra15[4:0], ..., letra1[4:0]}. Con WORD_MAXLEN=15, i_word queda en
    // exactamente 75 bits (word[74:0], sin la longitud) e i_word_length sigue en 4 bits
    // ($clog2(16)=4, igual que con 12), asi que se conectan directo sin adaptador de por medio.
    //
    // Pendiente de receptor_uart (REG_Letra-in), aun no instanciado
    logic [7:0] letra_in;
    logic       letra_nueva;

    logic [1:0] letra_state; // hacia generador_tono y transmisor_uart
    logic       letra_lista; // idem
    logic [14:0] mascara;    // hacia mostrar_lcd y transmisor_uart (15 bits, ver nota de arriba)

    comparador_letra #(.WORD_MAXLEN(15)) u_comparador_letra (
        .clk              (clk),
        .rst              (rst),
        .i_letra          (letra_in),
        .i_letra_nueva    (letra_nueva),
        .i_word           (word[74:0]),
        .i_word_length    (word[78:75]),
        .i_state          (state),
        .o_letra_state    (letra_state),
        .o_letra_lista    (letra_lista),
        .o_palabra_completa(palabra_completa),
        .o_mascara        (mascara),
        .o_try            (try)
    );

    // M10_Receptor-UART: filtra letras A-Z que llegan por UART y solo las deja pasar en JUEGO
    // Pendiente de arbitro_uart/periferico_uart, aun no instanciados
    logic [1:0]  rx_bus_addr;
    logic        rx_bus_we;
    logic [31:0] rx_bus_wdata;
    logic [31:0] rx_bus_rdata;

    receptor_uart u_receptor_uart (
        .clk           (clk),
        .rst           (rst),
        .i_rdata       (rx_bus_rdata),
        .i_state       (state),
        .o_addr        (rx_bus_addr),
        .o_write_enable(rx_bus_we),
        .o_wdata       (rx_bus_wdata),
        .o_letra       (letra_in),
        .o_valid_w     (letra_nueva)
    );

    // M11_Transmisor-UART: arma y envia la trama de estado del juego hacia la PC
    // WORD_MAXLEN se sobreescribe a 15, igual que en comparador_letra, para que i_mascara
    // (15 bits) coincida con la mascara que ese modulo ya produce.
    // Pendiente de arbitro_uart/periferico_uart, aun no instanciados
    logic        tx_bus_we;
    logic [1:0]  tx_bus_addr;
    logic [31:0] tx_bus_wdata;
    logic [31:0] tx_bus_rdata;
    logic        tx_bus_libre;

    transmisor_uart #(.WORD_MAXLEN(15)) u_transmisor_uart (
        .clk          (clk),
        .rst          (rst),
        .i_state      (state),
        .i_modo       (modo),
        .i_letra_state(letra_state),
        .i_letra_lista(letra_lista),
        .i_intentos   (intentos),
        .i_word_length(word[78:75]),
        .i_mascara    (mascara),
        .i_rdata      (tx_bus_rdata),
        .i_bus_libre  (tx_bus_libre),
        .o_write_enable(tx_bus_we),
        .o_addr       (tx_bus_addr),
        .o_wdata      (tx_bus_wdata)
    );

    // ARBITRO_UART: multiplexa el bus de 32 bits entre receptor_uart y transmisor_uart
    // Pendiente de periferico_uart, aun no instanciado
    logic [1:0]  uart_addr;
    logic        uart_we;
    logic [31:0] uart_wdata;
    logic [31:0] uart_rdata;

    arbitro_uart u_arbitro_uart (
        .i_rx_addr     (rx_bus_addr),
        .i_rx_we       (rx_bus_we),
        .i_rx_wdata    (rx_bus_wdata),
        .o_rx_rdata    (rx_bus_rdata),
        .i_tx_addr     (tx_bus_addr),
        .i_tx_we       (tx_bus_we),
        .i_tx_wdata    (tx_bus_wdata),
        .o_tx_rdata    (tx_bus_rdata),
        .o_tx_bus_libre(tx_bus_libre),
        .o_addr        (uart_addr),
        .o_we          (uart_we),
        .o_wdata       (uart_wdata),
        .i_rdata       (uart_rdata)
    );

    // PERIFERICO_UART: nucleos TX/RX a 115200 baudios, conectado a los pines fisicos del bus RS232
    periferico_uart u_periferico_uart (
        .clk_i         (clk),
        .rst_i         (rst),
        .write_enable_i(uart_we),
        .addr_i        (uart_addr),
        .wdata_i       (uart_wdata),
        .rdata_o       (uart_rdata),
        .rx_i          (rx_i),
        .tx_o          (tx_o)
    );

    // M02_Generador-Tono: tono de acierto/fallo/fin de partida hacia el buzzer
    generador_tono u_generador_tono (
        .clk          (clk),
        .rst          (rst),
        .i_state      (state),
        .i_letra_state(letra_state),
        .i_letra_lista(letra_lista),
        .o_sound      (buzzer)
    );

    // M05_Estado: refleja state en el LED de estado
    Estado u_estado (
        .clk      (clk),
        .rst      (rst),
        .state    (state),
        .state_led(state_led)
    );

    // M06_Ganadas: cuenta partidas ganadas, hacia M01_Marcador
    logic [6:0] num_ganadas;

    M06_Ganadas u_ganadas (
        .clk        (clk),
        .rst        (rst),
        .state      (state),
        .num_ganadas(num_ganadas)
    );

    // M01_Marcador: displays de 7 segmentos, tiempo restante y partidas ganadas
    marcador u_marcador (
        .clk        (clk),
        .rst        (rst),
        .time_value (tiempo),
        .num_ganadas(num_ganadas),
        .seg        (seg),
        .an         (an),
        .dp         (dp)
    );

    // Adaptador REG_Palabra-escogida -> mostrar_lcd: convierte el codigo de 5 bits (0-25) de
    // cada letra a ASCII (+8'h41). mostrar_lcd solo soporta 12 letras (i_word[95:0] hardcodeado,
    // no parametrizado como comparador_letra/transmisor_uart), asi que se usan las primeras 12
    // letras de word (bits [59:0], letra1 en la posicion 0 del bus ASCII, mismo orden que usa
    // mostrar_lcd internamente con i_word[pos*8 +: 8]) y se trunca mascara a esos mismos 12 bits.
    //
    // El truncamiento es seguro: el equipo acordo que el banco de palabras (REG_WBank, pendiente
    // de integrar) limita cada palabra a maximo 12 letras, asi que las posiciones 12-14 de
    // mascara siempre son relleno (nunca datos reales) y word nunca usa las letras 13-15 que
    // lfsr/comparador_letra dejan disponibles con WORD_MAXLEN=15.
    localparam int LCD_MAXLEN = 12;

    logic [LCD_MAXLEN*8-1:0] word_ascii;

    always_comb begin
        for (int i = 0; i < LCD_MAXLEN; i++) begin
            word_ascii[i*8 +: 8] = {3'b000, word[i*5 +: 5]} + 8'h41;
        end
    end

    // M04_Mostrar-LCD: decide que pantalla toca y arma la transaccion de bus hacia PERIFERICO_LCD
    // Pendiente de periferico_lcd, aun no instanciado
    logic [1:0]  lcd_bus_addr;
    logic        lcd_bus_we;
    logic [31:0] lcd_bus_wdata;
    logic [31:0] lcd_bus_rdata;

    mostrar_lcd u_mostrar_lcd (
        .clk           (clk),
        .rst           (rst),
        .i_state       (state),
        .i_modo        (modo),
        .i_word        (word_ascii),
        .i_word_length (word[78:75]),
        .i_mascara     (mascara[11:0]),
        .i_rdata       (lcd_bus_rdata),
        .o_addr        (lcd_bus_addr),
        .o_write_enable(lcd_bus_we),
        .o_wdata       (lcd_bus_wdata)
    );

    // PERIFERICO_LCD: nucleo del HD44780 (PmodCLP, modo 8 bits), conectado a los pines fisicos
    periferico_lcd u_periferico_lcd (
        .clk_i         (clk),
        .rst_i         (rst),
        .write_enable_i(lcd_bus_we),
        .addr_i        (lcd_bus_addr),
        .wdata_i       (lcd_bus_wdata),
        .rdata_o       (lcd_bus_rdata),
        .lcd_rs_o      (lcd_rs_o),
        .lcd_rw_o      (lcd_rw_o),
        .lcd_e_o       (lcd_e_o),
        .lcd_data_o    (lcd_data_o)
    );

endmodule
