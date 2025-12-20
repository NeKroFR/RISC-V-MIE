module Top #(
    parameter int IMEM_SIZE = 16384,  // 64KB
    parameter int DMEM_SIZE = 16384   // 64KB
) (
    input logic clk,
    input logic reset,
    input logic verbosity
);
    localparam logic [31:0] UART_ADDR = 32'h8000_0000;

    logic [31:0] pc, instr, mem_addr, mem_wdata, mem_rdata;
    logic [3:0] mem_be;
    // .text (IMEM)
    logic [31:0] imem [0:IMEM_SIZE-1]; // 64KB
    initial $readmemh("imem.hex", imem);
    assign instr = imem[pc[15:2]];
    // .data (DMEM)
    logic [31:0] dmem [0:DMEM_SIZE-1]; // 64KB
    initial $readmemh("dmem.hex", dmem);

    // Memory read
    assign mem_rdata = dmem[mem_addr[15:2]];

    // Memory write
    always_ff @(posedge clk) begin
        if (|mem_be) begin
            if (mem_addr == UART_ADDR) begin
                if (mem_be[0]) begin
                    $write("%c", mem_wdata[7:0]);
                    $fflush();
                end
                if (mem_be[1]) begin
                    $write("%c", mem_wdata[15:8]);
                    $fflush();
                end
                if (mem_be[2]) begin
                    $write("%c", mem_wdata[23:16]);
                    $fflush();
                end
                if (mem_be[3]) begin
                    $write("%c", mem_wdata[31:24]);
                    $fflush();
                end
            end else begin
                if (mem_be[0]) dmem[mem_addr[15:2]][7:0] <= mem_wdata[7:0];
                if (mem_be[1]) dmem[mem_addr[15:2]][15:8] <= mem_wdata[15:8];
                if (mem_be[2]) dmem[mem_addr[15:2]][23:16] <= mem_wdata[23:16];
                if (mem_be[3]) dmem[mem_addr[15:2]][31:24] <= mem_wdata[31:24];
            end
        end
    end

    // Initialize the CPU
    riscv_cpu cpu (
        .clk(clk),
        .reset(reset),
        .pc(pc),
        .instr(instr),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_be(mem_be)
    );
endmodule
