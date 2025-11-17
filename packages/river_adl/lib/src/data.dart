import 'package:riscv/riscv.dart' hide Instruction;
import 'instr.dart';
import 'module.dart';

enum DataType {
  i8(8, false),
  i16(16, false),
  i32(32, false),
  i64(64, false),
  u8(8),
  u16(16),
  u32(32),
  u64(64);

  const DataType(this.width, [this.unsigned = true]);

  final int width;
  final bool unsigned;

  int get bytes => width ~/ 4;
}

enum DataLocation { register, memory, immediate }

class DataField {
  final String? name;
  final DataType type;
  final DataLocation? source;
  final Module? module;
  Instruction? producer;
  Register? assignedRegister;
  int? ssaId;
  int? vreg;
  int? memAddress;

  DataField(
    this.type, {
    this.name,
    Module? module,
    this.source,
    this.producer,
    this.ssaId,
    this.vreg,
    this.memAddress,
  }) : module = module ?? Module.current;
  DataField.register(
    Register reg, {
    this.name,
    Module? module,
    this.ssaId,
    this.vreg,
  }) : type = DataType.i32,
       source = DataLocation.register,
       assignedRegister = reg,
       memAddress = null,
       module = module ?? Module.current;
  DataField.zero({this.name, Module? module, this.ssaId, this.vreg})
    : type = DataType.i32,
      source = DataLocation.register,
      assignedRegister = Register.x0,
      module = module ?? Module.current;

  DataField copyWith({
    String? name,
    DataType? type,
    DataLocation? source,
    Module? module,
    Instruction? producer,
    int? ssaId,
    int? vreg,
  }) => DataField(
    type ?? this.type,
    ssaId: ssaId ?? this.ssaId,
    name: name ?? this.name,
    source: source ?? this.source,
    module: module ?? this.module,
    producer: producer ?? this.producer,
    vreg: vreg ?? this.vreg,
  );

  String? _subname(String suffix) => name != null ? '${name}_${suffix}' : null;

  bool _canFold(DataField other) =>
      source == DataLocation.immediate &&
      other.source == DataLocation.immediate &&
      producer != null &&
      other.producer != null &&
      producer?.imm != null &&
      other.producer?.imm != null;

  void bind(DataField value) {
    producer = value.producer;
    value.producer = value.producer!.assignOutput(this);
  }

  void load(DataField other) {
    final i = RInstruction(
      RInstructionConfig.add(other),
      this,
      DataField.zero(module: module),
    );

    producer = i;
    module!.addInstruction(i);
  }

  DataField operator +(DataField other) {
    final outName = _subname('add_out');
    if (_canFold(other)) {
      final a = producer!.imm!;
      final b = other.producer!.imm!;
      return DataField.from(a + b, name: outName, module: module);
    } else {
      final out = module != null
          ? module!.field(type, name: outName)
          : DataField(type, name: outName);
      final add = RInstruction(RInstructionConfig.add(this), out, other);
      out.producer = add;
      (module ?? other.module)!.addInstruction(add);
      return out;
    }
  }

  DataField operator -(DataField other) {
    final outName = _subname('sub_out');
    if (_canFold(other)) {
      final a = producer!.imm!;
      final b = other.producer!.imm!;
      return DataField.from(a - b, name: outName, module: module);
    } else {
      final out = module != null
          ? module!.field(type, name: outName)
          : DataField(type, name: outName);
      final sub = RInstruction(RInstructionConfig.sub(this), out, other);
      out.producer = sub;
      (module ?? other.module)!.addInstruction(sub);
      return out;
    }
  }

  DataField operator |(DataField other) {
    final outName = _subname('sub_out');
    if (_canFold(other)) {
      final a = producer!.imm!;
      final b = other.producer!.imm!;
      return DataField.from(a | b, name: outName, module: module);
    } else {
      final out = module != null
          ? module!.field(type, name: outName)
          : DataField(type, name: outName);
      final sub = RInstruction(RInstructionConfig.or(this), out, other);
      out.producer = sub;
      (module ?? other.module)!.addInstruction(sub);
      return out;
    }
  }

  DataField operator &(DataField other) {
    final outName = _subname('sub_out');
    if (_canFold(other)) {
      final a = producer!.imm!;
      final b = other.producer!.imm!;
      return DataField.from(a & b, name: outName, module: module);
    } else {
      final out = module != null
          ? module!.field(type, name: outName)
          : DataField(type, name: outName);
      final sub = RInstruction(RInstructionConfig.and(this), out, other);
      out.producer = sub;
      (module ?? other.module)!.addInstruction(sub);
      return out;
    }
  }

  @override
  String toString() =>
      'DataField(name: $name, type: $type, source: $source, module: $module)';

  static DataField from(int value, {String? name, Module? module}) {
    final field = module != null
        ? module.field(DataType.i32, name: name)
        : DataField(DataType.i32, name: name);
    field.producer = IInstruction(
      IInstructionConfig.addi(value),
      field,
      DataField.zero(module: module),
    );
    return field;
  }
}
