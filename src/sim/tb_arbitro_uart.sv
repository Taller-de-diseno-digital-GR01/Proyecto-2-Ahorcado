`timescale 1ns/1ps

module tb_arbitro_uart;

  localparam logic [1:0] ADDR_DATOS_TX = 2'b00;
  localparam logic [1:0] ADDR_DATOS_RX = 2'b01;
  localparam logic [1:0] ADDR_CONTROL = 2'b10;
  localparam BIT_SEND = 0;
  localparam BIT_NEW_RX = 1;

  logic [1:0] rx_addr, tx_addr, o_addr;
  logic rx_we, tx_we, o_we;
  logic [31:0] rx_wdata, tx_wdata, o_wdata;
  logic [31:0] rx_rdata, tx_rdata, rdata;
  logic bus_libre;

  int pruebas = 0;
  int errores = 0;

  arbitro_uart dut (
    .i_rx_addr(rx_addr), .i_rx_we(rx_we), .i_rx_wdata(rx_wdata), .o_rx_rdata(rx_rdata),
    .i_tx_addr(tx_addr), .i_tx_we(tx_we), .i_tx_wdata(tx_wdata), .o_tx_rdata(tx_rdata),
    .o_tx_bus_libre(bus_libre),
    .o_addr(o_addr), .o_we(o_we), .o_wdata(o_wdata), .i_rdata(rdata)
  );

  task automatic anotar(input string nombre, input bit ok, input string detalle);
    pruebas++;
    if (ok) begin
      $display("ok %s", nombre);
    end
    else begin
      errores++;
      $display("fallo %s", nombre);
      $display("  %s", detalle);
    end
  endtask

  // el arbitro es puro combinacional, basta con poner las entradas y dejar que se asiente
  task automatic poner(input logic [1:0] ra, input logic rw, input logic [31:0] rd,
                       input logic [1:0] ta, input logic tw, input logic [31:0] td,
                       input logic [31:0] desde_periferico);
    rx_addr = ra; rx_we = rw; rx_wdata = rd;
    tx_addr = ta; tx_we = tw; tx_wdata = td;
    rdata = desde_periferico;
    #1;
  endtask

  task automatic chequear_salida(input string nombre, input logic [1:0] a, input logic we, input logic [31:0] d);
    anotar(nombre, o_addr === a && o_we === we && o_wdata === d,
           $sformatf("esperaba addr=%02b we=%0b wdata=%08h, y dio addr=%02b we=%0b wdata=%08h",
                     a, we, d, o_addr, o_we, o_wdata));
  endtask

  initial begin
    // los dos en reposo sondeando el control, nadie estorba a nadie
    poner(ADDR_CONTROL, 1'b0, 32'b0, ADDR_CONTROL, 1'b0, 32'b0, 32'h2);
    chequear_salida("con los dos en reposo el bus queda en el control", ADDR_CONTROL, 1'b0, 32'b0);
    anotar("y los dos leen el control de verdad",
           rx_rdata === 32'h2 && tx_rdata === 32'h2,
           $sformatf("rx leyo %08h y tx leyo %08h", rx_rdata, tx_rdata));
    anotar("el transmisor tiene el bus libre", bus_libre === 1'b1,
           $sformatf("bus_libre dio %0b", bus_libre));

    // el receptor va a leer su registro de datos, el transmisor se aguanta
    poner(ADDR_DATOS_RX, 1'b0, 32'b0, ADDR_CONTROL, 1'b0, 32'b0, 32'h41);
    chequear_salida("cuando el receptor lee datos, el bus es suyo", ADDR_DATOS_RX, 1'b0, 32'b0);
    anotar("y al transmisor se le corta el bus", bus_libre === 1'b0,
           $sformatf("bus_libre dio %0b", bus_libre));
    anotar("al transmisor le llegan ceros, no el registro ajeno", tx_rdata === 32'b0,
           $sformatf("tx leyo %08h", tx_rdata));

    // el transmisor quiere el bus y el receptor esta en reposo, se lo presta
    // el 4E tiene el bit 1 en alto, que es justo donde el receptor busca new_rx, si no se le corta lo lee como byte nuevo
    poner(ADDR_CONTROL, 1'b0, 32'b0, ADDR_DATOS_TX, 1'b1, 32'h4E, 32'h4E);
    chequear_salida("con el receptor en reposo, el transmisor escribe su dato", ADDR_DATOS_TX, 1'b1, 32'h4E);
    anotar("y al receptor le llegan ceros para que no vea un new_rx falso", rx_rdata === 32'b0,
           $sformatf("rx leyo %08h", rx_rdata));

    // los dos a la vez, gana el receptor
    poner(ADDR_DATOS_RX, 1'b0, 32'b0, ADDR_DATOS_TX, 1'b1, 32'h4C, 32'h41);
    chequear_salida("si los dos piden a la vez, gana el receptor", ADDR_DATOS_RX, 1'b0, 32'b0);
    anotar("y el transmisor se queda esperando", bus_libre === 1'b0,
           $sformatf("bus_libre dio %0b", bus_libre));

    // el receptor limpia new_rx, el send del transmisor no se puede perder por el camino
    poner(ADDR_CONTROL, 1'b1, 32'h0, ADDR_CONTROL, 1'b0, 32'b0, 32'h3);
    chequear_salida("limpiar new_rx conserva el send que estaba alto", ADDR_CONTROL, 1'b1, 32'h1);

    poner(ADDR_CONTROL, 1'b1, 32'h0, ADDR_CONTROL, 1'b0, 32'b0, 32'h2);
    chequear_salida("y si send estaba bajo, sigue bajo", ADDR_CONTROL, 1'b1, 32'h0);

    // el transmisor levanta send, el byte que el receptor no ha leido no se puede borrar
    poner(ADDR_CONTROL, 1'b0, 32'b0, ADDR_CONTROL, 1'b1, 32'h1, 32'h2);
    chequear_salida("levantar send conserva el new_rx que estaba esperando", ADDR_CONTROL, 1'b1, 32'h3);

    poner(ADDR_CONTROL, 1'b0, 32'b0, ADDR_CONTROL, 1'b1, 32'h1, 32'h0);
    chequear_salida("y sin byte esperando, new_rx se queda en cero", ADDR_CONTROL, 1'b1, 32'h1);

    // el caso feo, los dos escriben el control en el mismo ciclo
    poner(ADDR_CONTROL, 1'b1, 32'h0, ADDR_CONTROL, 1'b1, 32'h1, 32'h3);
    chequear_salida("con los dos escribiendo el control a la vez, pasa el del receptor", ADDR_CONTROL, 1'b1, 32'h1);
    anotar("y el transmisor sabe que no paso y va a reintentar", bus_libre === 1'b0,
           $sformatf("bus_libre dio %0b", bus_libre));

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_arbitro_uart termino con fallos");
    $finish;
  end

endmodule
