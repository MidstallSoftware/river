import 'package:riscv/riscv.dart' hide Instruction;
import '../data.dart';

List<int> encodeAsBytes(int word) => [
  word & 0xFF,
  (word >> 8) & 0xFF,
  (word >> 16) & 0xFF,
  (word >> 24) & 0xFF,
];

abstract class Instruction {
  const Instruction();

  int? get imm => null;

  DataField? get output;
  List<DataField> get inputs;

  bool get hasSideEffects => false;

  Instruction assignOutput(DataField output);
  Instruction assignInputs(List<DataField> inputs);

  String toAsm();
  InstructionType type();

  List<int> toBinary() {
    final t = type();
    if (t is RType) return encodeAsBytes(t.encode());
    if (t is IType) return encodeAsBytes(t.encode());
    if (t is UType) return encodeAsBytes(t.encode());

    throw 'Unknown instruction type for $t';
  }
}
