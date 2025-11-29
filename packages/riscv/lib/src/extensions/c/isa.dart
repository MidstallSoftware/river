import '../../riscv_isa_base.dart';
import '../../helpers.dart';

const kCompressedRegisterMap = <CompressedRegister, Register>{
  CompressedRegister.x8: Register.x8,
  CompressedRegister.x9: Register.x9,
  CompressedRegister.x10: Register.x10,
  CompressedRegister.x11: Register.x11,
  CompressedRegister.x12: Register.x12,
  CompressedRegister.x13: Register.x13,
  CompressedRegister.x14: Register.x14,
  CompressedRegister.x15: Register.x15,
};

/// Compressed registers
enum CompressedRegister {
  x8(8, 's0'),
  x9(9, 's1'),
  x10(10, 'a0'),
  x11(11, 'a1'),
  x12(12, 'a2'),
  x13(13, 'a3'),
  x14(14, 'a4'),
  x15(15, 'a5');

  const CompressedRegister(this.value, this.abi);

  final int value;
  final String abi;

  /// Gets the full register
  Register get full => kCompressedRegisterMap[this]!;

  /// Gets from the full register
  static CompressedRegister? fromFull(Register r) =>
      kCompressedRegisterMap.map((k, v) => MapEntry(v, k))[r];
}

/// Compressed R-Type RISC-V instruction
class CompressedRType extends InstructionType {
  final int rs2;
  final int rs1;

  const CompressedRType({
    required super.opcode,
    required this.rs2,
    required this.rs1,
    required super.funct4,
  });

  const CompressedRType.map(Map<String, int> map)
    : rs2 = map['rs2']!,
      rs1 = map['rs1']!,
      super.map(map);

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rs2': rs2,
    'rs1': rs1,
    'funct4': funct4!,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'rs2': const BitRange(2, 6),
    'rs1': const BitRange(7, 11),
    'funct4': const BitRange(12, 15),
  });
}

/// Compressed I-Type RISC-V instruction
class CompressedIType extends InstructionType {
  final int imm4_0;
  final int rs1;
  final int imm5;
  final int funct3;

  const CompressedIType({
    required super.opcode,
    required this.imm4_0,
    required this.rs1,
    required this.imm5,
    required this.funct3,
  });

  const CompressedIType.map(Map<String, int> map)
    : imm4_0 = map['imm[4:0]']!,
      rs1 = map['rs1']!,
      imm5 = map['imm[5]']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  int get imm => signExtend(imm5 << 5 | imm4_0, 6);

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'imm[4:0]': imm4_0,
    'rs1': rs1,
    'imm[5]': imm5,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'imm[4:0]': const BitRange(2, 6),
    'rs1': const BitRange(7, 11),
    'imm[5]': const BitRange.single(12),
    'funct3': const BitRange(13, 15),
  });
}

/// Compressed SS-Type RISC-V instruction
class CompressedSSType extends InstructionType {
  final int rs2;
  final int imm;
  final int funct3;

  const CompressedSSType({
    required super.opcode,
    required this.rs2,
    required this.imm,
    required this.funct3,
  });

  const CompressedSSType.map(Map<String, int> map)
    : rs2 = map['rs2']!,
      imm = map['imm']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rs2': rs2,
    'imm': imm,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'rs2': const BitRange(2, 6),
    'imm': const BitRange(7, 12),
    'funct3': const BitRange(13, 15),
  });
}

/// Compressed WI-Type RISC-V instruction
class CompressedWIType extends InstructionType {
  final int _imm;

  final int rd;
  final int funct3;

  const CompressedWIType({
    required super.opcode,
    required this.rd,
    required int imm,
    required this.funct3,
  }) : _imm = imm;

  const CompressedWIType.map(Map<String, int> map)
    : rd = map['rd']!,
      _imm = map['imm']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  int get imm => _imm;

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rd': rd,
    'imm': imm,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'rd': const BitRange(2, 4),
    'imm': const BitRange(5, 12),
    'funct3': const BitRange(13, 15),
  });
}

/// Compressed L-Type RISC-V instruction
class CompressedLType extends InstructionType {
  final int rd;
  final int imm2_6;
  final int rs1;
  final int imm5_3;
  final int funct3;

  const CompressedLType({
    required super.opcode,
    required this.rd,
    required this.imm2_6,
    required this.rs1,
    required this.imm5_3,
    required this.funct3,
  });

  const CompressedLType.map(Map<String, int> map)
    : rd = map['rd']!,
      imm2_6 = map['imm[2:6]']!,
      rs1 = map['rs1']!,
      imm5_3 = map['imm[5:3]']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  int get imm {
    final uimm2 = (imm2_6 & 0x1);
    final uimm3 = (imm5_3 & 0x1);
    final uimm4 = (imm5_3 >> 1) & 0x1;
    final uimm5 = (imm5_3 >> 2) & 0x1;
    return (uimm5 << 5) | (uimm4 << 4) | (uimm3 << 3) | (uimm2 << 2);
  }

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rd': rd,
    'imm[2:6]': imm2_6,
    'rs1': rs1,
    'imm[5:3]': imm5_3,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'rd': const BitRange(2, 4),
    'imm[2:6]': const BitRange(5, 6),
    'rs1': const BitRange(7, 9),
    'imm[5:3]': const BitRange(10, 12),
    'funct3': const BitRange(13, 15),
  });
}

/// Compressed S-Type RISC-V instruction
class CompressedSType extends InstructionType {
  final int rs2;
  final int imm2_6;
  final int rs1;
  final int imm5_3;
  final int funct3;

  const CompressedSType({
    required super.opcode,
    required this.rs2,
    required this.imm2_6,
    required this.rs1,
    required this.imm5_3,
    required this.funct3,
  });

  const CompressedSType.map(Map<String, int> map)
    : rs2 = map['rs2']!,
      imm2_6 = map['imm[2:6]']!,
      rs1 = map['rs1']!,
      imm5_3 = map['imm[5:3]']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  int get imm {
    final uimm2 = (imm2_6 & 0x1);
    final uimm3 = (imm5_3 & 0x1);
    final uimm4 = (imm5_3 >> 1) & 0x1;
    final uimm5 = (imm5_3 >> 2) & 0x1;
    return (uimm5 << 5) | (uimm4 << 4) | (uimm3 << 3) | (uimm2 << 2);
  }

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rs2': rs2,
    'imm[2:6]': imm2_6,
    'rs1': rs1,
    'imm[5:3]': imm5_3,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'rs2': const BitRange(2, 4),
    'imm[2:6]': const BitRange(5, 6),
    'rs1': const BitRange(7, 9),
    'imm[5:3]': const BitRange(10, 12),
    'funct3': const BitRange(13, 15),
  });
}

/// Compressed A-Type RISC-V instruction
class CompressedAType extends InstructionType {
  final int rs2;
  final int funct2;
  final int rs1;
  final int funct6;

  const CompressedAType({
    required super.opcode,
    required this.rs2,
    required this.funct2,
    required this.rs1,
    required this.funct6,
  });

  const CompressedAType.map(Map<String, int> map)
    : rs2 = map['rs2']!,
      funct2 = map['funct2']!,
      rs1 = map['rs1']!,
      funct6 = map['funct6']!,
      super.map(map);

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rs2': rs2,
    'funct2': funct2,
    'rs1': rs1,
    'funct6': funct6,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'rs2': const BitRange(2, 4),
    'funct2': const BitRange(5, 6),
    'rs1': const BitRange(7, 9),
    'funct6': const BitRange(10, 15),
  });
}

/// Compressed B-Type RISC-V instruction
class CompressedBType extends InstructionType {
  final int offset1;
  final int rs1;
  final int offset2;
  final int funct3;

  const CompressedBType({
    required super.opcode,
    required this.offset1,
    required this.rs1,
    required this.offset2,
    required this.funct3,
  });

  const CompressedBType.map(Map<String, int> map)
    : offset1 = map['offset1']!,
      rs1 = map['rs1']!,
      offset2 = map['offset2']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  int get imm => (offset2 << 5) | offset1;

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'offset1': offset1,
    'rs1': rs1,
    'offset2': offset2,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'offset1': const BitRange(2, 6),
    'rs1': const BitRange(7, 9),
    'offset2': const BitRange(10, 12),
    'funct3': const BitRange(13, 15),
  });
}

/// Compressed J-Type RISC-V instruction
class CompressedJType extends InstructionType {
  final int value;
  final int funct3;

  const CompressedJType({
    required super.opcode,
    required this.value,
    required this.funct3,
  });

  const CompressedJType.map(Map<String, int> map)
    : value = map['value']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  int get imm => signExtend(value << 1, 12);

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'value': value,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'value': const BitRange(2, 12),
    'funct3': const BitRange(13, 15),
  });
}

class CompressedLwspType extends InstructionType {
  final int imm0_4;
  final int rd;
  final int imm5;
  final int funct3;

  const CompressedLwspType({
    required super.opcode,
    required this.imm0_4,
    required this.rd,
    required this.imm5,
    required this.funct3,
  });

  const CompressedLwspType.map(Map<String, int> map)
    : imm0_4 = map['imm[0:4]']!,
      rd = map['rd']!,
      imm5 = map['imm[5]']!,
      funct3 = map['funct3']!,
      super.map(map);

  @override
  int get imm =>
      ((imm5 & 1) << 5) |
      ((imm0_4 >> 4) & 1) << 4 |
      ((imm0_4 >> 3) & 1) << 3 |
      ((imm0_4 >> 2) & 1) << 2 |
      ((imm0_4 >> 0) & 1) << 6;

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'imm[0:4]': imm0_4,
    'rd': rd,
    'imm[5]': imm5,
    'funct3': funct3,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'imm[0:4]': const BitRange(2, 6),
    'rd': const BitRange(7, 11),
    'imm[5]': const BitRange.single(12),
    'funct3': const BitRange(13, 15),
  });
}

class CompressedSwspType extends InstructionType {
  final int rs2;
  final int _imm;

  const CompressedSwspType({
    required super.opcode,
    required this.rs2,
    required int imm,
    required super.funct3,
  }) : _imm = imm;

  const CompressedSwspType.map(Map<String, int> map)
    : rs2 = map['rs2']!,
      _imm = map['imm']!,
      super.map(map);

  @override
  int get imm {
    final imm2 = (_imm >> 2) & 1;
    final imm3 = (_imm >> 3) & 1;
    final imm4 = (_imm >> 4) & 1;
    final imm5 = (_imm >> 5) & 1;
    final imm6 = (_imm >> 1) & 1;
    return (imm6 << 6) | (imm5 << 5) | (imm4 << 4) | (imm3 << 3) | (imm2 << 2);
  }

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'rs2': rs2,
    'imm': _imm,
    'funct3': funct3!,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'rs2': const BitRange(2, 6),
    'imm': const BitRange(7, 12),
    'funct3': const BitRange(13, 15),
  });
}

class CompressedCbType extends InstructionType {
  final int shamt;
  final int shamt5;
  final int rs1;

  const CompressedCbType({
    required super.opcode,
    required this.shamt,
    required this.shamt5,
    required super.funct2,
    required this.rs1,
    required super.funct3,
  });

  const CompressedCbType.map(Map<String, int> map)
    : shamt = map['shamt']!,
      rs1 = map['rs1']!,
      shamt5 = map['shamt5']!,
      super.map(map);

  @override
  int get imm => shamt;

  @override
  Map<String, int> toMap() => {
    'opcode': opcode,
    'shamt': shamt,
    'rs1': rs1,
    'funct2': funct2!,
    'shamt5': shamt5,
    'funct3': funct3!,
  };

  static const BitStruct STRUCT = const BitStruct({
    'opcode': CompressedInstruction.opcodeRange,
    'shamt': const BitRange(2, 7),
    'rs1': const BitRange(7, 10),
    'funct2': const BitRange(10, 11),
    'shamt5': const BitRange.single(12),
    'funct3': const BitRange(13, 15),
  });
}

/// Compressed RISC-V instruction
class CompressedInstruction {
  final InstructionType value;

  const CompressedInstruction.r(CompressedRType r) : value = r;
  const CompressedInstruction.i(CompressedIType i) : value = i;
  const CompressedInstruction.ss(CompressedSSType ss) : value = ss;
  const CompressedInstruction.wi(CompressedWIType wi) : value = wi;
  const CompressedInstruction.l(CompressedLType l) : value = l;
  const CompressedInstruction.s(CompressedSType s) : value = s;
  const CompressedInstruction.a(CompressedAType a) : value = a;
  const CompressedInstruction.b(CompressedBType b) : value = b;
  const CompressedInstruction.j(CompressedJType j) : value = j;
  const CompressedInstruction.lwsp(CompressedLwspType lwsp) : value = lwsp;
  const CompressedInstruction.swsp(CompressedSwspType swsp) : value = swsp;
  const CompressedInstruction.cb(CompressedCbType cb) : value = cb;

  int get opcode => value.opcode;
  Map<String, int> toMap() => value.toMap();

  BitStruct get struct {
    if (value is CompressedRType) return CompressedRType.STRUCT;
    if (value is CompressedIType) return CompressedIType.STRUCT;
    if (value is CompressedSSType) return CompressedSSType.STRUCT;
    if (value is CompressedWIType) return CompressedWIType.STRUCT;
    if (value is CompressedLType) return CompressedLType.STRUCT;
    if (value is CompressedSType) return CompressedSType.STRUCT;
    if (value is CompressedAType) return CompressedAType.STRUCT;
    if (value is CompressedBType) return CompressedBType.STRUCT;
    if (value is CompressedJType) return CompressedJType.STRUCT;
    if (value is CompressedLwspType) return CompressedLwspType.STRUCT;
    if (value is CompressedSwspType) return CompressedSwspType.STRUCT;
    if (value is CompressedCbType) return CompressedCbType.STRUCT;

    throw 'Unreachable';
  }

  @override
  String toString() => value.toString();

  static const opcodeRange = const BitRange(0, 1);
}
