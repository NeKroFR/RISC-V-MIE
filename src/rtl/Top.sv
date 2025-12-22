module Top #(
    parameter int IMEM_SIZE = 16384, // 64KB
    parameter int DMEM_SIZE = 16384  // 64KB
) (
    input logic clk,
    input logic reset,
    input logic verbosity
);

    import "DPI-C" function int dpi_getchar();

    localparam logic [31:0] UART_ADDR = 32'h4000_0000;
    localparam logic [31:0] UART_LSR  = 32'h4000_0004;
    localparam logic [31:0] EXIT_ADDR = 32'h1000_0000;

    logic [31:0] pc, instr, mem_addr, mem_wdata, mem_rdata;
    logic [3:0]  mem_be;

    // UART Internal State
    logic [7:0] rx_buffer;
    logic       rx_ready;

    // .text (IMEM)
    logic [31:0] imem [0:IMEM_SIZE-1];
    initial $readmemh("imem.hex", imem);
    assign instr = imem[pc[15:2]];

    // .data (DMEM)
    logic [31:0] dmem [0:DMEM_SIZE-1];
    initial $readmemh("dmem.hex", dmem);

    // MEMORY READ
    always_comb begin
        mem_rdata = 32'b0;
        if (mem_addr[31:16] == 16'h8000) begin
            mem_rdata = dmem[mem_addr[15:2]];
        end 
        else if (mem_addr == UART_ADDR) begin
            mem_rdata = {24'b0, rx_buffer};
        end 
        else if (mem_addr == UART_LSR) begin
            // Bit 5: TX Ready (always 1)
            // Bit 0: RX Ready
            mem_rdata = {26'b0, 1'b1, 4'b0, rx_ready};
        end
    end

    // MEMORY WRITE (UART & DMEM)
    always_ff @(posedge clk) begin
        if (reset) begin
            rx_ready <= 1'b0;
            rx_buffer <= 8'd0;
        end else begin
            // Poll for input if buffer is empty
            if (!rx_ready) begin
                int c = dpi_getchar();
                if (c != -1) begin
                    rx_buffer <= c[7:0];
                    rx_ready  <= 1'b1;
                end
            end

            // Handle CPU Actions
            if (|mem_be) begin
                if (mem_addr == UART_ADDR) begin
                    // Write to UART
                    if (mem_be[0]) begin 
                        $write("%c", mem_wdata[7:0]); 
                        $fflush(); 
                    end
                end else if (mem_addr == EXIT_ADDR) begin
                    $display("\n[EXIT] Program terminated at with return value %0d.", mem_wdata);
                    $finish;
                end else if (mem_addr[31:16] == 16'h8000) begin
                    // Write to DMEM
                    if (mem_be[0]) dmem[mem_addr[15:2]][7:0]   <= mem_wdata[7:0];
                    if (mem_be[1]) dmem[mem_addr[15:2]][15:8]  <= mem_wdata[15:8];
                    if (mem_be[2]) dmem[mem_addr[15:2]][23:16] <= mem_wdata[23:16];
                    if (mem_be[3]) dmem[mem_addr[15:2]][31:24] <= mem_wdata[31:24];
                end
            end

            // Clear RX flag when CPU reads the data register
            // If instr == load and mem_addr == UART_ADDR
            if (instr[6:0] == 7'b0000011 && mem_addr == UART_ADDR) begin
                rx_ready <= 1'b0;
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
