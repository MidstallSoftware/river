import 'package:riscv/riscv.dart' hide Instruction;
import 'base.dart';
import '../data.dart';
import '../module.dart';

class IInstructionConfig {
  final String name;
  final int opcode;
  final int funct3;
  final int imm;

  const IInstructionConfig(this.name, this.opcode, this.funct3, this.imm);

  const IInstructionConfig.addi(this.imm)
    : name = 'addi',
      opcode = 0x13,
      funct3 = 0;

  const IInstructionConfig.xori(this.imm)
    : name = 'xori',
      opcode = 0x13,
      funct3 = 0x4;

  const IInstructionConfig.ori(this.imm)
    : name = 'ori',
      opcode = 0x13,
      funct3 = 0x6;

  const IInstructionConfig.andi(this.imm)
    : name = 'andi',
      opcode = 0x13,
      funct3 = 0x7;
}

class IInstruction extends Instruction {
  final IInstructionConfig config;
  final DataField rd;
  final DataField rs1;

  const IInstruction(this.config, this.rd, this.rs1);
  IInstruction.load(this.config, this.rd, {Module? module})
    : rs1 = DataField.zero(module: module);

  @override
  int? get imm => config.imm;

  @override
  DataField? get output => rd;

  @override
  List<DataField> get inputs => [rs1];

  @override
  Instruction assignOutput(DataField output) =>
      IInstruction(config, output, rs1);

  @override
  Instruction assignInputs(List<DataField> inputs) =>
      IInstruction(config, rd, inputs[0]);

  @override
  String toAsm() =>
      '${config.name} ${rd.assignedRegister!.name}, ${rs1.assignedRegister!.name}, ${config.imm}';

  @override
  InstructionType type() => IType(
    opcode: config.opcode,
    funct3: config.funct3,
    rd: rd.assignedRegister!.value,
    rs1: rs1.assignedRegister!.value,
    imm: config.imm,
  );

  @override
  String toString() => '${config.name} $rd, $rs1, ${config.imm}';
}
