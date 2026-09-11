// ============================================================================
// PERIFERICO_LCD - Proyecto 2 (Ahorcado), EL3313
//
// Envoltorio de registros de 32 bits (interfaz estandar de bus del
// enunciado, seccion 3.4.3) + driver interno del HD44780 (PmodCLP,
// modo de 8 bits) discutido en el chat.
//
// *** BORRADOR PARA REVISAR, NO DAR POR VALIDADO ***
// Los bytes de comando y los tiempos de espera de la tabla de
// inicializacion son valores TIPICOS tomados de la hoja de datos del
// HD44780U. Confirmalos contra la hoja de datos exacta que estes
// citando y contra la referencia del PmodCLP antes de usarlos en la
// entrega, y deja esa fuente documentada en tu informe tecnico.
// Falta ademas: bloque de pruebas (testbench autoverificable), y
// revisar con el linter que no se cuele ningun latch.
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

    // -------------------------------------------------------------------
    // Constantes de tiempo, derivadas de CLK_FREQ_HZ (repasar contra la
    // hoja de datos real antes de dar por buenos estos numeros)
    // -------------------------------------------------------------------
    localparam int CYC_PER_US = CLK_FREQ_HZ / 1_000_000; // 100 @ 100 MHz

    localparam int T_15MS_CYC   = 15_000 * CYC_PER_US;  // espera de encendido
    localparam int T_4_1MS_CYC  = 4_100  * CYC_PER_US;  // tras 1er Function Set
    localparam int T_100US_CYC  = 100    * CYC_PER_US;  // tras 2do Function Set
    localparam int T_40US_CYC   = 40     * CYC_PER_US;  // comando/dato normal
    localparam int T_1_52MS_CYC = 1_520  * CYC_PER_US;  // clear / home
    localparam int T_EPULSE_CYC = (CYC_PER_US / 2 > 0) ? (CYC_PER_US / 2) : 1;
                                                          // ancho del pulso E (~0.5us)

    // -------------------------------------------------------------------
    // Tabla fija de inicializacion "by instruction" del HD44780
    // (valores de ejemplo — verificar contra la hoja de datos)
    // -------------------------------------------------------------------
    localparam int N_INIT = 6;

    localparam logic [7:0] INIT_BYTE [0:N_INIT-1] = '{
        8'h30, 8'h30, 8'h38, 8'h0C, 8'h01, 8'h06
    };
    // Function Set, Function Set, Function Set(8b/2L/5x8), Display ON,
    // Clear Display, Entry Mode Set — todos con rs=0 (son comandos)
    localparam logic INIT_RS [0:N_INIT-1] = '{
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0
    };
    localparam int INIT_WAIT [0:N_INIT-1] = '{
        T_4_1MS_CYC, T_100US_CYC, T_40US_CYC, T_40US_CYC, T_1_52MS_CYC, T_40US_CYC
    };

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
    // FSM principal: RESET_WAIT -> (tabla de init) -> IDLE <-> SET/EXEC/WAIT
    // -------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_RESET_WAIT,
        S_SET,
        S_EXEC,
        S_WAIT,
        S_IDLE
    } state_t;

    state_t state, next_state;

    logic        init_done;
    logic [2:0]  init_idx;        // 0..N_INIT-1

    logic [7:0]  op_byte;
    logic        op_rs;
    logic [20:0] op_wait_target;  // alcanza para T_15MS_CYC

    logic [20:0] cnt;
    logic [15:0] e_cnt;

    logic busy_r, done_r;

    // Logica de siguiente estado (combinacional, sin latches: default
    // "quedate igual" al inicio de cada branch)
    always_comb begin
        next_state = state;
        unique case (state)
            S_RESET_WAIT: if (cnt == T_15MS_CYC) next_state = S_SET;

            S_SET: next_state = S_EXEC;

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
                        op_byte        <= INIT_BYTE[init_idx];
                        op_rs          <= INIT_RS[init_idx];
                        op_wait_target <= INIT_WAIT[init_idx][20:0];
                    end else if (clear_pulse) begin
                        op_byte        <= 8'h01;
                        op_rs          <= 1'b0;
                        op_wait_target <= T_1_52MS_CYC[20:0];
                    end else if (home_pulse) begin
                        op_byte        <= 8'h02;
                        op_rs          <= 1'b0;
                        op_wait_target <= T_1_52MS_CYC[20:0];
                    end else begin // start_pulse
                        op_byte        <= data_reg;
                        op_rs          <= rs_reg;
                        op_wait_target <= T_40US_CYC[20:0];
                    end
                end

                S_EXEC: begin
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
                end

                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------
    // Salidas fisicas hacia el PmodCLP
    // -------------------------------------------------------------------
    assign lcd_rw_o   = 1'b0; // este diseno solo escribe, nunca lee el LCD
    assign lcd_rs_o   = op_rs;
    assign lcd_data_o = op_byte;
    assign lcd_e_o    = (state == S_EXEC);

    // busy: ocupado en cualquier estado que no sea IDLE
    assign busy_r = (state != S_IDLE);

    // -------------------------------------------------------------------
    // Lectura del bus (combinacional, con default para evitar latches)
    // -------------------------------------------------------------------
    always_comb begin
        rdata_o = 32'h0;
        unique case (addr_i)
            2'b00: rdata_o = {22'h0, done_r, busy_r, 6'h0, rs_reg, 1'b0};
            2'b01: rdata_o = {24'h0, data_reg};
            default: rdata_o = 32'h0;
        endcase
    end

endmodule
