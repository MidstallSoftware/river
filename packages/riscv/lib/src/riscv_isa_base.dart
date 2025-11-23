import 'helpers.dart';

const int kInstructionBits = 32;
const int kInstructionBytes = kInstructionBits ~/ 8;

enum PrivilegeMode {
  machine(3),
  supervisor(1),
  user(0);

  const PrivilegeMode(this.id);

  final int id;

  static PrivilegeMode? find(int id) {
    for (final mode in PrivilegeMode.values) {
      if (mode.id == id) return mode;
    }
    return null;
  }
}

enum Trap {
  instructionMisaligned(0, 0, 0, false),
  instructionAccessFault(1, 1, 1, false),
  illegal(2, 2, 2, false),
  breakpoint(3, 3, 3, false),

  misalignedLoad(4, 4, 4, false),
  loadAccess(5, 5, 5, false),

  misalignedStore(6, 6, 6, false),
  storeAccess(7, 7, 7, false),

  ecallU(8, 8, 8, false),
  ecallS(9, 9, 9, false),
  ecallM(11, 11, 11, false),

  instructionPageFault(12, 12, 12, false),
  loadPageFault(13, 13, 13, false),
  storePageFault(15, 15, 15, false),

  userSoftware(0, 0, 0, true),
  supervisorSoftware(1, 1, 1, true),
  machineSoftware(3, 3, 3, true),

  userTimer(4, 4, 4, true),
  supervisorTimer(5, 5, 5, true),
  machineTimer(7, 7, 7, true),

  userExternal(8, 8, 8, true),
  supervisorExternal(9, 9, 9, true),
  machineExternal(11, 11, 11, true);

  final int mcauseCode;
  final int scauseCode;
  final int ucauseCode;
  final bool interrupt;

  const Trap(this.mcauseCode, this.scauseCode, this.ucauseCode, this.interrupt);

  int mcause(int xlen) => (interrupt ? (1 << (xlen - 1)) : 0) | mcauseCode;
  int scause(int xlen) => (interrupt ? (1 << (xlen - 1)) : 0) | scauseCode;
  int ucause(int xlen) => (interrupt ? (1 << (xlen - 1)) : 0) | ucauseCode;
}

enum PagingMode {
  bare(
    0,
    levels: 0,
    vpnBits: 0,
    supportedMxlens: [Mxlen.mxlen_32, Mxlen.mxlen_64],
  ),
  sv32(
    1,
    levels: 2,
    vpnBits: 10,
    supportedMxlens: [Mxlen.mxlen_32, Mxlen.mxlen_64],
  ),
  sv39(8, levels: 3, vpnBits: 9, supportedMxlens: [Mxlen.mxlen_64]),
  sv48(9, levels: 4, vpnBits: 9, supportedMxlens: [Mxlen.mxlen_64]),
  sv57(10, levels: 5, vpnBits: 9, supportedMxlens: [Mxlen.mxlen_64]);

  const PagingMode(
    this.id, {
    required this.levels,
    required this.vpnBits,
    required this.supportedMxlens,
  });

  final int id;
  final int levels;
  final int vpnBits;
  final List supportedMxlens;

  bool isSupported(Mxlen mxlen) => supportedMxlens.contains(mxlen);

  static PagingMode? fromId(int id) {
    for (final mode in PagingMode.values) {
      if (mode.id == id) return mode;
    }

    return null;
  }
}

abstract class InstructionType {
  /// The opcode which to execute
  final int opcode;
  final int? funct3;
  final int? funct7;

  const InstructionType({required this.opcode, this.funct3, this.funct7});

  const InstructionType.map(Map<String, int> map)
    : opcode = map['opcode']!,
      funct3 = map['funct3'],
      funct7 = map['funct7'];

  int get imm => 0;

  bool matches(int bOpcode, int? bFunct3, int? bFunct7) =>
      opcode == bOpcode && funct3 == bFunct3 && funct7 == bFunct7;

  Map<String, int> toMap();

  @override
  String toString() =>
      '${runtimeType.toString()}(opcode: $opcode, funct3: $funct3, funct7: $funct7)';
}

/// R-Type RISC-V instruction
class RType extends InstructionType {
  /// The result-data register
  final int rd;

  /// Data 1
  final int rs1;

  /// Data 2
  final int rs2;

  const RType({
    required super.opcode,
    required this.rd,
    required super.funct3,
    required this.rs1,
    required this.rs2,
    required super.funct7,
  });

  const RType.map(Map<String, int> map)
    : rd = map['rd']!,
      rs1 = map['rs1']!,
      rs2 = map['rs2']!,
      super.map(map);

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rd': rd,
    'funct3': funct3!,
    'rs1': rs1,
    'rs2': rs2,
    'funct7': funct7!,
  };

  @override
  String toString() =>
      'RType(opcode: $opcode, rd: $rd, funct3: $funct3, rs1: $rs1, rs2: $rs2, funct7: $funct7)';

  static const BitStruct STRUCT = const BitStruct({
    'opcode': Instruction.opcodeRange,
    'rd': const BitRange(7, 11),
    'funct3': const BitRange(12, 14),
    'rs1': const BitRange(15, 19),
    'rs2': const BitRange(20, 24),
    'funct7': const BitRange(25, 31),
  });
}

/// I-Type RISC-V instruction
class IType extends InstructionType {
  final int _imm;

  /// The result-data register
  final int rd;

  /// Data 1
  final int rs1;

  const IType({
    required super.opcode,
    required this.rd,
    required super.funct3,
    required this.rs1,
    required int imm,
  }) : _imm = imm;

  const IType.map(Map<String, int> map)
    : rd = map['rd']!,
      rs1 = map['rs1']!,
      _imm = map['imm']!,
      super.map(map);

  @override
  int get imm => _imm;

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rd': rd,
    'funct3': funct3!,
    'rs1': rs1,
    'imm': imm,
  };

  @override
  String toString() =>
      'IType(opcode: $opcode, rd: $rd, funct3: $funct3, rs1: $rs1, imm: $imm)';

  static const BitStruct STRUCT = const BitStruct({
    'opcode': Instruction.opcodeRange,
    'rd': const BitRange(7, 11),
    'funct3': const BitRange(12, 14),
    'rs1': const BitRange(15, 19),
    'imm': const BitRange(20, 31),
  });
}

/// S-Type RISC-V instruction
class SType extends InstructionType {
  /// Bits 0:4 of the immediate
  final int imm4_0;

  /// Data 1
  final int rs1;

  /// Data 2
  final int rs2;

  /// Bits 5:11 of the immediate
  final int imm11_5;

  const SType({
    required super.opcode,
    required this.imm4_0,
    required super.funct3,
    required this.rs1,
    required this.rs2,
    required this.imm11_5,
  });

  const SType.map(Map<String, int> map)
    : imm4_0 = map['imm[4:0]']!,
      rs1 = map['rs1']!,
      rs2 = map['rs2']!,
      imm11_5 = map['imm[11:5]']!,
      super.map(map);

  @override
  int get imm {
    var value = (imm11_5 << 5) | imm4_0;

    if ((value & 0x800) != 0) {
      value |= ~0xFFFFF000;
    }

    return value;
  }

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'imm[4:0]': imm4_0,
    'funct3': funct3!,
    'rs1': rs1,
    'rs2': rs2,
    'imm[11:5]': imm11_5,
  };

  @override
  String toString() =>
      'SType(opcode: $opcode, imm[4:0]: $imm4_0, funct3: $funct3, rs1: $rs1, rs2: $rs2, imm[11:5]: $imm11_5)';

  static const BitStruct STRUCT = const BitStruct({
    'opcode': Instruction.opcodeRange,
    'imm[4:0]': const BitRange(7, 11),
    'funct3': const BitRange(12, 14),
    'rs1': const BitRange(15, 19),
    'rs2': const BitRange(20, 24),
    'imm[11:5]': const BitRange(25, 31),
  });
}

/// B-Type RISC-V instruction
class BType extends InstructionType {
  final int imm11;
  final int imm4_1;
  final int rs1;
  final int rs2;
  final int imm10_5;
  final int imm12;

  const BType({
    required super.opcode,
    required this.imm11,
    required this.imm4_1,
    required super.funct3,
    required this.rs1,
    required this.rs2,
    required this.imm10_5,
    required this.imm12,
  });

  const BType.map(Map<String, int> map)
    : imm11 = map['imm[11]']!,
      imm4_1 = map['imm[4:1]']!,
      rs1 = map['rs1']!,
      rs2 = map['rs2']!,
      imm10_5 = map['imm[10:5]']!,
      imm12 = map['imm[12]']!,
      super.map(map);

  @override
  int get imm {
    int value = (imm12 << 12) | (imm11 << 11) | (imm10_5 << 5) | (imm4_1 << 1);

    if ((value & 0x1000) != 0) value |= ~0x1FFF;
    return value;
  }

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'imm[11]': imm11,
    'imm[4:1]': imm4_1,
    'funct3': funct3!,
    'rs1': rs1,
    'rs2': rs2,
    'imm[10:5]': imm10_5,
    'imm[12]': imm12,
  };

  @override
  String toString() =>
      'BType(opcode: $opcode, imm[11]: $imm11, imm[4:1]: $imm4_1, funct3: $funct3, rs1: $rs1, rs2: $rs2, imm[10:5]: $imm10_5, imm[12]: $imm12)';

  static const BitStruct STRUCT = const BitStruct({
    'opcode': Instruction.opcodeRange,
    'imm[11]': const BitRange.single(7),
    'imm[4:1]': const BitRange(8, 11),
    'funct3': const BitRange(12, 14),
    'rs1': const BitRange(15, 19),
    'rs2': const BitRange(20, 24),
    'imm[10:5]': const BitRange(25, 30),
    'imm[12]': const BitRange.single(31),
  });
}

/// U-Type RISC-V instruction
class UType extends InstructionType {
  /// The result-data register
  final int rd;

  /// The immediate value
  final int shifted_imm;

  const UType({required super.opcode, required this.rd, required int imm})
    : shifted_imm = imm >> 12,
      super(funct3: 0);

  UType.map(Map<String, int> map)
    : rd = map['rd']!,
      shifted_imm = map['imm']!,
      super.map({...map, 'funct3': 0});

  @override
  int get imm => shifted_imm << 12;

  @override
  bool matches(int bOpcode, int? bFunct3, int? bFunct7) =>
      opcode == bOpcode && bFunct3 == null && bFunct7 == null;

  @override
  Map<String, int> toMap() => {'opcode': opcode, 'rd': rd, 'imm': shifted_imm};

  @override
  String toString() => 'UType(opcode: $opcode, rd: $rd, imm: $shifted_imm)';

  static const BitStruct STRUCT = const BitStruct({
    'opcode': Instruction.opcodeRange,
    'rd': const BitRange(7, 11),
    'imm': const BitRange(12, 31),
  });
}

/// J-Type RISC-V instruction
class JType extends InstructionType {
  final int rd;
  final int imm19_12;
  final int imm11;
  final int imm10_1;
  final int imm20;

  const JType({
    required super.opcode,
    required this.rd,
    required this.imm19_12,
    required this.imm11,
    required this.imm10_1,
    required this.imm20,
  });

  const JType.map(Map<String, int> map)
    : rd = map['rd']!,
      imm19_12 = map['imm[19:12]']!,
      imm11 = map['imm[11]']!,
      imm10_1 = map['imm[10:1]']!,
      imm20 = map['imm[20]']!,
      super.map(map);

  @override
  int get imm {
    int value =
        (imm20 << 20) | (imm19_12 << 12) | (imm11 << 11) | (imm10_1 << 1);
    if ((value & 0x100000) != 0) value |= ~0x1FFFFF;
    return value;
  }

  @override
  bool matches(int bOpcode, int? _bFunct3, int? _bFunct7) => opcode == bOpcode;

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rd': rd,
    'imm[19:12]': imm19_12,
    'imm[11]': imm11,
    'imm[10:1]': imm10_1,
    'imm[20]': imm20,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': Instruction.opcodeRange,
    'rd': const BitRange(7, 11),
    'imm[19:12]': const BitRange(12, 19),
    'imm[11]': const BitRange.single(20),
    'imm[10:1]': const BitRange(21, 30),
    'imm[20]': const BitRange.single(31),
  });
}

/// RISC-V instruction
class Instruction {
  final InstructionType value;

  const Instruction.r(RType r) : value = r;
  const Instruction.i(IType i) : value = i;
  const Instruction.s(SType s) : value = s;
  const Instruction.b(BType b) : value = b;
  const Instruction.u(UType u) : value = u;
  const Instruction.j(JType j) : value = j;

  int get opcode => value.opcode;
  Map<String, int> toMap() => value.toMap();

  BitStruct get struct {
    if (value is RType) return RType.STRUCT;
    if (value is IType) return IType.STRUCT;
    if (value is SType) return SType.STRUCT;
    if (value is BType) return BType.STRUCT;
    if (value is UType) return UType.STRUCT;
    if (value is JType) return JType.STRUCT;

    throw 'Unreachable';
  }

  @override
  String toString() => value.toString();

  static const opcodeRange = const BitRange(0, 6);
}

enum Register {
  x0(0, 'zero'),
  x1(1, 'ra'),
  x2(2, 'sp'),
  x3(3, 'gp'),
  x4(4, 'tp'),
  x5(5, 't0'),
  x6(6, 't1'),
  x7(7, 't2'),
  x8(8, 's0'),
  x9(9, 's1'),
  x10(10, 'a0'),
  x11(11, 'a1'),
  x12(12, 'a2'),
  x13(13, 'a3'),
  x14(14, 'a4'),
  x15(15, 'a5'),
  x16(16, 'a6'),
  x17(17, 'a7'),
  x18(18, 's2'),
  x19(19, 's3'),
  x20(20, 's4'),
  x21(21, 's5'),
  x22(22, 's6'),
  x23(23, 's7'),
  x24(24, 's8'),
  x25(25, 's9'),
  x26(26, 's10'),
  x27(27, 's11'),
  x28(28, 't3'),
  x29(29, 't4'),
  x30(30, 't5'),
  x31(31, 't6');

  const Register(this.value, this.abi);

  final int value;
  final String abi;
}

enum Mxlen {
  mxlen_32(32, 1 << 30, 0x003F_FFFF, 0x3FF, 22),
  mxlen_64(64, 1 << 62, 0x0FFF_FFFF_FFFF, 0xF, 60);

  const Mxlen(
    this.size,
    this.misa,
    this.satpPpnMask,
    this.satpModeMask,
    this.satpModeShift,
  );

  final int size;
  final int misa;
  final int satpPpnMask;
  final int satpModeMask;
  final int satpModeShift;

  int get width => size ~/ 8;
}
