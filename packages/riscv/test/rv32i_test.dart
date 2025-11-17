import 'package:riscv/riscv.dart';
import 'package:test/test.dart';

void main() {
  group('Decode RV32I', () {
    test('R-type: add x3, x1, x2', () {
      const instr = 0x002081B3;
      final decoded = InstructionDecode.decode(instr);

      expect(decoded.value, isA<RType>());
      final r = decoded.value as RType;

      expect(r.opcode, equals(0x33));
      expect(r.rd, equals(3));
      expect(r.rs1, equals(1));
      expect(r.rs2, equals(2));
      expect(r.funct3, equals(0x0));
      expect(r.funct7, equals(0x00));
    });

    test('I-type: addi x5, x1, 10', () {
      const instr = 0x00A08293;
      final decoded = InstructionDecode.decode(instr);

      expect(decoded.value, isA<IType>());
      final i = decoded.value as IType;

      expect(i.opcode, equals(0x13));
      expect(i.rd, equals(5));
      expect(i.rs1, equals(1));
      expect(i.funct3, equals(0x0));
      expect(i.imm, equals(10));
    });

    test('S-type: sw x2, 12(x1)', () {
      const instr = 0x0020A623;
      final decoded = InstructionDecode.decode(instr);

      expect(decoded.value, isA<SType>());
      final s = decoded.value as SType;

      expect(s.opcode, equals(0x23));
      expect(s.rs1, equals(1));
      expect(s.rs2, equals(2));
      expect(s.funct3, equals(0x2));
      expect(s.imm, equals(12));
    });

    test('B-type: beq x1, x2, offset=8', () {
      const instr = 0x00208663;
      final decoded = InstructionDecode.decode(instr);

      expect(decoded.value, isA<BType>());
      final b = decoded.value as BType;

      expect(b.opcode, equals(0x63));
      expect(b.rs1, equals(1));
      expect(b.rs2, equals(2));
      expect(b.funct3, equals(0x0));
    });

    test('U-type: lui x5, 0x12345000', () {
      const instr = 0x123452B7;
      final decoded = InstructionDecode.decode(instr);

      expect(decoded.value, isA<UType>());
      final u = decoded.value as UType;

      expect(u.opcode, equals(0x37));
      expect(u.rd, equals(5));
      expect(u.imm, equals(0x12345000));
    });

    test('J-type: jal x1, 0x100', () {
      const instr = 0x000100EF;
      final decoded = InstructionDecode.decode(instr);

      expect(decoded.value, isA<JType>());
      final j = decoded.value as JType;

      expect(j.opcode, equals(0x6F));
      expect(j.rd, equals(1));
    });
  });
}
