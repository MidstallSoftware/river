import 'helpers.dart';
import 'riscv_isa_base.dart';

sealed class MicroOp {
  const MicroOp();
}

enum MicroOpCondition { eq, ne, lt, ge, le }

enum MicroOpAluFunct { add, sub, mul, and, or, xor, sll, srl, sra, slt, sltu }

enum MicroOpSource { alu, mem, imm, rs1, rs2, sp }

enum MicroOpField { rd, rs1, rs2, imm, pc, sp }

enum MicroOpLink { ra }

enum MicroOpMemSize { byte, half, word, dword }

enum MicroOpTrap { ecall, ebreak, illegal }

class ReadRegisterMicroOp extends MicroOp {
  final MicroOpField source;
  const ReadRegisterMicroOp(this.source);

  @override
  String toString() => 'ReadRegisterMicroOp($source)';
}

class WriteRegisterMicroOp extends MicroOp {
  final MicroOpField field;
  final MicroOpSource source;
  final int offset;
  const WriteRegisterMicroOp(this.field, this.source, {this.offset = 0});

  @override
  String toString() => 'WriteRegisterMicroOp($field, $source, offset: $offset)';
}

class AluMicroOp extends MicroOp {
  final MicroOpAluFunct funct;
  final MicroOpField a;
  final MicroOpField b;
  const AluMicroOp(this.funct, this.a, this.b);

  @override
  String toString() => 'AluMicroOp($funct, $a, $b)';
}

class BranchIfMicroOp extends MicroOp {
  final MicroOpCondition condition;
  final MicroOpField target;
  final int offset;
  final MicroOpField? offsetField;
  const BranchIfMicroOp(
    this.condition,
    this.target, {
    this.offset = 0,
    this.offsetField = null,
  });

  @override
  String toString() =>
      'BranchIfMicroOp($condition, $target, $offset, $offsetField)';
}

class UpdatePCMicroOp extends MicroOp {
  final MicroOpField source;
  final int offset;
  final MicroOpField? offsetField;
  const UpdatePCMicroOp(
    this.source, {
    this.offset = 0,
    this.offsetField = null,
  });

  @override
  String toString() => 'UpdatePCMicroOp($source, $offset, $offsetField)';
}

class MemLoadMicroOp extends MicroOp {
  final MicroOpField base;
  final MicroOpMemSize size;
  final bool unsigned;
  final MicroOpField dest;

  const MemLoadMicroOp({
    required this.base,
    required this.size,
    this.unsigned = true,
    required this.dest,
  });

  @override
  String toString() =>
      'MemLoadMicroOp($base, $size, ${unsigned ? 'unsigned' : 'signed'}, $dest)';
}

class MemStoreMicroOp extends MicroOp {
  final MicroOpField base;
  final MicroOpField src;
  final MicroOpMemSize size;

  const MemStoreMicroOp({
    required this.base,
    required this.src,
    required this.size,
  });

  @override
  String toString() => 'MemStoreMicroOp($base, $src, $size)';
}

class TrapMicroOp extends MicroOp {
  final MicroOpTrap kind;
  const TrapMicroOp(this.kind);

  @override
  String toString() => 'TrapMicroOp($kind)';
}

class FenceMicroOp extends MicroOp {
  const FenceMicroOp();

  @override
  String toString() => 'FenceMicroOp()';
}

class BranchIfZeroMicroOp extends MicroOp {
  final MicroOpField field;
  final MicroOpField? offsetField;
  final int offset;

  const BranchIfZeroMicroOp({
    required this.field,
    this.offsetField,
    this.offset = 0,
  });

  @override
  String toString() => 'BranchIfZeroMicroOp($field, $offsetField, $offset)';
}

class BranchIfNonZeroMicroOp extends MicroOp {
  final MicroOpField field;
  final MicroOpField? offsetField;
  final int offset;

  const BranchIfNonZeroMicroOp({
    required this.field,
    this.offsetField,
    this.offset = 0,
  });

  @override
  String toString() => 'BranchIfNonZeroMicroOp($field, $offsetField, $offset)';
}

class WriteLinkRegisterMicroOp extends MicroOp {
  final MicroOpLink link;
  final int pcOffset;
  const WriteLinkRegisterMicroOp({required this.link, required this.pcOffset});

  @override
  String toString() => 'WriteLinkRegisterMicroOp($link, $pcOffset)';
}

class Operation<T extends InstructionType> {
  final String mnemonic;
  final int opcode;
  final int funct3;
  final int? funct7;
  final T Function(int instr) decode;
  final BitRange opcodeRange;
  final List<MicroOp> microcode;

  const Operation({
    required this.mnemonic,
    required this.opcode,
    required this.funct3,
    this.funct7,
    required this.decode,
    this.opcodeRange = Instruction.opcodeRange,
    this.microcode = const [],
  });

  bool matches(InstructionType ir) => ir.matches(opcode, funct3, funct7);

  bool checkOpcode(int instr) => opcodeRange.decode(instr) == opcode;

  @override
  String toString() =>
      'Operation(mnemonic: $mnemonic, opcode: $opcode, funct3: $funct3, funct7: $funct7, decode: $decode, microcode: $microcode)';
}

class RiscVExtension {
  final List<Operation<InstructionType>> operations;
  final String? name;
  final String? key;
  final int mask;

  const RiscVExtension(this.operations, {this.name, this.key, this.mask = 0});

  Operation<InstructionType>? findOperation(
    int opcode,
    int funct3, [
    int? funct7,
  ]) {
    for (final op in operations) {
      if (op.opcode == opcode &&
          op.funct3 == funct3 &&
          (op.funct7 == null || op.funct7 == funct7))
        return op;
    }
    return null;
  }

  @override
  String toString() => name ?? 'RiscVExtension($operations, mask: $mask)';
}
