import 'isa.dart';

extension CompressedRTypeEncode on CompressedRType {
  int encode() => CompressedRType.STRUCT.encode(toMap());
}

extension CompressedITypeEncode on CompressedIType {
  int encode() => CompressedIType.STRUCT.encode(toMap());
}

extension CompressedSSTypeEncode on CompressedSSType {
  int encode() => CompressedSSType.STRUCT.encode(toMap());
}

extension CompressedWITypeEncode on CompressedWIType {
  int encode() => CompressedWIType.STRUCT.encode(toMap());
}

extension CompressedLTypeEncode on CompressedLType {
  int encode() => CompressedLType.STRUCT.encode(toMap());
}

extension CompressedSTypeEncode on CompressedSType {
  int encode() => CompressedSType.STRUCT.encode(toMap());
}

extension CompressedATypeEncode on CompressedAType {
  int encode() => CompressedAType.STRUCT.encode(toMap());
}

extension CompressedBTypeEncode on CompressedBType {
  int encode() => CompressedBType.STRUCT.encode(toMap());
}

extension CompressedJTypeEncode on CompressedJType {
  int encode() => CompressedJType.STRUCT.encode(toMap());
}

extension CompressedInstructionEncode on CompressedInstruction {
  int encode() => struct.encode(toMap());
}
