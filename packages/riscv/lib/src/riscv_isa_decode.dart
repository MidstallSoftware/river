import 'riscv_isa_base.dart';

class DecodeException implements Exception {
  final int opcode;
  final int? funct;

  const DecodeException(this.opcode, this.funct);

  @override
  String toString() => "Decode exception: $opcode, function: $funct";
}

extension RTypeDecode on RType {
  static RType decode(int instr) => RType.map(RType.STRUCT.decode(instr));
}

extension ITypeDecode on IType {
  static IType decode(int instr) => IType.map(IType.STRUCT.decode(instr));
}

extension STypeDecode on SType {
  static SType decode(int instr) => SType.map(SType.STRUCT.decode(instr));
}

extension BTypeDecode on BType {
  static BType decode(int instr) => BType.map(BType.STRUCT.decode(instr));
}

extension UTypeDecode on UType {
  static UType decode(int instr) => UType.map(UType.STRUCT.decode(instr));
}

extension JTypeDecode on JType {
  static JType decode(int instr) => JType.map(JType.STRUCT.decode(instr));
}

extension InstructionDecode on Instruction {
  static Instruction decode(int instr) {
    int opcode = instr & 0x7F;

    switch (opcode) {
      case 0x33:
        return Instruction.r(RTypeDecode.decode(instr));

      case 0x13:
      case 0x03:
      case 0x67:
      case 0x73:
        return Instruction.i(ITypeDecode.decode(instr));

      case 0x23:
        return Instruction.s(STypeDecode.decode(instr));
      case 0x63:
        return Instruction.b(BTypeDecode.decode(instr));

      case 0x37:
      case 0x17:
        return Instruction.u(UTypeDecode.decode(instr));

      case 0x6F:
        return Instruction.j(JTypeDecode.decode(instr));

      default:
        throw DecodeException(opcode, null);
    }
  }
}
