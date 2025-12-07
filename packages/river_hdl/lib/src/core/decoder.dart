import 'package:rohd/rohd.dart';
import 'package:riscv/riscv.dart';

class InstructionDecoder extends Module {
  final Mxlen mxlen;
  final Microcode microcode;

  Logic get valid => output('valid');
  Logic get index => output('index');

  Map<String, Logic> get fields => Map.fromEntries(
    fieldWidths.entries.map(
      (entry) => MapEntry(entry.key, output(computeName(entry.key))),
    ),
  );

  Map<String, Logic> get instrTypeMap =>
      Map.fromEntries(instrTypes.map((t) => MapEntry(t, output('is_$t'))));

  InstructionDecoder(
    Logic input, {
    required this.microcode,
    required this.mxlen,
    super.name = 'river_instruction_decoder',
  }) {
    input = addInput('instr', input, width: 32);

    addOutput('valid');
    addOutput('index', width: microcode.map.length.bitLength);
    addOutput('imm', width: mxlen.size);

    for (final entry in fieldWidths.entries) {
      if (entry.key == 'imm') continue;

      addOutput(computeName(entry.key), width: entry.value);
    }

    for (final t in instrTypes) {
      addOutput('is_$t');
    }

    final decodeMap = lookupDecode(input);

    Combinational([
      If.block([
        ...decodeMap.entries
            .map(
              (entry) => Iff(entry.value, [
                valid < 1,
                index <
                    Const(
                      microcode.indices[entry.key]! + 1,
                      width: microcode.map.length.bitLength,
                    ),
                ...fields.entries.map((entry) => entry.value < 0).toList(),
                ...instrTypeMap.entries
                    .map((entry) => entry.value < 0)
                    .toList(),
                instrTypeMap[instrType(microcode.map[entry.key]!)]! < 1,
                ...microcode.map[entry.key]!.struct.mapping.entries
                    .where((entry) => entry.key != 'imm')
                    .map((entry) {
                      final fieldName = entry.key;
                      final fieldOutput = fields[fieldName]!;
                      final range = entry.value;
                      final value = input
                          .slice(range.end, range.start)
                          .zeroExtend(fieldOutput.width)
                          .named(fieldName);
                      return fieldOutput < value;
                    })
                    .toList(),
                fields['imm']! <
                    switch (instrType(microcode.map[entry.key]!)) {
                      'IType' => input.slice(31, 20).signExtend(mxlen.size),
                      'SType' => [
                        input.slice(31, 25),
                        input.slice(11, 7),
                      ].swizzle().zeroExtend(mxlen.size).signExtend(mxlen.size),
                      'BType' => [
                        input.slice(31, 31),
                        input.slice(7, 7),
                        input.slice(30, 25),
                        input.slice(11, 8),
                        Const(0, width: 1),
                      ].swizzle().signExtend(mxlen.size),
                      'UType' => [
                        input.slice(31, 12),
                        Const(0, width: 12),
                      ].swizzle().signExtend(mxlen.size),
                      'JType' => [
                        input.slice(31, 31),
                        input.slice(19, 12),
                        input.slice(20, 20),
                        input.slice(30, 21),
                        Const(0, width: 1),
                      ].swizzle().signExtend(mxlen.size),
                      _ => Const(0, width: mxlen.size),
                    },
              ]),
            )
            .toList(),
        Else([
          valid < 0,
          index < 0,
          ...instrTypeMap.entries.map((entry) => entry.value < 0).toList(),
          ...fields.entries.map((entry) => entry.value < 0).toList(),
        ]),
      ]),
    ]);
  }

  List<String> get instrTypes {
    List<String> result = [];
    for (final i in microcode.map.values) {
      final t = instrType(i);
      if (result.contains(t)) continue;
      result.add(t);
    }
    return result;
  }

  Map<String, int> get fieldWidths {
    final widths = <String, int>{};
    for (final entry in microcode.fields.entries) {
      final fieldName = entry.key;
      final patternMap = entry.value;

      int maxWidth = 0;
      for (final range in patternMap.values) {
        if (range.width > maxWidth) maxWidth = range.width;
      }

      widths[fieldName] = maxWidth;
    }
    return widths;
  }

  Map<OperationDecodePattern, Logic> lookupDecode(Logic input) =>
      Map.fromEntries(
        microcode.map.entries.map((entry) {
          var temp = Logic(
            name: 'temp_${entry.value.mnemonic}',
            width: mxlen.size,
          );

          final nonZeroFields = Const(
            entry.key.nonZeroFields.keys
                .map(
                  (fieldName) =>
                      entry.value.struct.mapping[fieldName]!.encode(1),
                )
                .fold(0, (a, b) => a | b),
            width: mxlen.size,
          ).named('nzf_${entry.value.mnemonic}');

          temp <= input | nonZeroFields;

          final mask = Const(
            entry.key.mask,
            width: mxlen.size,
          ).named('mask_${entry.value.mnemonic}');
          final value = Const(
            entry.key.value,
            width: mxlen.size,
          ).named('value_${entry.value.mnemonic}');

          return MapEntry(entry.key, (temp & mask).eq(value));
        }),
      );

  static String computeName(String input) {
    return input.replaceAll('[', '_').replaceAll(']', '').replaceAll(':', '_');
  }

  static String instrType<T extends InstructionType>(Operation<T> i) {
    final name = i.runtimeType.toString();
    return name.substring(10, name.length - 1);
  }
}
