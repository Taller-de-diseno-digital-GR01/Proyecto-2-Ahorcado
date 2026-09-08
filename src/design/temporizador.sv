module temporizador (
    input  logic       clk,
    input  logic       rst,
    input  logic       start,   // arranca el temporizador (carga tiempo inicial y activa running)
    input  logic       modo,    // 0 = facil (60 s), 1 = dificil (45 s)

    output logic [7:0] tiempo,          // tiempo restante en BCD: {decenas, unidades}
    output logic       tiempo_agotado   // se agoto el tiempo, hacia la FSM
);

    // Tiempos iniciales en BCD (decenas, unidades), segun docs/diseño/modulos/M13_FSM.md
    localparam logic [3:0] TIEMPO_FACIL_DEC   = 4'd6, TIEMPO_FACIL_UNI   = 4'd0; // 60 s
    localparam logic [3:0] TIEMPO_DIFICIL_DEC = 4'd4, TIEMPO_DIFICIL_UNI = 4'd5; // 45 s

    // Recarga del prescaler: 100 MHz / 100_000_000 = 1 Hz -- Se ajusta a 99_999_999 para que el tick dure exactamente 1 segundo
    // Es "parameter" (no localparam) para poder achicarlo desde el testbench y simular
    // una cuenta regresiva completa sin esperar 100_000_000 ciclos por cada segundo.
    parameter logic [26:0] PRESCALER_RECARGA = 27'd99_999_999;

    logic [3:0] tiempo_dec_inicial, tiempo_uni_inicial;
    logic [3:0] tiempo_dec, tiempo_uni;
    logic       running;
    logic       zero;
    logic [26:0] prescaler_cnt;
    logic        tick_1hz;
    logic        cten;

    // MUX 2:1 del tiempo inicial segun modo
    always_comb begin
        if (modo) begin //cuando modo es 1, se carga el tiempo de dificil
            tiempo_dec_inicial = TIEMPO_DIFICIL_DEC;
            tiempo_uni_inicial = TIEMPO_DIFICIL_UNI;
        end else begin
            tiempo_dec_inicial = TIEMPO_FACIL_DEC;
            tiempo_uni_inicial = TIEMPO_FACIL_UNI;
        end
    end

    // REG_RUNNING: se apaga sola al llegar a cero, sin necesitar una entrada "detener"
    always_ff @(posedge clk) begin
        if (rst)
            running <= 1'b0;
        else
            running <= start | (running & ~zero);
    end

    // CONT_PRESCALER: contador descendente de 27 bits, genera tick_1hz con su propio borrow
    assign tick_1hz = (prescaler_cnt == 27'd0);

    always_ff @(posedge clk) begin
        if (rst)
            prescaler_cnt <= PRESCALER_RECARGA;
        else if (tick_1hz)
            prescaler_cnt <= PRESCALER_RECARGA;
        else
            prescaler_cnt <= prescaler_cnt - 1'b1;
    end

    // REG_TIEMPO: carga en start, decrementa en BCD (con acarreo entre decadas) cuando cten=1
    assign cten = running & tick_1hz;
    assign zero = (tiempo_dec == 4'd0) && (tiempo_uni == 4'd0);



    //El if tiempo_uni == 4'd0 es para que cuando llegue a 0, se reinicie a 9 y se reste 1 a las decenas, si no, solo se resta 1 a las unidades
    always_ff @(posedge clk) begin
        if (rst) begin
            tiempo_dec <= 4'd0;
            tiempo_uni <= 4'd0;
        end else if (start) begin
            tiempo_dec <= tiempo_dec_inicial;
            tiempo_uni <= tiempo_uni_inicial;
        end else if (cten && !zero) begin
            if (tiempo_uni == 4'd0) begin
                tiempo_uni <= 4'd9;
                tiempo_dec <= tiempo_dec - 1'b1;
            end else begin
                tiempo_uni <= tiempo_uni - 1'b1;
            end
        end
    end

    assign tiempo = {tiempo_dec, tiempo_uni};//se asigna el tiempo en BCD a la salida

    // tiempo_agotado: se levanta solo cuando el tiempo llega a 0 mientras estaba corriendo
    // (running & zero), se limpia con start/rst y se mantiene en alto el resto de los ciclos.
    // (Si se levantara directo de "zero", quedaria en falso "agotado" tras un reset, antes
    // de cualquier start, porque tiempo arranca en 0 y por tanto zero=1 sin haber corrido.)
    always_ff @(posedge clk) begin
        if (rst)
            tiempo_agotado <= 1'b0;
        else if (start)
            tiempo_agotado <= 1'b0;
        else if (running & zero)
            tiempo_agotado <= 1'b1;
    end

endmodule
