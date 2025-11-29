import '../../helpers.dart';
import '../../riscv_isa_decode.dart';
import 'isa.dart';

extension CompressedRTypeDecode on CompressedRType {
  static CompressedRType decode(int instr) =>
      CompressedRType.map(CompressedRType.STRUCT.decode(instr));
}

extension CompressedITypeDecode on CompressedIType {
  static CompressedIType decode(int instr) =>
      CompressedIType.map(CompressedIType.STRUCT.decode(instr));
}

extension CompressedSSTypeDecode on CompressedSSType {
  static CompressedSSType decode(int instr) =>
      CompressedSSType.map(CompressedSSType.STRUCT.decode(instr));
}

extension CompressedWITypeDecode on CompressedWIType {
  static CompressedWIType decode(int instr) =>
      CompressedWIType.map(CompressedWIType.STRUCT.decode(instr));
}

extension CompressedLTypeDecode on CompressedLType {
  static CompressedLType decode(int instr) =>
      CompressedLType.map(CompressedLType.STRUCT.decode(instr));
}

extension CompressedSTypeDecode on CompressedSType {
  static CompressedSType decode(int instr) =>
      CompressedSType.map(CompressedSType.STRUCT.decode(instr));
}

extension CompressedATypeDecode on CompressedAType {
  static CompressedAType decode(int instr) =>
      CompressedAType.map(CompressedAType.STRUCT.decode(instr));
}

extension CompressedBTypeDecode on CompressedBType {
  static CompressedBType decode(int instr) =>
      CompressedBType.map(CompressedBType.STRUCT.decode(instr));
}

extension CompressedJTypeDecode on CompressedJType {
  static CompressedJType decode(int instr) =>
      CompressedJType.map(CompressedJType.STRUCT.decode(instr));
}

extension CompressedLwspTypeDecode on CompressedLwspType {
  static CompressedLwspType decode(int instr) =>
      CompressedLwspType.map(CompressedLwspType.STRUCT.decode(instr));
}

extension CompressedSwspTypeDecode on CompressedSwspType {
  static CompressedSwspType decode(int instr) =>
      CompressedSwspType.map(CompressedSwspType.STRUCT.decode(instr));
}

extension CompressedCbTypeDecode on CompressedCbType {
  static CompressedCbType decode(int instr) =>
      CompressedCbType.map(CompressedCbType.STRUCT.decode(instr));
}

extension CompressedInstructionDecode on CompressedInstruction {
  static CompressedInstruction decode(int instr) {
    final quadrant = BitRange(0, 1).decode(instr);
    final funct3 = BitRange(13, 15).decode(instr);

    switch (quadrant) {
      case 0:
        return _decodeQuadrant0(instr, funct3);
      case 1:
        return _decodeQuadrant1(instr, funct3);
      case 2:
        return _decodeQuadrant2(instr, funct3);
      default:
        throw DecodeException(quadrant, funct3);
    }
  }

  static CompressedInstruction _decodeQuadrant0(int instr, int funct3) {
    switch (funct3) {
      case 0:
        return CompressedInstruction.wi(CompressedWITypeDecode.decode(instr));
      case 2:
        return CompressedInstruction.l(CompressedLTypeDecode.decode(instr));
      case 6:
        return CompressedInstruction.s(CompressedSTypeDecode.decode(instr));
      default:
        throw DecodeException(0, funct3);
    }
  }

  static CompressedInstruction _decodeQuadrant1(int instr, int funct3) {
    switch (funct3) {
      case 0:
      case 1:
      case 2:
      case 3:
        return CompressedInstruction.i(CompressedITypeDecode.decode(instr));
      case 4:
        final top2 = BitRange(10, 11).decode(instr);
        if (top2 == 3) {
          return CompressedInstruction.a(CompressedATypeDecode.decode(instr));
        }
        return CompressedInstruction.i(CompressedITypeDecode.decode(instr));
      case 5:
        return CompressedInstruction.j(CompressedJTypeDecode.decode(instr));
      case 6:
      case 7:
        return CompressedInstruction.a(CompressedATypeDecode.decode(instr));
      default:
        throw DecodeException(1, funct3);
    }
  }

  static CompressedInstruction _decodeQuadrant2(int instr, int funct3) {
    switch (funct3) {
      case 0:
        return CompressedInstruction.i(CompressedITypeDecode.decode(instr));
      case 2:
        return CompressedInstruction.lwsp(
          CompressedLwspTypeDecode.decode(instr),
        );
      case 4:
        return CompressedInstruction.i(CompressedITypeDecode.decode(instr));
      case 6:
        return CompressedInstruction.ss(CompressedSSTypeDecode.decode(instr));
      default:
        throw DecodeException(2, funct3);
    }
  }
}
