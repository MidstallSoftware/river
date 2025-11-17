import 'package:riscv/riscv.dart' hide Instruction;
import 'base.dart';
import 'i.dart';
import 'r.dart';
import '../data.dart';
import '../module.dart';

class ROrIInstruction extends Instruction {
  final IInstructionConfig? i;
  final RInstructionConfig? r;

  final DataField rd;
  final DataField rs1;

  const ROrIInstruction(RInstructionConfig r, this.rd, this.rs1)
    : r = r,
      i = null;
  const ROrIInstruction.immediate(IInstructionConfig i, this.rd, this.rs1)
    : i = i,
      r = null;

  ROrIInstruction.load(RInstructionConfig r, this.rd, {Module? module})
    : r = r,
      rs1 = DataField.zero(module: module),
      i = null;
  ROrIInstruction.loadImmediate(IInstructionConfig i, this.rd, {Module? module})
    : i = i,
      rs1 = DataField.zero(module: module),
      r = null;

  @override
  DataField? get output => rd;

  @override
  List<DataField> get inputs => [rs1, if (r != null) r!.rs2];

  @override
  Instruction assignOutput(DataField output) {
    if (i == null && r != null) {
      return ROrIInstruction(r!, output, rs1);
    } else if (i != null && r == null) {
      return ROrIInstruction.immediate(i!, output, rs1);
    } else {
      throw 'Invalid encoding, rs2 and imm are both set.';
    }
  }

  @override
  Instruction assignInputs(List<DataField> inputs) {
    if (i == null && r != null) {
      return ROrIInstruction(r!.copyWith(rs2: inputs[1]), rd, inputs[0]);
    } else if (i != null && r == null) {
      return ROrIInstruction.immediate(i!, rd, inputs[0]);
    } else {
      throw 'Invalid encoding, rs2 and imm are both set.';
    }
  }

  @override
  String toAsm() {
    if (i == null && r != null) {
      return '${r!.name} ${rd.assignedRegister!.name},'
          ' ${rs1.assignedRegister!.name},'
          ' ${r!.rs2.assignedRegister!.name}';
    } else if (i != null && r == null) {
      return '${i!.name} ${rd.assignedRegister!.name},'
          ' ${rs1.assignedRegister!.name},'
          ' ${i!.imm}';
    } else {
      throw 'Invalid encoding, rs2 and imm are both set.';
    }
  }

  @override
  InstructionType type() {
    if (i == null && r != null) {
      return RType(
        opcode: r!.opcode,
        funct3: r!.funct3,
        funct7: r!.funct7,
        rd: rd.assignedRegister!.value,
        rs1: rs1.assignedRegister!.value,
        rs2: r!.rs2.assignedRegister!.value,
      );
    } else if (i != null && r == null) {
      return IType(
        opcode: i!.opcode,
        funct3: i!.funct3,
        rd: rd.assignedRegister!.value,
        rs1: rs1.assignedRegister!.value,
        imm: i!.imm,
      );
    } else {
      throw 'Invalid encoding, rs2 and imm are both set.';
    }
  }

  @override
  String toString() {
    if (i == null && r != null) {
      return '${r!.name} $rd, $rs1, ${r!.rs2}';
    } else if (i != null && r == null) {
      return '${i!.name} $rd, $rs1, ${i!.imm}';
    } else {
      throw 'Invalid encoding, rs2 and imm are both set.';
    }
  }
}
