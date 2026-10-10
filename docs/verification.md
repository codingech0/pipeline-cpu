# Trace 验证记录

最终 RTL 在课程提供的差分测试框架中完成验证。

## 测试结果

- Passed Tests: 45
- Failed Tests: 0

通过的测试：

```text
add, addi, and, andi, auipc,
beq, bge, bgeu, blt, bltu, bne,
div, divu, jal, jalr,
lb, lbu, lh, lhu, lui, lw,
mul, mulh, mulhu,
or, ori, rem, remu,
sb, sh, sll, slli,
slt, slti, sltiu, sltu,
sra, srai, srl, srli,
start, sub, sw, xor, xori
```

测试覆盖流水线前递、Load-use 停顿、控制冒险冲刷、同步访存握手、多周期乘除法、Cache 与 AXI 访问路径。

## 提交目录一致性

仓库中的 `mySoC` 与最终通过 Trace 测试的提交目录逐文件一致，共包含 30 个 Verilog / Verilog Header 文件，不包含 IP 核和 Vivado 生成文件。


