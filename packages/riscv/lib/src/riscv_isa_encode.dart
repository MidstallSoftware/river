import 'riscv_isa_base.dart';

extension RTypeEncode on RType {
  int encode() => RType.STRUCT.encode(toMap());
}

extension ITypeEncode on IType {
  int encode() => IType.STRUCT.encode(toMap());
}

extension STypeEncode on SType {
  int encode() => SType.STRUCT.encode(toMap());
}

extension BTypeEncode on BType {
  int encode() => BType.STRUCT.encode(toMap());
}

extension UTypeEncode on UType {
  int encode() => UType.STRUCT.encode(toMap());
}

extension InstructionEncode on Instruction {
  int encode() => struct.encode(toMap());
}
