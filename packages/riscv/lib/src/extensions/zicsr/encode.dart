import 'isa.dart';

extension SystemITypeEncode on SystemIType {
  int encode() => SystemIType.STRUCT.encode(toMap());
}

extension SystemRTypeEncode on SystemRType {
  int encode() => SystemRType.STRUCT.encode(toMap());
}
