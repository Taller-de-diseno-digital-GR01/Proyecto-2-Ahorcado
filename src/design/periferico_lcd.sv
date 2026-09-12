//NOTAS:


// Tabla de inicializacion y tiempos actualizados segun el datasheet del
// equipo (secuencia reducida: Power On -> 20ms -> Function Set -> 37us
// -> Display On/Off -> 37us -> Clear Display -> 1.52ms -> listo). El
// Entry Mode Set no se manda explicito porque, segun ese mismo
// datasheet, el circuito de reset interno del HD44780 ya deja
// I/D=1, SH=0 configurado, y esta secuencia solo corrige lo que el
// reset interno no deja como se necesita (2 lineas y display encendido).
// Bytes derivados de la tabla "Instruction bit assignments" de ese
// datasheet: Function Set 8bit/2L/5x8 = 0x38, Display ON+cursor off+
// blink off = 0x0C, Clear Display = 0x01.
//
// Timing del pulso E y de setup de RS/datos tomado del datasheet del
// KS0066U (controlador real del PmodCLP, compatible con el HD44780):
// tw (ancho de E) >= 230ns, tsu1 (setup RS/RW) >= 40ns,
// tsu2 (setup de datos) >= 80ns. Fuente:
// https://www.lcd-module.de/eng/pdf/zubehoer/ks0066.pdf (Tabla de
// caracteristicas AC, modo de escritura del MPU).
//
// Falta todavia: bloque de pruebas (testbench autoverificable)
// ============================================================================

module periferico_lcd #(
    parameter int CLK_FREQ_HZ = 100_000_000
) (
    input  logic        clk_i,
    input  logic        rst_i,          // reset sincrono, activo en alto

    // Interfaz estandar de bus (seccion 3.4.3 del enunciado)
    input  logic        write_enable_i,
    input  logic [1:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    // Pines fisicos hacia el PmodCLP (HD44780, modo de 8 bits)
    output logic        lcd_rs_o,
    output logic        lcd_rw_o,
    output logic        lcd_e_o,
    output logic [7:0]  lcd_data_o
);

    // Constantes de tiempo, derivadas de CLK_FREQ_HZ
    localparam int CYC_PER_US = CLK_FREQ_HZ / 1_000_000; // 100 @ 100 MHz

    // El PmodCLP real de este equipo necesita mas margen que los minimos del datasheet del
    // KS0066U para los tiempos que siguen al encendido inicial: con los minimos "de libro" se
    // pierde el primer caracter de cada mensaje en hardware real (no en simulacion). x3 sobre
    // esos minimos resuelve el problema, confirmado en la Basys3.
    localparam int MARGEN_SEGURIDAD = 3;

    localparam int T_20MS_CYC   = 20_000 * CYC_PER_US;                       // espera de encendido
    localparam int T_37US_CYC   = 37     * CYC_PER_US * MARGEN_SEGURIDAD;    // tras Function Set / Display On-Off
    localparam int T_40US_CYC   = 40     * CYC_PER_US * MARGEN_SEGURIDAD;    // comando/dato normal (operacion regular)
    localparam int T_1_52MS_CYC = 1_520  * CYC_PER_US * MARGEN_SEGURIDAD;    // clear / home
    localparam int T_EPULSE_CYC = ((CYC_PER_US / 2 > 0) ? (CYC_PER_US / 2) : 1) * MARGEN_SEGURIDAD;
                                                          // ancho del pulso E (~0.5us,
                                                          // min. real segun KS0066U: 230ns)
    localparam int T_SETUP_CYC  = (((80 * CYC_PER_US) / 1000 > 0) ? ((80 * CYC_PER_US) / 1000) : 1) * MARGEN_SEGURIDAD;
                                                          // espera de "setup" con E en bajo,
                                                          // antes de subir E (~80ns, el mayor
                                                          // entre tsu1=40ns y tsu2=80ns)

    // Tabla fija de inicializacion "by instruction" del HD44780, segun el
    // datasheet del equipo (ver nota arriba). Nota de herramienta: iverilog
    // (nuestro simulador, ver GNUmakefile) no soporta "localparam <tipo>
    // nombre [rango] = '{...}" (arreglo sin empacar con localparam), asi
    // que la tabla se implementa como un mux/case, exactamente la misma
    // idea que ya usamos para decodificar salidas segun el estado: el
    // indice init_idx selecciona la fila de la tabla.
    localparam int N_INIT = 3;

    function automatic logic [7:0] init_byte_f(input logic [1:0] idx);
        unique case (idx)
            2'd0: init_byte_f = 8'h38; // Function Set (8bit/2L/5x8)
            2'd1: init_byte_f = 8'h0C; // Display ON, cursor off, blink off
            2'd2: init_byte_f = 8'h01; // Clear Display
            default: init_byte_f = 8'h00;
        endcase
    endfunction

    function automatic logic [20:0] init_wait_f(input logic [1:0] idx);
        unique case (idx)
            2'd0: init_wait_f = T_37US_CYC[20:0];
            2'd1: init_wait_f = T_37US_CYC[20:0];
            2'd2: init_wait_f = T_1_52MS_CYC[20:0];
            default: init_wait_f = '0;
        endcase
    endfunction
    // Los tres pasos de la tabla van con rs=0 (son comandos), por eso no
    // hace falta una funcion aparte para eso: se pone 1'b0 directo abajo.

    // -------------------------------------------------------------------
    // Registros accesibles por el bus
    // -------------------------------------------------------------------
    logic       rs_reg;    // REG_CTRL_ESTADO, bit 1
    logic [7:0] data_reg;  // REG_DATOS, bits [7:0]

    wire start_pulse = write_enable_i && (addr_i == 2'b00) && wdata_i[0];
    wire clear_pulse = write_enable_i && (addr_i == 2'b00) && wdata_i[2];
    wire home_pulse  = write_enable_i && (addr_i == 2'b00) && wdata_i[3];

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rs_reg   <= 1'b0;
            data_reg <= 8'h00;
        end else begin
            if (write_enable_i && addr_i == 2'b00) rs_reg   <= wdata_i[1];
            if (write_enable_i && addr_i == 2'b01) data_reg <= wdata_i[7:0];
        end
    end

    // -------------------------------------------------------------------
    // FSM principal: RESET_WAIT -> (tabla de init) -> IDLE <-> SET/SETUP/EXEC/WAIT
    //
    // S_SETUP es el estado agregado para respetar tsu1/tsu2: mantiene
    // RS y los datos ya estables (E todavia en bajo) durante T_SETUP_CYC
    // ciclos antes de pasar a S_EXEC, donde recien ahi sube E.
    // -------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_RESET_WAIT,
        S_SET,
        S_SETUP,
        S_EXEC,
        S_WAIT,
        S_IDLE
    } state_t;

    state_t state, next_state;

    logic        init_done;
    logic [2:0]  init_idx;        // 0..N_INIT-1

    logic [7:0]  op_byte;
    logic        op_rs;
    logic [20:0] op_wait_target;  // alcanza para el mayor tiempo usado (T_1_52MS_CYC)

    logic [20:0] cnt;
    logic [15:0] e_cnt;

    logic busy_r, done_r;

    // clear_pulse/home_pulse/start_pulse solo valen durante el UNICO ciclo
    // en que se escribe el bit correspondiente (son W1P): se apagan solos
    // apenas write_enable_i se baja. Si S_IDLE decide "next_state = S_SET"
    // en base a ellos pero S_SET los vuelve a leer un ciclo despues, ya los
    // encuentra en cero. Por eso hace falta "guardarlos" (latch) en el
    // mismo ciclo en que S_IDLE los ve altos, para poder usarlos ya en
    // S_SET. Misma prioridad que antes: clear > home > start.
    typedef enum logic [1:0] {
        OP_START,
        OP_CLEAR,
        OP_HOME
    } pending_op_t;

    pending_op_t pending_op;

    // Logica de siguiente estado (combinacional, sin latches: default
    // "quedate igual" al inicio de cada branch)
    always_comb begin
        next_state = state;
        unique case (state)
            S_RESET_WAIT: if (cnt == T_20MS_CYC) next_state = S_SET;

            S_SET: next_state = S_SETUP;

            S_SETUP: if (cnt == T_SETUP_CYC) next_state = S_EXEC;

            S_EXEC: if (e_cnt == T_EPULSE_CYC) next_state = S_WAIT;

            S_WAIT: begin
                if (cnt == op_wait_target) begin
                    if (!init_done) next_state = S_SET;      // (des)pues de incrementar el indice
                    else            next_state = S_IDLE;      // operacion normal terminada
                end
            end

            S_IDLE: if (start_pulse || clear_pulse || home_pulse) next_state = S_SET;

            default: next_state = S_RESET_WAIT;
        endcase
    end

    // Registro de estado + datapath
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state          <= S_RESET_WAIT;
            init_done      <= 1'b0;
            init_idx       <= '0;
            cnt            <= '0;
            e_cnt          <= '0;
            op_byte        <= '0;
            op_rs          <= 1'b0;
            op_wait_target <= '0;
            done_r         <= 1'b0;
            pending_op     <= OP_START;
        end else begin
            state  <= next_state;
            done_r <= 1'b0; // "done" es un pulso de un ciclo; se reafirma abajo si toca

            unique case (state)

                S_RESET_WAIT: begin
                    cnt <= cnt + 1'b1;
                end

                S_SET: begin
                    cnt   <= '0;
                    e_cnt <= '0;
                    if (!init_done) begin
                        op_byte        <= init_byte_f(init_idx[1:0]);
                        op_rs          <= 1'b0;
                        op_wait_target <= init_wait_f(init_idx[1:0]);
                    end else begin
                        // pending_op ya quedo guardado desde S_IDLE (ver
                        // nota arriba de su declaracion): para aca los
                        // pulsos originales ya se apagaron.
                        unique case (pending_op)
                            OP_CLEAR: begin
                                op_byte        <= 8'h01;
                                op_rs          <= 1'b0;
                                op_wait_target <= T_1_52MS_CYC[20:0];
                            end
                            OP_HOME: begin
                                op_byte        <= 8'h02;
                                op_rs          <= 1'b0;
                                op_wait_target <= T_1_52MS_CYC[20:0];
                            end
                            default: begin // OP_START
                                op_byte        <= data_reg;
                                op_rs          <= rs_reg;
                                op_wait_target <= T_40US_CYC[20:0];
                            end
                        endcase
                    end
                end

                S_SETUP: begin
                    cnt <= cnt + 1'b1; // RS/datos ya estables, E todavia en bajo
                end

                S_EXEC: begin
                    cnt   <= '0; // lo dejamos listo para que S_WAIT arranque en 0
                    e_cnt <= e_cnt + 1'b1;
                end

                S_WAIT: begin
                    cnt <= cnt + 1'b1;
                    if (cnt == op_wait_target) begin
                        if (!init_done) begin
                            if (init_idx == N_INIT-1) init_done <= 1'b1;
                            else                       init_idx  <= init_idx + 1'b1;
                        end else begin
                            done_r <= 1'b1; // avisa a CONTROL_JUEGO que ya termino
                        end
                    end
                end

                S_IDLE: begin
                    cnt <= '0;
                    // aca los pulsos todavia estan vivos (es el mismo
                    // ciclo en que next_state los lee): se guardan en
                    // pending_op para que S_SET los pueda usar despues
                    if (clear_pulse)      pending_op <= OP_CLEAR;
                    else if (home_pulse)  pending_op <= OP_HOME;
                    else if (start_pulse) pending_op <= OP_START;
                end

                default: ;
            endcase
        end
    end


    // Salidas fisicas hacia el PmodCLP

    assign lcd_rw_o   = 1'b0; // este diseno solo escribe, nunca lee el LCD
    assign lcd_rs_o   = op_rs;
    assign lcd_data_o = op_byte;
    assign lcd_e_o    = (state == S_EXEC);

    // busy: ocupado en cualquier estado que no sea IDLE
    assign busy_r = (state != S_IDLE);


    // Lectura del bus (combinacional, con default para evitar latches)

    always_comb begin
        rdata_o = 32'h0;
        unique case (addr_i)
            2'b00: rdata_o = {22'h0, done_r, busy_r, 6'h0, rs_reg, 1'b0};
            2'b01: rdata_o = {24'h0, data_reg};
            default: rdata_o = 32'h0;
        endcase
    end

endmodule