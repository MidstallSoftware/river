import 'dart:io';
import 'package:riscv/riscv.dart';
import 'package:river_adl/river_adl.dart';

class MyModule extends Module {
  DataField get c => output('c');
  //DataField get d => output('d');

  MyModule(DataField a, DataField b) : super() {
    a = addInput('a', a);
    b = addInput('b', b);

    addOutput('c', type: a.type, source: DataLocation.register);
    //addOutput('d', type: a.type, source: DataLocation.memory);

    c.bind(a + b);
    //d.load(c);
  }
}

void main() async {
  // Does:
  //
  // final a = 1;
  // final b = 2;
  // final c = a + b;
  //
  // Asm:
  // addi x4, x0, 1
  // addi x5, x0, 2
  // add x6, x4, x5
  final myModule = MyModule(
    DataField.from(1, name: 'a'),
    DataField.from(2, name: 'b'),
  );

  await myModule.build();

  final generatedAsm = myModule.generateAssembly();
  print(generatedAsm);

  final generatedBin = myModule.generateBinary();

  File('myProgram.bin').writeAsBytesSync(generatedBin);
}
