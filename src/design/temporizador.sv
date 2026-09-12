module temporizador (
    input  logic       clk,
    input  logic       rst,
    input  logic [2:0] i_state, // desde la fsm, decide cuando arrancar la cuenta y cuando contar fin_espera
    input  logic       modo,    // 0 = facil (60 s), 1 = dificil (45 s)

    output logic [7:0] tiempo,          // tiempo restante en BCD: {decenas, unidades}
    output logic       tiempo_agotado,  // se agoto el tiempo, hacia la FSM
    output logic       o_fin_espera     // se cumplieron los 3 s de resultado, hacia la FSM
);

    // Codigos de estado de la FSM principal (docs/diseño/modulos/M13_FSM.md, h)
    localparam logic [2:0] ST_JUEGO  = 3'b010;
    localparam logic [2:0] ST_GANO   = 3'b011;
    localparam logic [2:0] ST_PERDIO = 3'b100;

    // Tiempos iniciales en BCD (decenas, unidades), segun docs/diseño/modulos/M13_FSM.md
    localparam logic [3:0] TIEMPO_FACIL_DEC   = 4'd6, TIEMPO_FACIL_UNI   = 4'd0; // 60 s
    localparam logic [3:0] TIEMPO_DIFICIL_DEC = 4'd4, TIEMPO_DIFICIL_UNI = 4'd5; // 45 s

    // Los 3 s de o_fin_espera, contados con el mismo tick_1hz del reloj de partida
    localparam int ESPERA_S = 3;
    localparam int ESPERA_WIDTH = $clog2(ESPERA_S + 1);

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

    // Arranque del reloj de partida: en el diseño viejo lo mandaba la FSM con un pulso "start",
    // ahora la FSM no manda señales puntuales (M13_FSM.md, f) y este modulo decodifica su propio
    // disparo igual que ya hacen lfsr.sv y comparador_letra.sv con la entrada a CARGA.
    logic dec_juego, dec_juego_prev, start;

    assign dec_juego = (i_state == ST_JUEGO);

    always_ff @(posedge clk) begin
        if (rst) dec_juego_prev <= 1'b0;
        else dec_juego_prev <= dec_juego;
    end

    assign start = dec_juego & ~dec_juego_prev;

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

    // DEC_FIN: entrada a GANO o PERDIO, mismo patron de flanco que dec_juego arriba
    logic dec_fin, dec_fin_prev, pulso_fin;
    logic [ESPERA_WIDTH-1:0] cont_espera;

    assign dec_fin = (i_state == ST_GANO) || (i_state == ST_PERDIO);

    always_ff @(posedge clk) begin
        if (rst) dec_fin_prev <= 1'b0;
        else dec_fin_prev <= dec_fin;
    end

    assign pulso_fin = dec_fin & ~dec_fin_prev;

    // CONT_ESPERA: cuenta los tick_1hz transcurridos desde que se entro al estado de fin,
    // se satura en ESPERA_S para no dar la vuelta si la FSM tarda en consumir o_fin_espera
    always_ff @(posedge clk) begin
        if (rst) cont_espera <= '0;
        else if (pulso_fin) cont_espera <= '0;
        else if (dec_fin && tick_1hz && cont_espera != ESPERA_S[ESPERA_WIDTH-1:0])
            cont_espera <= cont_espera + 1'b1;
    end

    // o_fin_espera: se levanta al tercer tick_1hz de GANO/PERDIO y se mantiene hasta que la
    // FSM sale de ahi y entra al siguiente estado de fin (pulso_fin de la proxima partida)
    always_ff @(posedge clk) begin
        if (rst) o_fin_espera <= 1'b0;
        else if (pulso_fin) o_fin_espera <= 1'b0;
        else if (dec_fin && tick_1hz && cont_espera == ESPERA_S[ESPERA_WIDTH-1:0] - 1)
            o_fin_espera <= 1'b1;
    end

endmodule
