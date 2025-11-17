import 'package:riscv/riscv.dart';
import 'interconnect/base.dart';
import 'bus.dart';
import 'cache.dart';
import 'clock.dart';
import 'dev.dart';
import 'mem.dart';

/// Defines the configuration mode of the microcode
enum MicrocodeMode {
  /// No microcode engine
  none,

  /// Partial microcode engine
  partial,

  /// Full microcode engine
  full,
}

/// Method of performing the execution stage of the pipeline
enum ExecutionMode {
  /// Execute all instructions in order
  in_order,

  /// Executes instructions out of order based on utilization of the individual execution units
  out_of_order,
}

class InterruptLine {
  final int irq;
  final String source;
  final String target;

  const InterruptLine({
    required this.irq,
    required this.source,
    required this.target,
  });

  @override
  String toString() =>
      'InterruptLine(irq: $irq, source: $source, target: $target)';
}

class InterruptController {
  final String name;
  final int baseAddr;
  final List<InterruptLine> lines;

  const InterruptController({
    required this.name,
    required this.baseAddr,
    required this.lines,
  });

  @override
  String toString() =>
      'InterruptController(name: $name, baseAddr: $baseAddr, lines: $lines)';
}

/// A River RISC-V core
class RiverCore {
  final int vendorId;
  final int archId;
  final int hartId;
  final int resetVector;
  final Mxlen mxlen;
  final ClockConfig clock;
  final List<RiscVExtension> extensions;
  final List<InterruptController> interrupts;
  final Mmu mmu;
  final MicrocodeMode microcodeMode;
  final ExecutionMode executionMode;
  final L1Cache? l1cache;

  const RiverCore({
    this.vendorId = 0,
    this.archId = 0,
    this.hartId = 0,
    this.resetVector = 0,
    required this.clock,
    required this.mxlen,
    required this.extensions,
    required this.interrupts,
    required this.mmu,
    this.microcodeMode = MicrocodeMode.none,
    this.executionMode = ExecutionMode.in_order,
    this.l1cache,
  });

  const RiverCore._32({
    this.vendorId = 0,
    this.archId = 0,
    this.hartId = 0,
    this.resetVector = 0,
    required this.clock,
    required this.extensions,
    required this.interrupts,
    required this.mmu,
    this.microcodeMode = MicrocodeMode.none,
    this.executionMode = ExecutionMode.in_order,
    this.l1cache,
  }) : mxlen = Mxlen.mxlen_32;

  const RiverCore._64({
    this.vendorId = 0,
    this.archId = 0,
    this.hartId = 0,
    this.resetVector = 0,
    required this.clock,
    required this.extensions,
    required this.interrupts,
    required this.mmu,
    this.microcodeMode = MicrocodeMode.none,
    this.executionMode = ExecutionMode.in_order,
    this.l1cache,
  }) : mxlen = Mxlen.mxlen_64;

  String? get implementsName {
    String value = "";
    for (final ext in extensions) {
      if (ext.name != null && value.length == 0) {
        value += ext.name!;
      } else if (ext.key != null) {
        value += ext.key!;
      } else {
        return null;
      }
    }

    return value;
  }

  @override
  String toString() =>
      'RiverCore(vendorId: $vendorId, archId: $archId, hartId: $hartId,'
      ' resetVector: $resetVector, clock: $clock, ${implementsName != null ? 'implements: $implementsName' : 'extensions: $extensions'}, interrupts: $interrupts,'
      ' mmu: $mmu, microcodeMode: $microcodeMode, executionMode: $executionMode, l1Cache: $l1cache)';
}

/// A River SoC
abstract class RiverSoC {
  /// Devices on the SoC
  List<Device> get devices;

  /// Bus client ports on the interconnect
  List<BusClientPort> get clients;

  /// All of the cores in the SoC
  List<RiverCore> get cores;

  /// The interconnect fabric on the SoC
  Interconnect get fabric;

  /// The clocks for the SoC
  List<ClockDomain> get clocks;

  const RiverSoC();

  RiverCore? getCore(int hartId) {
    for (final core in cores) {
      if (core.hartId == hartId) {
        return core;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'RiverSoC(devices: $devices, clients: $clients, cores: $cores, fabric: $fabric, clocks: $clocks)';
}
