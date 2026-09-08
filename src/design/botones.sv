module botones (
    input logic clk,
    input logic rst,
    input logic btn_ok,
    input logic btn_sel,

    output logic btn_ok_pulse,
    output logic btn_sel_pulse
);

logic btn_ok_db;
logic btn_sel_db;


debounce #(.N(21)) debounce_ok (
    .clk(clk),
    .rst(rst),
    .button_in(btn_ok),
    .button_out(btn_ok_db)
);

debounce #(.N(21)) debounce_sel (
    .clk(clk),
    .rst(rst),
    .button_in(btn_sel),
    .button_out(btn_sel_db)
);

//Detector de flanco de subida: genera un pulso de un ciclo por cada presión de botón
logic btn_ok_db_prev;
logic btn_sel_db_prev;

always_ff @(posedge clk) begin
    if (rst) begin
        btn_ok_db_prev  <= 1'b0;
        btn_sel_db_prev <= 1'b0;
    end else begin
        btn_ok_db_prev  <= btn_ok_db;
        btn_sel_db_prev <= btn_sel_db;
    end
end

assign btn_ok_pulse  = btn_ok_db  & ~btn_ok_db_prev;
assign btn_sel_pulse = btn_sel_db & ~btn_sel_db_prev;

endmodule