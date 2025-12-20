module reg_file #(
    parameter int unsigned REGS_WIDTH = 32,
    parameter int unsigned REGS_DEPTH = 32 
) (
    input  logic             clk,
    input  logic [4:0]       rs1,
    input  logic [4:0]       rs2,
    input  logic [4:0]       rd,
    input  logic [REGS_WIDTH-1:0] wd3,
    input  logic             we3,
    output logic [REGS_WIDTH-1:0] rd1,
    output logic [REGS_WIDTH-1:0] rd2
);

    // Internal register array
    logic [REGS_WIDTH-1:0] rf [REGS_DEPTH-1:0];

    initial begin
        for (int i = 0; i < REGS_DEPTH; i++) begin
            rf[i] = '0;
        end
    end

    // Synchronous write
    always_ff @(posedge clk) begin
        if (we3 && (rd != 5'd0)) begin
            rf[rd] <= wd3;
        end
    end

    // Asynchronous read
    assign rd1 = (rs1 == 5'd0) ? '0 : rf[rs1];
    assign rd2 = (rs2 == 5'd0) ? '0 : rf[rs2];
endmodule
