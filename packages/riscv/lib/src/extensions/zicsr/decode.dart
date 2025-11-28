import '../../helpers.dart';
import '../../riscv_isa_decode.dart';
import 'isa.dart';

extension SystemITypeDecode on SystemIType {
  static SystemIType decode(int instr) =>
      SystemIType.map(SystemIType.STRUCT.decode(instr));
}

extension SystemRTypeDecode on SystemRType {
  static SystemRType decode(int instr) =>
      SystemRType.map(SystemRType.STRUCT.decode(instr));
}
