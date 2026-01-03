import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:river_hdl/river_hdl.dart';
import 'package:test/test.dart';

Future<void> decoderTest<T extends InstructionType>(
  int instr,
  Map<String, int> fields,
  Mxlen mxlen,
  Microcode microcode, {
  bool isDynamic = false,
}) async {
  final clk = SimpleClockGenerator(20).clk;

  final reset = Logic();
  final enable = Logic();
  final input = Const(instr, width: 32);

  final microcodeRead = DataPortInterface(
    microcode.patternWidth,
    microcode.decodeLookup.length.bitLength,
  );

  RegisterFile(
    clk,
    reset,
    [],
    [microcodeRead],
    numEntries: microcode.map.length,
    resetValue: microcode.encodedPatterns,
  );

  final decoder = isDynamic
      ? DynamicInstructionDecoder(
          clk,
          reset,
          enable,
          input,
          microcodeRead,
          microcode: microcode,
          mxlen: mxlen,
        )
      : StaticInstructionDecoder(
          clk,
          reset,
          enable,
          input,
          microcode: microcode,
          mxlen: mxlen,
        );

  await decoder.build();

  WaveDumper(decoder);

  reset.inject(1);
  enable.inject(0);

  Simulator.registerAction(20, () {
    reset.put(0);
    enable.put(1);
  });

  unawaited(Simulator.run());

  await clk.nextPosedge;

  while (reset.value.toBool()) {
    await clk.nextPosedge;
  }

  while (!decoder.done.value.toBool()) {
    await clk.nextPosedge;
  }

  await Simulator.endSimulation();
  await Simulator.simulationEnded;

  expect(decoder.valid.value.toBool(), isTrue);

  final typeName = T.toString();

  for (final entry in decoder.instrTypeMap.entries) {
    final value = entry.value.value.toBool();
    if (entry.key == typeName) {
      expect(value, isTrue);
    } else {
      expect(value, isFalse);
    }
  }

  for (final entry in fields.entries) {
    final value = decoder.fields[entry.key]!.value.toInt();
    expect(value, equals(entry.value), reason: '${entry.key}=$value');
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  void define(bool isDynamic) {
    group('RV32I', () {
      final microcode = Microcode(Microcode.buildDecodeMap([rv32i]));

      test('R-type: add x3, x1, x2', () async {
        await decoderTest<RType>(
          0x002081B3,
          {
            'opcode': 0x33,
            'rd': 3,
            'rs1': 1,
            'rs2': 2,
            'funct3': 0,
            'funct7': 0,
          },
          Mxlen.mxlen_32,
          microcode,
          isDynamic: isDynamic,
        );
      });

      test('I-type: addi x5, x1, 10', () async {
        await decoderTest<IType>(
          0x00A08293,
          {'opcode': 0x13, 'rd': 5, 'rs1': 1, 'imm': 10, 'funct3': 0},
          Mxlen.mxlen_32,
          microcode,
          isDynamic: isDynamic,
        );
      });

      test('S-type: sw x2, 12(x1)', () async {
        await decoderTest<SType>(
          0x0020A623,
          {'opcode': 0x23, 'rs1': 1, 'rs2': 2, 'funct3': 0x2, 'imm[4:0]': 12},
          Mxlen.mxlen_32,
          microcode,
          isDynamic: isDynamic,
        );
      });
    });
  }

  group('Static decoding', () => define(false));
  group('Dynamic decoding', () => define(true));
}
