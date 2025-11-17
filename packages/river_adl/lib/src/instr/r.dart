import 'package:riscv/riscv.dart' hide Instruction;
import 'base.dart';
import '../data.dart';
import '../module.dart';

class RInstructionConfig {
  final String name;
  final int opcode;
  final int funct3;
  final int funct7;
  final DataField rs2;

  const RInstructionConfig(
    this.name,
    this.opcode,
    this.funct3,
    this.funct7,
    this.rs2,
  );

  const RInstructionConfig.add(this.rs2)
    : name = 'add',
      opcode = 0x33,
      funct3 = 0,
      funct7 = 0;

  const RInstructionConfig.sub(this.rs2)
    : name = 'sub',
      opcode = 0x33,
      funct3 = 0,
      funct7 = 0x20;

  const RInstructionConfig.xor(this.rs2)
    : name = 'xor',
      opcode = 0x33,
      funct3 = 0x4,
      funct7 = 0x0;

  const RInstructionConfig.or(this.rs2)
    : name = 'or',
      opcode = 0x33,
      funct3 = 0x6,
      funct7 = 0x0;

  const RInstructionConfig.and(this.rs2)
    : name = 'and',
      opcode = 0x33,
      funct3 = 0x7,
      funct7 = 0x0;

  RInstructionConfig copyWith({DataField? rs2}) =>
      RInstructionConfig(name, opcode, funct3, funct7, rs2 ?? this.rs2);
}

class RInstruction extends Instruction {
  final RInstructionConfig config;
  final DataField rd;
  final DataField rs1;

  const RInstruction(this.config, this.rd, this.rs1);
  RInstruction.load(this.config, this.rd, {Module? module})
    : rs1 = DataField.zero(module: module);

  @override
  DataField? get output => rd;

  @override
  List<DataField> get inputs => [rs1, config.rs2];

  @override
  Instruction assignOutput(DataField output) =>
      RInstruction(config, output, rs1);

  @override
  Instruction assignInputs(List<DataField> inputs) =>
      RInstruction(config.copyWith(rs2: inputs[1]), rd, inputs[0]);

  @override
  String toAsm() =>
      '${config.name} ${rd.assignedRegister!.name}, ${rs1.assignedRegister!.name}, ${config.rs2.assignedRegister!.name}';

  @override
  InstructionType type() => RType(
    opcode: config.opcode,
    funct3: config.funct3,
    funct7: config.funct7,
    rd: rd.assignedRegister!.value,
    rs1: rs1.assignedRegister!.value,
    rs2: config.rs2.assignedRegister!.value,
  );

  @override
  String toString() => '${config.name} $rd, $rs1, ${config.rs2}';
}
