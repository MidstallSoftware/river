import 'helpers.dart';
import 'riscv_isa_base.dart';

sealed class MicroOp {
  const MicroOp();
}

enum MicroOpCondition { eq, ne, lt, gt, ge, le }

enum MicroOpAluFunct {
  add,
  sub,
  mul,
  and,
  or,
  xor,
  sll,
  srl,
  sra,
  slt,
  sltu,
  masked,
  mulh,
  mulhsu,
  mulhu,
  div,
  divu,
  rem,
  remu,
}

enum MicroOpAtomicFunct { add, swap, xor, and, or, min, max, minu, maxu }

enum MicroOpSource { alu, mem, imm, rs1, rs2, sp }

enum MicroOpField { rd, rs1, rs2, imm, pc, sp }

enum MicroOpLink {
  ra(Register.x1);

  const MicroOpLink(this.reg);

  final Register reg;
}

enum MicroOpMemSize {
  byte(1),
  half(2),
  word(4),
  dword(8);

  const MicroOpMemSize(this.bytes);

  final int bytes;

  int get bits => bytes * 8;
}

class ReadCsrMicroOp extends MicroOp {
  final MicroOpField source;

  const ReadCsrMicroOp(this.source);

  @override
  String toString() => 'ReadCsrMicroOp($source)';
}

class WriteCsrMicroOp extends MicroOp {
  final MicroOpField field;
  final MicroOpSource source;
  final int offset;

  const WriteCsrMicroOp(this.field, this.source, {this.offset = 0});

  @override
  String toString() => 'WriteCsrMicroOp($field, $source, offset: $offset)';
}

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

class ModifyLatchMicroOp extends MicroOp {
  final MicroOpField field;
  final MicroOpSource source;
  final bool replace;

  const ModifyLatchMicroOp(this.field, this.source, this.replace);

  @override
  String toString() => 'ModifyLatchMicroOp($field, $source, $replace)';
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
  final MicroOpSource target;
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
  final Trap kindMachine;
  final Trap? kindSupervisor;
  final Trap? kindUser;

  const TrapMicroOp(this.kindMachine, this.kindSupervisor, this.kindUser);
  const TrapMicroOp.one(this.kindMachine)
    : kindSupervisor = null,
      kindUser = null;

  @override
  String toString() => 'TrapMicroOp($kindMachine, $kindSupervisor, $kindUser)';
}

class TlbFenceMicroOp extends MicroOp {
  const TlbFenceMicroOp();

  @override
  String toString() => 'TlbFenceMicroOp()';
}

class TlbInvalidateMicroOp extends MicroOp {
  final MicroOpField addrField;
  final MicroOpField asidField;

  const TlbInvalidateMicroOp({
    required this.addrField,
    required this.asidField,
  });

  @override
  String toString() =>
      'TlbInvalidateMicroOp(addrField: $addrField, asidField: $asidField)';
}

class FenceMicroOp extends MicroOp {
  const FenceMicroOp();

  @override
  String toString() => 'FenceMicroOp()';
}

class ReturnMicroOp extends MicroOp {
  final PrivilegeMode mode;

  const ReturnMicroOp(this.mode);

  @override
  String toString() => 'ReturnMicroOp($mode)';
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

class InterruptHoldMicroOp extends MicroOp {
  const InterruptHoldMicroOp();

  @override
  String toString() => 'InterruptHoldMicroOp()';
}

class LoadReservedMicroOp extends MicroOp {
  final MicroOpField base;
  final MicroOpField dest;
  final MicroOpMemSize size;

  const LoadReservedMicroOp(this.base, this.dest, this.size);

  @override
  String toString() => 'LoadReservedMicroOp($base, $dest, $size)';
}

class StoreConditionalMicroOp extends MicroOp {
  final MicroOpField base;
  final MicroOpField src;
  final MicroOpField dest;
  final MicroOpMemSize size;

  const StoreConditionalMicroOp({
    required this.base,
    required this.src,
    required this.dest,
    required this.size,
  });

  @override
  String toString() => 'StoreConditionalMicroOp($base, $src, $dest, $size)';
}

class AtomicMemoryMicroOp extends MicroOp {
  final MicroOpAtomicFunct funct;
  final MicroOpField base;
  final MicroOpField src;
  final MicroOpField dest;
  final MicroOpMemSize size;

  const AtomicMemoryMicroOp({
    required this.funct,
    required this.base,
    required this.src,
    required this.dest,
    required this.size,
  });

  @override
  String toString() => 'AtomicMemoryMicroOp($funct, $base, $src, $dest, $size)';
}

class Operation<T extends InstructionType> {
  final String mnemonic;
  final int opcode;
  final int funct3;
  final int? funct7;
  final int? funct12;
  final T Function(int instr) decode;
  final BitRange opcodeRange;
  final List<PrivilegeMode> allowedLevels;
  final List<MicroOp> microcode;

  const Operation({
    required this.mnemonic,
    required this.opcode,
    required this.funct3,
    this.funct7,
    this.funct12,
    required this.decode,
    this.opcodeRange = Instruction.opcodeRange,
    this.allowedLevels = PrivilegeMode.values,
    this.microcode = const [],
  });

  bool matches(InstructionType ir) =>
      ir.matches(opcode, funct3, funct7, funct12);

  bool checkOpcode(int instr) => opcodeRange.decode(instr) == opcode;

  @override
  String toString() =>
      'Operation(mnemonic: $mnemonic, opcode: $opcode, funct3: $funct3,'
      ' funct7: $funct7, funct12: $funct12, decode: $decode,'
      ' allowedLevels: $allowedLevels, microcode: $microcode)';
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
