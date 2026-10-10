`timescale 1ns / 1ps
`include "defines.vh"

module Controller (
    input  wire [ 6:0] opcode,
    input  wire [ 2:0] funct3,
    input  wire [ 6:0] funct7,
    output wire [ 1:0] npc_op,
    output wire [ 2:0] sext_op,
    output wire        alua_sel,
    output wire        alub_sel,
    output wire [ 4:0] alu_op,
    output wire        is_mul,
    output wire        is_div,
    output wire [ 2:0] ram_r_op,
    output wire [ 3:0] ram_w_op,
    output wire        rf_we,
    output wire [ 1:0] rf_wsel
);

    // RV32I I-type arithmetic and shift instructions.
    wire ADDI  = (opcode == 7'b0010011) && (funct3 == 3'b000);
    wire SLLI  = (opcode == 7'b0010011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
    wire SLTI  = (opcode == 7'b0010011) && (funct3 == 3'b010);
    wire SLTIU = (opcode == 7'b0010011) && (funct3 == 3'b011);
    wire XORI  = (opcode == 7'b0010011) && (funct3 == 3'b100);
    wire SRLI  = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
    wire SRAI  = (opcode == 7'b0010011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);
    wire ORI   = (opcode == 7'b0010011) && (funct3 == 3'b110);
    wire ANDI  = (opcode == 7'b0010011) && (funct3 == 3'b111);

    // Loads.
    wire LB    = (opcode == 7'b0000011) && (funct3 == 3'b000);
    wire LH    = (opcode == 7'b0000011) && (funct3 == 3'b001);
    wire LW    = (opcode == 7'b0000011) && (funct3 == 3'b010);
    wire LBU   = (opcode == 7'b0000011) && (funct3 == 3'b100);
    wire LHU   = (opcode == 7'b0000011) && (funct3 == 3'b101);

    // Stores.
    wire SB    = (opcode == 7'b0100011) && (funct3 == 3'b000);
    wire SH    = (opcode == 7'b0100011) && (funct3 == 3'b001);
    wire SW    = (opcode == 7'b0100011) && (funct3 == 3'b010);

    // Conditional branches.
    wire BEQ   = (opcode == 7'b1100011) && (funct3 == 3'b000);
    wire BNE   = (opcode == 7'b1100011) && (funct3 == 3'b001);
    wire BLT   = (opcode == 7'b1100011) && (funct3 == 3'b100);
    wire BGE   = (opcode == 7'b1100011) && (funct3 == 3'b101);
    wire BLTU  = (opcode == 7'b1100011) && (funct3 == 3'b110);
    wire BGEU  = (opcode == 7'b1100011) && (funct3 == 3'b111);

    // Upper-immediate and jump instructions.
    wire LUI   = (opcode == 7'b0110111);
    wire AUIPC = (opcode == 7'b0010111);
    wire JAL   = (opcode == 7'b1101111);
    wire JALR  = (opcode == 7'b1100111) && (funct3 == 3'b000);

    // RV32I R-type instructions.
    wire ADD   = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    wire SUB   = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
    wire SLL   = (opcode == 7'b0110011) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
    wire SLT   = (opcode == 7'b0110011) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
    wire SLTU  = (opcode == 7'b0110011) && (funct3 == 3'b011) && (funct7 == 7'b0000000);
    wire XOR   = (opcode == 7'b0110011) && (funct3 == 3'b100) && (funct7 == 7'b0000000);
    wire SRL   = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0000000);
    wire SRA   = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0100000);
    wire OR    = (opcode == 7'b0110011) && (funct3 == 3'b110) && (funct7 == 7'b0000000);
    wire AND   = (opcode == 7'b0110011) && (funct3 == 3'b111) && (funct7 == 7'b0000000);

    // RV32M instructions.
    wire MUL   = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0000001);
    wire MULH  = (opcode == 7'b0110011) && (funct3 == 3'b001) && (funct7 == 7'b0000001);
    wire MULHU = (opcode == 7'b0110011) && (funct3 == 3'b011) && (funct7 == 7'b0000001);
    wire DIV   = (opcode == 7'b0110011) && (funct3 == 3'b100) && (funct7 == 7'b0000001);
    wire DIVU  = (opcode == 7'b0110011) && (funct3 == 3'b101) && (funct7 == 7'b0000001);
    wire REM   = (opcode == 7'b0110011) && (funct3 == 3'b110) && (funct7 == 7'b0000001);
    wire REMU  = (opcode == 7'b0110011) && (funct3 == 3'b111) && (funct7 == 7'b0000001);

    wire i_alu = ADDI | SLLI | SLTI | SLTIU | XORI | SRLI | SRAI | ORI | ANDI;
    wire r_alu = ADD | SUB | SLL | SLT | SLTU | XOR | SRL | SRA | OR | AND;
    wire load  = LB | LH | LW | LBU | LHU;
    wire store = SB | SH | SW;
    wire branch = BEQ | BNE | BLT | BGE | BLTU | BGEU;
    wire mul_op = MUL | MULH | MULHU;
    wire div_op = DIV | DIVU | REM | REMU;

    assign npc_op = JALR   ? `NPC_JALR :
                    JAL    ? `NPC_JMP  :
                    branch ? `NPC_BRA  : `NPC_PC4;

    assign rf_we = i_alu | r_alu | load | LUI | AUIPC | JAL | JALR | mul_op | div_op;

    assign rf_wsel = load          ? `WB_RAM :
                     (JAL | JALR)  ? `WB_PC4 :
                     LUI           ? `WB_EXT : `WB_ALU;

    assign sext_op = store             ? `EXT_S :
                     branch            ? `EXT_B :
                     (LUI | AUIPC)      ? `EXT_U :
                     JAL                ? `EXT_J : `EXT_I;

    assign alu_op = (ADDI | ADD | load | store | AUIPC | JALR) ? `ALU_ADD  :
                    SUB                                      ? `ALU_SUB  :
                    (ORI | OR)                               ? `ALU_OR   :
                    (XORI | XOR)                             ? `ALU_XOR  :
                    (SLLI | SLL)                             ? `ALU_SLL  :
                    (SRLI | SRL)                             ? `ALU_SRL  :
                    (SRAI | SRA)                             ? `ALU_SRA  :
                    (ANDI | AND)                             ? `ALU_AND  :
                    BEQ                                      ? `ALU_EQ   :
                    BNE                                      ? `ALU_NE   :
                    (BLT | SLT | SLTI)                       ? `ALU_LT   :
                    (BLTU | SLTU | SLTIU)                    ? `ALU_LTU  :
                    BGE                                      ? `ALU_GE   :
                    BGEU                                     ? `ALU_GEU  :
                    MUL                                      ? `ALU_MUL  :
                    MULH                                     ? `ALU_MULH :
                    MULHU                                    ? `ALU_MULHU :
                    DIV                                      ? `ALU_DIV  :
                    DIVU                                     ? `ALU_DIVU :
                    REM                                      ? `ALU_REM  :
                    REMU                                     ? `ALU_REMU : `ALU_ADD;

    assign alua_sel = AUIPC ? `ALU_A_PC : `ALU_A_RS1;

    assign alub_sel = (i_alu | load | store | AUIPC | JALR)
                    ? `ALU_B_EXT : `ALU_B_RS2;

    assign ram_r_op = LB  ? `RAM_EXT_B  :
                      LBU ? `RAM_EXT_BU :
                      LH  ? `RAM_EXT_H  :
                      LHU ? `RAM_EXT_HU :
                      LW  ? `RAM_EXT_W  : `RAM_EXT_N;

    assign ram_w_op = SB ? `RAM_WE_B :
                      SH ? `RAM_WE_H :
                      SW ? `RAM_WE_W : `RAM_WE_N;

    assign is_mul = mul_op;
    assign is_div = div_op;

endmodule

