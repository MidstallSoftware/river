import 'package:riscv/riscv.dart' show Register;
import 'data.dart';
import 'instr.dart';

class _LiveInterval {
  int vreg;
  int start;
  int end;

  _LiveInterval(this.vreg, this.start, this.end);
}

class _RegisterAllocator {
  int nextRegIndex = 4; // start at x4
  final Map<int, int> _vregToIndex = {};
  final List<int> _free = [];
  final Set<int> _reserved = {0};

  _RegisterAllocator();

  void run(
    List<Instruction> instructions,
    Map<int, _LiveInterval> intervals,
    Iterable<DataField> outputFields,
  ) {
    for (final inst in instructions) {
      for (final input in inst.inputs) {
        _recordPinned(input);
      }
      if (inst.output != null) {
        _recordPinned(inst.output!);
      }
    }

    int _allocIndexSkippingReserved() {
      while (_reserved.contains(nextRegIndex)) {
        nextRegIndex++;
      }
      return nextRegIndex++;
    }

    int _allocIndex() {
      if (_free.isNotEmpty) {
        return _free.removeLast();
      }
      return _allocIndexSkippingReserved();
    }

    for (final out in outputFields) {
      final v = out.vreg;
      if (v == null) continue;

      final assigned = out.assignedRegister;
      if (assigned != null) {
        final idx = assigned.value;
        _reserved.add(idx);
        _vregToIndex[v] = idx;
        continue;
      }

      final idx = _allocIndexSkippingReserved();
      _vregToIndex[v] = idx;
      _reserved.add(idx);
    }

    while (_reserved.contains(nextRegIndex)) {
      nextRegIndex++;
    }

    final intervalList = intervals.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final active = <_LiveInterval>[];

    void _expireOld(int position) {
      active.removeWhere((iv) {
        if (iv.end < position) {
          final idx = _vregToIndex[iv.vreg];
          if (idx != null && !_reserved.contains(idx)) {
            _free.add(idx);
          }
          return true;
        }
        return false;
      });
    }

    for (final iv in intervalList) {
      _expireOld(iv.start);

      if (_vregToIndex.containsKey(iv.vreg)) {
        active.add(iv);
        continue;
      }

      final idx = _allocIndex();
      _vregToIndex[iv.vreg] = idx;
      active.add(iv);
    }

    for (final inst in instructions) {
      for (final input in inst.inputs) {
        _assignField(input);
      }
      if (inst.output != null) {
        _assignField(inst.output!);
      }
    }
  }

  void _recordPinned(DataField f) {
    if (f.vreg == null || f.assignedRegister == null) return;

    final idx = f.assignedRegister!.value;
    _reserved.add(idx);
    _vregToIndex[f.vreg!] = idx;
  }

  void _assignField(DataField f) {
    if (f.assignedRegister != null) return;

    final vreg = f.vreg;
    if (vreg == null) return;

    final idx = _vregToIndex[vreg];
    if (idx == null || idx >= Register.values.length) return;

    f.assignedRegister = Register.values[idx];
  }
}

abstract class Module {
  static Module? current;

  final Map<String, DataField> inputs = {};
  final Map<String, DataField> outputs = {};
  final List<Instruction> instructions = [];
  List<Instruction> _built = [];
  int _nextSSA = 0;
  int _memOffset = 0;

  Module() {
    current = this;
  }

  DataField field(DataType type, {String? name}) =>
      DataField(type, ssaId: _nextSSA++, name: name, module: this);

  DataField input(String name) => inputs[name]!;
  DataField output(String name) => outputs[name]!;

  DataField addInput(String name, DataField field) {
    final input = field.copyWith(ssaId: _nextSSA++, name: name, module: this);

    if (input.producer != null) {
      final inst = input.producer!.assignOutput(input);
      instructions.add(inst);
      input.producer = inst;
    }

    inputs[name] = input;
    return input;
  }

  DataField addOutput(
    String name, {
    required DataType type,
    DataLocation? source,
  }) {
    final out = DataField(
      type,
      ssaId: _nextSSA++,
      name: name,
      source: source,
      module: this,
    );

    if (source == DataLocation.memory) {
      out.memAddress = _memOffset;
      _memOffset += type.bytes;
    }

    outputs[name] = out;
    return out;
  }

  DataField register(Register reg) {
    if (outputs.containsKey(reg.abi)) {
      return outputs[reg.abi]!;
    }

    outputs[reg.abi] = DataField.register(
      reg,
      ssaId: _nextSSA++,
      name: reg.abi,
      module: this,
    );
    return outputs[reg.abi]!;
  }

  void addInstruction(Instruction i) => instructions.add(i);

  String generateAssembly() {
    final asm = StringBuffer();

    for (final inst in _built) {
      asm.writeln(inst.toAsm());
    }

    return asm.toString();
  }

  List<int> generateBinary() {
    final bytes = <int>[];

    for (final inst in _built) {
      bytes.addAll(inst.toBinary());
    }

    return bytes;
  }

  void _clearState(List<Instruction> instrs) {
    _nextSSA = 0;

    for (final instr in instrs) {
      if (instr.output != null) {
        final output = instr.output!;
        if (output.module == this) {
          output.ssaId = null;
          output.vreg = null;

          if (output.assignedRegister != null) {
            final reg = output.assignedRegister!;
            if (reg.value >= 4) output.assignedRegister = null;
          }
        }
      }

      for (final input in instr.inputs) {
        if (input.module == this) {
          input.ssaId = null;
          input.vreg = null;

          if (input.assignedRegister != null) {
            final reg = input.assignedRegister!;
            if (reg.value >= 4) input.assignedRegister = null;
          }
        }
      }
    }
  }

  void _computeState(List<Instruction> instrs) {
    int nextVreg = 0;
    for (final instr in instrs) {
      for (final input in instr.inputs) {
        if (input.module == this) {
          if (input.ssaId == null) {
            input.ssaId = _nextSSA++;
          }

          if (input.vreg == null) {
            input.vreg = nextVreg++;
          }
        }
      }

      if (instr.output != null) {
        if (instr.output!.module == this) {
          if (instr.output!.ssaId == null) {
            instr.output!.ssaId = _nextSSA++;
          }

          if (instr.output!.vreg == null) {
            instr.output!.vreg = nextVreg++;
          }
        }
      }
    }
  }

  List<Instruction> _topoSort(List<Instruction> instrs) {
    final visited = <Instruction>{};
    final sorted = <Instruction>[];

    void visit(Instruction inst) {
      if (visited.contains(inst)) return;
      visited.add(inst);

      for (final input in inst.inputs) {
        final prod = input.producer;
        if (prod != null) {
          visit(prod);
        }
      }

      sorted.add(inst);
    }

    for (final inst in instrs) visit(inst);

    return sorted;
  }

  List<Instruction> _removeDeadCode(List<Instruction> instrs) {
    final liveInstructions = <Instruction>{};
    final worklist = <DataField>[];

    for (final out in outputs.values) {
      if (out.producer != null) {
        worklist.add(out);
      }
    }

    while (worklist.isNotEmpty) {
      final field = worklist.removeLast();
      final instr = field.producer;
      if (instr == null) continue;
      if (liveInstructions.add(instr)) {
        for (final input in instr.inputs) {
          if (input.producer != null) {
            worklist.add(input);
          }
        }
      }
    }

    return instrs
        .where((i) => liveInstructions.contains(i) || i.hasSideEffects)
        .toList();
  }

  Map<int, _LiveInterval> _computeLiveIntervals(List<Instruction> instrs) {
    final intervals = <int, _LiveInterval>{};

    for (int i = 0; i < instrs.length; i++) {
      final inst = instrs[i];

      for (final input in inst.inputs) {
        if (input.vreg == null) continue;
        final v = input.vreg!;
        intervals.putIfAbsent(v, () => _LiveInterval(v, i, i)).end = i;
      }

      if (inst.output != null && inst.output!.vreg != null) {
        final v = inst.output!.vreg!;
        intervals.putIfAbsent(v, () => _LiveInterval(v, i, i)).start = i;
      }
    }

    final lastIdx = instrs.isEmpty ? 0 : instrs.length - 1;
    for (final out in outputs.values) {
      if (out.vreg == null) continue;
      final v = out.vreg!;
      final iv = intervals.putIfAbsent(
        v,
        () => _LiveInterval(v, lastIdx, lastIdx),
      );
      if (iv.end < lastIdx) {
        iv.end = lastIdx;
      }
    }

    return intervals;
  }

  Future<void> build() async {
    _built = _topoSort(instructions);
    _built = _removeDeadCode(_built);
    _clearState(_built);
    _computeState(_built);

    final intervals = _computeLiveIntervals(_built);

    var regAlloc = _RegisterAllocator();
    regAlloc.run(_built, intervals, outputs.values);
  }
}
