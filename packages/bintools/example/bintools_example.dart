import 'dart:io';
import 'package:bintools/bintools.dart';

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final elf = Elf.load(bytes);

  print(elf.header);

  for (final sh in elf.sectionHeaders) {
    if (sh.nameIndex == 0) continue;

    final bytes = elf.sectionData(sh);
    print('$sh: $bytes');
  }

  for (final ph in elf.programHeaders) {
    print(ph);
  }
}
