`timescale 1ns / 1ps
`include "defines.vh"

module cpu_core(
    input  wire        cpu_rst,
    input  wire        cpu_clk,

    output wire        ifetch_req    /* verilator public */,
    output wire [31:0] ifetch_addr   /* verilator public */,
    input  wire        ifetch_ready  /* verilator public */,
    input  wire        ifetch_valid  /* verilator public */,
    input  wire [31:0] ifetch_inst   /* verilator public */,

    output reg  [ 3:0] daccess_ren   /* verilator public */,
    output reg  [31:0] daccess_addr  /* verilator public */,
    input  wire        daccess_rvalid /* verilator public */,
    input  wire [31:0] daccess_rdata /* verilator public */,
    output reg  [ 3:0] daccess_wen   /* verilator public */,
    output reg  [31:0] daccess_wdata /* verilator public */,
    input  wire        daccess_wresp /* verilator public */
);

    // The supplied IROM is synchronous.  Keep the address associated with
    // each outstanding request and buffer one response during a hazard stall.
    reg  [31:0] fetch_pc;
    reg         fetch_pending;
    reg  [31:0] fetch_pending_pc;
    reg         fetch_buf_valid;
    reg  [31:0] fetch_buf_pc;
    reg  [31:0] fetch_buf_inst;

    wire [31:0] pc = fetch_pc;

    // ID stage.
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;
    wire [31:0] rf_rs1_data;
    wire [31:0] rf_rs2_data;
    wire [31:0] id_imm;
    wire [ 4:0] id_rs1 = id_inst[19:15];
    wire [ 4:0] id_rs2 = id_inst[24:20];
    wire [ 4:0] id_rd  = id_inst[11:7];
    wire [ 4:0] id_alu_op;
    wire        id_alua_sel;
    wire        id_alub_sel;
    wire [ 2:0] id_ram_rop;
    wire [ 3:0] id_ram_wop;
    wire        id_rf_we;
    wire [ 1:0] id_rf_wsel;
    wire [ 1:0] id_npc_op;
    wire [ 2:0] id_sext_op;
    wire        id_is_ld_st;
    wire        id_is_mul_div;

    // EX stage.
    wire [31:0] ex_pc;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;
    wire [ 4:0] ex_rs1;
    wire [ 4:0] ex_rs2;
    wire [ 4:0] ex_rd;
    wire [ 4:0] ex_alu_op;
    wire        ex_alua_sel;
    wire        ex_alub_sel;
    wire [ 2:0] ex_ram_rop;
    wire [ 3:0] ex_ram_wop;
    wire        ex_rf_we;
    wire [ 1:0] ex_rf_wsel;
    wire        ex_is_mul_div;
    wire        ex_is_ld_st;
    wire [ 1:0] ex_npc_op;
    wire [31:0] forwarded_a;
    wire [31:0] forwarded_b;
    wire [31:0] alu_a = ex_alua_sel ? ex_pc  : forwarded_a;
    wire [31:0] alu_b = ex_alub_sel ? ex_imm : forwarded_b;
    wire [31:0] alu_c;
    wire        alu_branch;
    wire        mul_div_busy;
    wire [ 1:0] forward_a;
    wire [ 1:0] forward_b;

    // MEM stage.
    wire [31:0] mem_alu_result;
    wire [31:0] mem_rs2_data;
    wire [31:0] mem_pc;
    wire [31:0] mem_imm;
    wire [ 4:0] mem_rd;
    wire [ 2:0] mem_ram_rop;
    wire [ 3:0] mem_ram_wop;
    wire        mem_rf_we;
    wire [ 1:0] mem_rf_wsel;
    wire        mem_is_mul_div;
    wire        mem_is_ld_st;
    wire [31:0] mem_load_data;
    wire [31:0] mem_forward_data;
    wire [ 3:0] mem_da_ren;
    wire [31:0] mem_da_addr;
    wire [ 3:0] mem_da_wen;
    wire [31:0] mem_da_wdata;
    wire        mem_is_load  = (mem_ram_rop != `RAM_EXT_N);
    wire        mem_is_store = (mem_ram_wop != `RAM_WE_N);
    wire        mem_done = mem_is_load  ? daccess_rvalid :
                            mem_is_store ? daccess_wresp  : 1'b1;
    wire        mem_wait = mem_is_ld_st && !mem_done;

    // WB stage.
    wire [31:0] wb_alu_result;
    wire [31:0] wb_load_data;
    wire [31:0] wb_pc;
    wire [31:0] wb_imm;
    wire [ 4:0] wb_rd;
    wire        wb_rf_we;
    wire [ 1:0] wb_rf_wsel;
    wire        wb_is_mul_div;
    wire        wb_is_ld_st;
    reg  [31:0] wb_rf_wdata;

    // Hazard, stall and redirect control.
    wire load_use_stall;
    wire ex_mul_wait = ex_is_mul_div && mul_div_busy;
    wire ex_branch_taken = (ex_npc_op == `NPC_BRA) && alu_branch;
    wire ex_is_jump = (ex_npc_op == `NPC_JMP) ||
                      (ex_npc_op == `NPC_JALR);
    wire redirect_raw = ex_branch_taken || ex_is_jump;
    wire [31:0] redirect_target =
        (ex_npc_op == `NPC_JALR) ? ((forwarded_a + ex_imm) & 32'hffff_fffe) :
                                   (ex_pc + ex_imm);
    wire ex_flush = redirect_raw && !mem_wait && !ex_mul_wait;
    wire front_hold = load_use_stall || mem_wait || ex_mul_wait;

    assign ifetch_req  = !cpu_rst && !fetch_pending && !fetch_buf_valid &&
                         !front_hold && !ex_flush;
    assign ifetch_addr = fetch_pc;
    wire fetch_accept = ifetch_req && ifetch_ready;

    wire fetch_response = ifetch_valid && fetch_pending;
    wire fetch_to_id_valid = fetch_buf_valid || fetch_response;
    wire [31:0] fetch_to_id_pc = fetch_buf_valid ? fetch_buf_pc :
                                                   fetch_pending_pc;
    wire [31:0] fetch_to_id_inst = fetch_buf_valid ? fetch_buf_inst :
                                                     ifetch_inst;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            fetch_pc         <= 32'h0;
            fetch_pending    <= 1'b0;
            fetch_pending_pc <= 32'h0;
            fetch_buf_valid  <= 1'b0;
            fetch_buf_pc     <= 32'h0;
            fetch_buf_inst   <= 32'h0000_0013;
        end else if (ex_flush) begin
            fetch_pc        <= redirect_target;
            fetch_pending   <= 1'b0;
            fetch_buf_valid <= 1'b0;
        end else begin
            if (fetch_buf_valid && !front_hold)
                fetch_buf_valid <= 1'b0;

            if (fetch_response) begin
                fetch_pending <= 1'b0;
                if (front_hold) begin
                    fetch_buf_valid <= 1'b1;
                    fetch_buf_pc    <= fetch_pending_pc;
                    fetch_buf_inst  <= ifetch_inst;
                end
            end

            if (fetch_accept) begin
                fetch_pending    <= 1'b1;
                fetch_pending_pc <= fetch_pc;
                fetch_pc         <= fetch_pc + 32'd4;
            end
        end
    end

    IF_ID U_IF_ID (
        .clk     (cpu_clk),
        .rst     (cpu_rst),
        .stall   (front_hold),
        .flush   (ex_flush),
        .if_valid(fetch_to_id_valid),
        .if_pc   (fetch_to_id_pc),
        .if_inst (fetch_to_id_inst),
        .id_pc   (id_pc),
        .id_inst (id_inst)
    );

    Controller U_CU (
        .opcode   (id_inst[6:0]),
        .funct3   (id_inst[14:12]),
        .funct7   (id_inst[31:25]),
        .npc_op   (id_npc_op),
        .sext_op  (id_sext_op),
        .alua_sel (id_alua_sel),
        .alub_sel (id_alub_sel),
        .alu_op   (id_alu_op),
        .is_mul   (),
        .is_div   (),
        .ram_r_op (id_ram_rop),
        .ram_w_op (id_ram_wop),
        .rf_we    (id_rf_we),
        .rf_wsel  (id_rf_wsel)
    );

    SEXT U_SEXT (
        .op      (id_sext_op),
        .imm     (id_inst[31:7]),
        .imm_ext (id_imm)
    );

    RF U_RF (
        .clk (cpu_clk),
        .rR1 (id_rs1),
        .rR2 (id_rs2),
        .rD1 (rf_rs1_data),
        .rD2 (rf_rs2_data),
        .we  (wb_rf_we),
        .wR  (wb_rd),
        .wD  (wb_rf_wdata)
    );

    assign id_rs1_data = wb_rf_we && (wb_rd != 5'h0) && (wb_rd == id_rs1)
                       ? wb_rf_wdata : rf_rs1_data;
    assign id_rs2_data = wb_rf_we && (wb_rd != 5'h0) && (wb_rd == id_rs2)
                       ? wb_rf_wdata : rf_rs2_data;

    assign id_is_ld_st = (id_ram_rop != `RAM_EXT_N) ||
                         (id_ram_wop != `RAM_WE_N);
    assign id_is_mul_div = (id_alu_op == `ALU_MUL)   ||
                           (id_alu_op == `ALU_MULH)  ||
                           (id_alu_op == `ALU_MULHU) ||
                           (id_alu_op == `ALU_DIV)   ||
                           (id_alu_op == `ALU_DIVU)  ||
                           (id_alu_op == `ALU_REM)   ||
                           (id_alu_op == `ALU_REMU);

    ID_EX U_ID_EX (
        .clk(cpu_clk), .rst(cpu_rst),
        .stall(mem_wait || ex_mul_wait),
        .flush(ex_flush || load_use_stall),
        .id_pc(id_pc), .id_rs1_data(id_rs1_data), .id_rs2_data(id_rs2_data),
        .id_imm(id_imm), .id_rs1(id_rs1), .id_rs2(id_rs2), .id_rd(id_rd),
        .id_alu_op(id_alu_op), .id_alua_sel(id_alua_sel),
        .id_alub_sel(id_alub_sel), .id_ram_rop(id_ram_rop),
        .id_ram_wop(id_ram_wop), .id_rf_we(id_rf_we),
        .id_rf_wsel(id_rf_wsel), .id_is_mul_div(id_is_mul_div),
        .id_is_ld_st(id_is_ld_st), .id_npc_op(id_npc_op),
        .ex_pc(ex_pc), .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data),
        .ex_imm(ex_imm), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2), .ex_rd(ex_rd),
        .ex_alu_op(ex_alu_op), .ex_alua_sel(ex_alua_sel),
        .ex_alub_sel(ex_alub_sel), .ex_ram_rop(ex_ram_rop),
        .ex_ram_wop(ex_ram_wop), .ex_rf_we(ex_rf_we),
        .ex_rf_wsel(ex_rf_wsel), .ex_is_mul_div(ex_is_mul_div),
        .ex_is_ld_st(ex_is_ld_st), .ex_npc_op(ex_npc_op)
    );

    Forwarding U_Forwarding (
        .id_rs1(ex_rs1), .id_rs2(ex_rs2),
        .mem_rd(mem_rd), .mem_rf_we(mem_rf_we),
        .wb_rd(wb_rd), .wb_rf_we(wb_rf_we),
        .forward_a(forward_a), .forward_b(forward_b)
    );

    assign forwarded_a = (forward_a == 2'b10) ? mem_forward_data :
                         (forward_a == 2'b01) ? wb_rf_wdata : ex_rs1_data;
    assign forwarded_b = (forward_b == 2'b10) ? mem_forward_data :
                         (forward_b == 2'b01) ? wb_rf_wdata : ex_rs2_data;

    ALU U_ALU (
        .rst(cpu_rst), .clk(cpu_clk), .op(ex_alu_op),
        .a(alu_a), .b(alu_b), .c(alu_c), .br(alu_branch),
        .busy(mul_div_busy)
    );

    EX_MEM U_EX_MEM (
        .clk(cpu_clk), .rst(cpu_rst), .stall(mem_wait), .flush(ex_mul_wait),
        .ex_alu_result(alu_c), .ex_rs2_data(forwarded_b), .ex_pc(ex_pc),
        .ex_imm(ex_imm), .ex_rd(ex_rd), .ex_ram_rop(ex_ram_rop),
        .ex_ram_wop(ex_ram_wop), .ex_rf_we(ex_rf_we),
        .ex_rf_wsel(ex_rf_wsel), .ex_is_mul_div(ex_is_mul_div),
        .ex_is_ld_st(ex_is_ld_st), .mem_alu_result(mem_alu_result),
        .mem_rs2_data(mem_rs2_data), .mem_pc(mem_pc), .mem_imm(mem_imm),
        .mem_rd(mem_rd), .mem_ram_rop(mem_ram_rop), .mem_ram_wop(mem_ram_wop),
        .mem_rf_we(mem_rf_we), .mem_rf_wsel(mem_rf_wsel),
        .mem_is_mul_div(mem_is_mul_div), .mem_is_ld_st(mem_is_ld_st)
    );

    MREQ U_MEM_REQ (
        .ram_addr(mem_alu_result), .ram_rop(mem_ram_rop),
        .da_ren(mem_da_ren), .da_addr(mem_da_addr),
        .ram_wop(mem_ram_wop), .ram_wdata(mem_rs2_data),
        .da_wen(mem_da_wen), .da_wdata(mem_da_wdata)
    );

    always @(*) begin
        daccess_addr  = mem_da_addr;
        daccess_wdata = mem_da_wdata;
        daccess_ren   = daccess_rvalid ? 4'h0 : mem_da_ren;
        daccess_wen   = daccess_wresp  ? 4'h0 : mem_da_wen;
    end

    MEXT U_MEM_EXT (
        .op(mem_ram_rop), .din(daccess_rdata),
        .byte_offs(mem_alu_result[1:0]), .ext(mem_load_data)
    );

    assign mem_forward_data =
        (mem_rf_wsel == `WB_PC4) ? (mem_pc + 32'd4) :
        (mem_rf_wsel == `WB_EXT) ? mem_imm :
        (mem_rf_wsel == `WB_RAM) ? mem_load_data : mem_alu_result;

    MEM_WB U_MEM_WB (
        .clk(cpu_clk), .rst(cpu_rst), .stall(1'b0), .flush(mem_wait),
        .mem_alu_result(mem_alu_result), .mem_load_data(mem_load_data),
        .mem_pc(mem_pc), .mem_imm(mem_imm), .mem_rd(mem_rd),
        .mem_rf_we(mem_rf_we), .mem_rf_wsel(mem_rf_wsel),
        .mem_is_mul_div(mem_is_mul_div), .mem_is_ld_st(mem_is_ld_st),
        .wb_alu_result(wb_alu_result), .wb_load_data(wb_load_data),
        .wb_pc(wb_pc), .wb_imm(wb_imm), .wb_rd(wb_rd),
        .wb_rf_we(wb_rf_we), .wb_rf_wsel(wb_rf_wsel),
        .wb_is_mul_div(wb_is_mul_div), .wb_is_ld_st(wb_is_ld_st)
    );

    always @(*) begin
        case (wb_rf_wsel)
            `WB_ALU: wb_rf_wdata = wb_alu_result;
            `WB_RAM: wb_rf_wdata = wb_load_data;
            `WB_PC4: wb_rf_wdata = wb_pc + 32'd4;
            `WB_EXT: wb_rf_wdata = wb_imm;
            default: wb_rf_wdata = 32'h0;
        endcase
    end

    Hazard U_Hazard (
        .id_rs1(id_rs1), .id_rs2(id_rs2), .ex_rd(ex_rd),
        .ex_is_ld_st(ex_ram_rop != `RAM_EXT_N), .ex_rf_we(ex_rf_we),
        .stall(load_use_stall), .flush()
    );

    wire [31:0] debug_wb_pc    /* verilator public */;
    wire        debug_wb_rf_we /* verilator public */;
    wire [ 4:0] debug_wb_rf_wR /* verilator public */;
    wire [31:0] debug_wb_rf_wD /* verilator public */;
    wire [31:0] debug_mem_pc    /* verilator public */;
    wire [ 3:0] debug_mem_we    /* verilator public */;
    wire [31:0] debug_mem_waddr /* verilator public */;
    wire [31:0] debug_mem_wdata /* verilator public */;

    assign debug_wb_pc    = wb_pc;
    assign debug_wb_rf_we = wb_rf_we;
    assign debug_wb_rf_wR = wb_rd;
    assign debug_wb_rf_wD = wb_rf_wdata;
    assign debug_mem_pc    = mem_pc;
    assign debug_mem_we    = daccess_wresp ? mem_da_wen : 4'h0;
    assign debug_mem_waddr = mem_da_addr;
    assign debug_mem_wdata = mem_da_wdata;

endmodule

