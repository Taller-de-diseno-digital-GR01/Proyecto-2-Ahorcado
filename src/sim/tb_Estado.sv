`timescale 1ns/1ps

module tb_M05_Estado;

    logic clk;
    logic rst;
    logic [2:0] state;
    logic [1:0] state_led;

    integer errores;

    M05_Estado dut (
        .clk       (clk),
        .rst       (rst),
        .state     (state),
        .state_led (state_led)
    );

    always #5 clk = ~clk;


    task automatic probar_estado(
        input logic [2:0] estado_prueba,
        input logic [1:0] salida_esperada
    );
        begin
            state = estado_prueba;

            // Esperar a que el registro capture el estado
            @(posedge clk);
            #1;

            if (state_led !== salida_esperada) begin
                $display(
                    "ERROR: state=%b -> state_led=%b, esperado=%b",
                    estado_prueba,
                    state_led,
                    salida_esperada
                );
                errores = errores + 1;
            end
            else begin
                $display(
                    "OK: state=%b -> state_led=%b",
                    estado_prueba,
                    state_led
                );
            end
        end
    endtask


    initial begin

        $dumpfile("tb_M05_Estado.vcd");
        $dumpvars(0, tb_M05_Estado);

        clk     = 1'b0;
        rst     = 1'b1;
        state   = 3'b000;
        errores = 0;

        repeat (2) @(posedge clk);
        rst = 1'b0;

        // SELECCION
        probar_estado(3'b000, 2'b00);

        // CARGA
        probar_estado(3'b001, 2'b01);

        // JUEGO
        probar_estado(3'b010, 2'b01);

        // GANO
        probar_estado(3'b011, 2'b10);

        // PERDIO_INTENTOS
        probar_estado(3'b100, 2'b10);

        // PERDIO_TIEMPO
        probar_estado(3'b101, 2'b10);

        // Estado inválido -> vuelve a visualización de selección
        probar_estado(3'b110, 2'b00);
        probar_estado(3'b111, 2'b00);

        $display("");
        $display("============================================");

        if (errores == 0)
            $display("M05: TODOS LOS CASOS PASARON.");
        else
            $display("M05: SE ENCONTRARON %0d ERRORES.", errores);

        $display("============================================");

        #20;
        $finish;
    end

endmodule
