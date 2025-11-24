import 'package:riscv/riscv.dart';
import 'package:river_adl/river_adl.dart';
import 'package:test/test.dart';

class MyModule extends Module {
  DataField get c => output('c');

  MyModule(DataField a, DataField b) : super() {
    a = addInput('a', a);
    b = addInput('b', b);

    addOutput('c', type: a.type, source: DataLocation.register);

    c.bind(a + b);
  }
}

void main() {
  group('MyModule', () {
    final myModule = MyModule(
      DataField.from(1, name: 'a'),
      DataField.from(2, name: 'b'),
    );

    setUp(myModule.build);

    test('Generated Assembly', () {
      expect("""addi x4, x0, 1
addi x5, x0, 2
add x6, x5, x4
""", myModule.generateAssembly());
    });
  });
}
