import 'package:riscv/riscv.dart';
import 'interconnect/base.dart';
import 'bus.dart';
import 'cache.dart';
import 'clock.dart';
import 'dev.dart';
import 'mem.dart';

/// In-Core Scaler Version
enum IcsVersion { v1 }

/// Defines the type of workloads the core is designed for
enum RiverCoreType {
  /// Microcontroller
  mcu(hasCsrs: true),

  /// General purpose compute
  general(hasCsrs: true);

  const RiverCoreType({required this.hasCsrs});

  final bool hasCsrs;
}

/// Defines how a segment of the pipeline should be integrated with microcode
enum MicrocodePipelineMode {
  /// Contains both microcoded and hard-coded
  in_parallel,

  /// Contains purely microcoded
  standalone,

  /// Contains purely hard-coded
  none,
}

/// Defines the configuration mode of the microcode
enum MicrocodeMode {
  /// No microcode engine
  none(),

  /// Partial microcode engine
  parallelDecode(
    onDecoder: MicrocodePipelineMode.in_parallel,
    onExec: MicrocodePipelineMode.standalone,
  ),

  /// Partial microcode engine
  parallelExec(
    onDecoder: MicrocodePipelineMode.standalone,
    onExec: MicrocodePipelineMode.in_parallel,
  ),

  /// Partial microcode engine
  fullParallel(
    onDecoder: MicrocodePipelineMode.in_parallel,
    onExec: MicrocodePipelineMode.in_parallel,
  ),

  /// Full microcode engine
  full(
    onDecoder: MicrocodePipelineMode.standalone,
    onExec: MicrocodePipelineMode.standalone,
  );

  const MicrocodeMode({
    this.onDecoder = MicrocodePipelineMode.none,
    this.onExec = MicrocodePipelineMode.none,
  });

  final MicrocodePipelineMode onDecoder;
  final MicrocodePipelineMode onExec;
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
  final int impId;
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
  final bool hasSupervisor;
  final bool hasUser;
  final RiverCoreType type;
  final IcsVersion? icsVersion;
  final int threads;

  const RiverCore({
    this.vendorId = 0,
    this.archId = 0,
    this.impId = 0,
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
    this.hasSupervisor = true,
    this.hasUser = true,
    required this.type,
    this.icsVersion,
    this.threads = 1,
  });

  const RiverCore._32({
    this.vendorId = 0,
    this.archId = 0,
    this.impId = 0,
    this.hartId = 0,
    this.resetVector = 0,
    required this.clock,
    required this.extensions,
    required this.interrupts,
    required this.mmu,
    this.microcodeMode = MicrocodeMode.none,
    this.executionMode = ExecutionMode.in_order,
    this.l1cache,
    this.hasSupervisor = false,
    this.hasUser = false,
    required this.type,
    this.icsVersion,
    this.threads = 1,
  }) : mxlen = Mxlen.mxlen_32;

  const RiverCore._64({
    this.vendorId = 0,
    this.archId = 0,
    this.impId = 0,
    this.hartId = 0,
    this.resetVector = 0,
    required this.clock,
    required this.extensions,
    required this.interrupts,
    required this.mmu,
    this.microcodeMode = MicrocodeMode.none,
    this.executionMode = ExecutionMode.in_order,
    this.l1cache,
    this.hasSupervisor = false,
    this.hasUser = false,
    required this.type,
    this.icsVersion,
    this.threads = 1,
  }) : mxlen = Mxlen.mxlen_64;

  String? get implementsName {
    final hasI = extensions.any((e) => e.key == 'I');
    final hasE = extensions.any((e) => e.key == 'E');

    if (!hasI && !hasE) {
      return null;
    }

    final baseLetter = hasE ? 'E' : 'I';
    final base = 'RV${mxlen.size}$baseLetter';

    final buf = StringBuffer(base);

    for (final ext in extensions) {
      final key = ext.key;
      if (key == null) continue;
      if (key == baseLetter) continue;
      buf.write(key);
    }

    return buf.toString();
  }

  Microcode get microcode => Microcode(Microcode.buildDecodeMap(extensions));

  @override
  String toString() =>
      'RiverCore(vendorId: $vendorId, archId: $archId, hartId: $hartId,'
      ' resetVector: $resetVector, clock: $clock, ${implementsName != null ? 'implements: $implementsName' : 'extensions: $extensions'}, interrupts: $interrupts,'
      ' mmu: $mmu, microcodeMode: $microcodeMode, executionMode: $executionMode, l1Cache: $l1cache, type: $type, icsVersion: $icsVersion, threads: $threads)';
}

class RiverPortMap {
  final String name;
  final List<int> pins;
  final Map<String, String> devices;
  final bool isOutput;

  int get width => pins.length.bitLength;

  const RiverPortMap(
    this.name,
    this.pins,
    this.devices, {
    this.isOutput = false,
  });

  @override
  String toString() =>
      'RiverPortMap($name, pins: $pins, devices: $devices, isOutput: $isOutput)';
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

  /// Physical pinout of the SoC
  List<RiverPortMap> get ports;

  const RiverSoC();

  RiverCore? getCore(int hartId) {
    for (final core in cores) {
      if (core.hartId == hartId) {
        return core;
      }
    }
    return null;
  }

  Device? getDevice(String name) {
    for (final dev in devices) {
      if (dev.name == name) return dev;
    }
    return null;
  }

  @override
  String toString() =>
      'RiverSoC(devices: $devices, clients: $clients, cores: $cores, fabric: $fabric, clocks: $clocks, ports: $ports)';
}
