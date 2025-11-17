import 'package:riscv/riscv.dart';
import 'package:test/test.dart';

void main() {
  group('Decode RVC', () {
    test('WI-type: c.addi4spn x8, 16(sp)', () {
      const instr = 0x0020;
      final decoded = CompressedInstructionDecode.decode(instr);

      expect(decoded.value, isA<CompressedWIType>());
      final wi = decoded.value as CompressedWIType;

      expect(wi.rd, equals(0));
      expect(wi.imm, equals(1));
      expect(wi.funct3, equals(0));
    });

    test('L-type: c.lw x9, 8(x2)', () {
      const instr = 0x4224;
      final decoded = CompressedInstructionDecode.decode(instr);

      expect(decoded.value, isA<CompressedLType>());
      final cl = decoded.value as CompressedLType;

      expect(cl.funct3, equals(2));
      expect(cl.rs1, equals(4));
      expect(cl.rd, equals(1));
    });

    test('S-type: c.sw x9, 8(x2)', () {
      const instr = 0xC204;
      final decoded = CompressedInstructionDecode.decode(instr);

      expect(decoded.value, isA<CompressedSType>());
      final cs = decoded.value as CompressedSType;

      expect(cs.funct3, equals(6));
      expect(cs.rs1, equals(4));
      expect(cs.rs2, equals(1));
    });

    test('I-type: c.addi x1, 1', () {
      const instr = 0x0085;
      final decoded = CompressedInstructionDecode.decode(instr);

      expect(decoded.value, isA<CompressedIType>());
      final ci = decoded.value as CompressedIType;

      expect(ci.funct3, equals(0));
      expect(ci.rs1, equals(1));
      expect(ci.imm4_0, equals(1));
    });

    test('J-type: c.j 0x4', () {
      const instr = 0xA011;
      final decoded = CompressedInstructionDecode.decode(instr);

      expect(decoded.value, isA<CompressedJType>());
      final cj = decoded.value as CompressedJType;

      expect(cj.funct3, equals(5));
      expect(cj.value, isNonZero);
    });

    test('A-type: c.and x8, x9', () {
      const instr = 0x8CE1;
      final decoded = CompressedInstructionDecode.decode(instr);

      expect(decoded.value, isA<CompressedAType>());
      final ca = decoded.value as CompressedAType;

      expect(ca.rs1, equals(1));
      expect(ca.rs2, equals(0));
    });

    test('SS-type: c.swsp x5, 12(sp)', () {
      const instr = 0xC616;
      final decoded = CompressedInstructionDecode.decode(instr);

      expect(decoded.value, isA<CompressedSSType>());
      final css = decoded.value as CompressedSSType;

      expect(css.rs2, equals(5));
      expect(css.imm, isPositive);
    });
  });
}
