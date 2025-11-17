import 'package:riscv/riscv.dart';
import 'package:test/test.dart';

void main() {
  group('Decode RV64I', () {
    test('I-type: addiw x10, x11, 1', () {
      const instr = 0x0015851B;
      final i = ITypeDecode.decode(instr);
      expect(i.opcode, equals(0x1B));
      expect(i.rd, equals(10));
      expect(i.rs1, equals(11));
      expect(i.funct3, equals(0));
      expect(i.imm, equals(1));
    });

    test('I-type: slli x5, x6, 3', () {
      const instr = 0x00331293;
      final i = ITypeDecode.decode(instr);
      expect(i.opcode, equals(0x13));
      expect(i.rd, equals(5));
      expect(i.rs1, equals(6));
      expect(i.funct3, equals(1));
      expect(i.imm, equals(3));
    });

    test('I-type: ld x8, 16(x9)', () {
      const instr = 0x0104B403;
      final i = ITypeDecode.decode(instr);
      expect(i.opcode, equals(0x03));
      expect(i.rd, equals(8));
      expect(i.rs1, equals(9));
      expect(i.funct3, equals(3));
      expect(i.imm, equals(16));
    });

    test('S-type: sd x5, 8(x6)', () {
      const instr = 0x00533423;
      final s = STypeDecode.decode(instr);
      expect(s.opcode, equals(0x23));
      expect(s.rs1, equals(6));
      expect(s.rs2, equals(5));
      expect(s.funct3, equals(3));
      expect(s.imm, equals(8));
    });

    test('U-type: lui x10, 0x12345000', () {
      const instr = 0x12345537;
      final u = UTypeDecode.decode(instr);
      expect(u.opcode, equals(0x37));
      expect(u.rd, equals(10));
      expect(u.imm, equals(0x12345000));
    });

    test('J-type: jal x1, 0x00000010', () {
      const instr = 0x010000EF;
      final j = JTypeDecode.decode(instr);
      expect(j.opcode, equals(0x6F));
      expect(j.rd, equals(1));
      expect(j.imm, equals(16));
    });

    test('B-type: beq x1, x2, 8', () {
      const instr = 0x00208463;
      final b = BTypeDecode.decode(instr);
      expect(b.opcode, equals(0x63));
      expect(b.rs1, equals(1));
      expect(b.rs2, equals(2));
      expect(b.funct3, equals(0));
      expect(b.imm, equals(8));
    });
  });
}
