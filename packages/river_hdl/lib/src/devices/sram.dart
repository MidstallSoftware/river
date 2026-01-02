import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import '../dev.dart';

const _kSramAddrWidth = <String, int>{'SB_RAM40_4K': 11};

const _kSramDataWidth = <String, int>{'SB_RAM40_4K': 16};

class _RiverSramExternal extends ExternalSystemVerilogModule {
  _RiverSramExternal(
    String defName,
    Logic clk,
    Logic reset,
    DataPortInterface read,
    DataPortInterface write, {
    String name = 'external_module',
  }) : super(definitionName: defName, name: name) {
    final mapping = switch (defName) {
      'SB_RAM40_4K' => const {
        'clk': ['RCLK', 'WCLK'],
        'read.en': ['RE'],
        'read.addr': ['RADDR'],
        'read.data': ['RDATA'],
        'read.done': ['0'],
        'read.valid': ['1'],
        'write.en': ['WE'],
        'write.addr': ['WADDR'],
        'write.data': ['WDATA'],
        'write.done': ['0'],
        'write.valid': ['1'],
      },
      _ => throw UnsupportedError('Unknown SRAM block $defName'),
    };

    final inputs = <String, Logic>{
      'clk': clk,
      'reset': reset,
      'read.en': read.en,
      'read.addr': read.addr,
      'write.en': write.en,
      'write.addr': write.addr,
      'write.data': write.data,
    };

    final outputs = <String, Logic>{
      'read.data': read.data,
      'read.done': read.done,
      'read.valid': read.valid,
      'write.done': write.done,
      'write.valid': write.valid,
    };

    for (final i in inputs.entries) {
      if (mapping.containsKey(i.key)) {
        for (final n in mapping[i.key]!) {
          addInput(n, i.value, width: i.value.width);
        }
      }
    }

    for (final o in outputs.entries) {
      if (mapping.containsKey(o.key)) {
        for (final n in mapping[o.key]!) {
          final c = int.tryParse(n);
          if (c != null) {
            o.value <= Const(c, width: o.value.width);
          } else {
            o.value <= addOutput(n, width: o.value.width);
          }
        }
      }
    }
  }
}

class _RiverSramArray extends Module {
  late final LogicArray _mem;

  _RiverSramArray(
    Logic clk,
    Logic reset,
    DataPortInterface read,
    DataPortInterface write, {
    super.name = 'array',
  }) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    read = read.clone()
      ..connectIO(
        this,
        read,
        outputTags: {DataPortGroup.data, DataPortGroup.integrity},
        inputTags: {DataPortGroup.control},
        uniquify: (og) => 'read_$og',
      );

    write = write.clone()
      ..connectIO(
        this,
        write,
        outputTags: {DataPortGroup.integrity},
        inputTags: {DataPortGroup.control, DataPortGroup.data},
        uniquify: (og) => 'write_$og',
      );

    _mem = LogicArray([1 << read.addrWidth], write.dataWidth, name: 'mem');

    final int shift = switch (read.dataWidth ~/ 8) {
      4 => 2,
      8 => 3,
      _ => throw UnsupportedError('Invalid XLEN=${read.dataWidth}'),
    };

    Sequential(clk, [
      If(
        reset,
        then: [
          read.data < 0,
          read.done < 0,
          read.valid < 0,
          write.done < 0,
          write.valid < 0,
        ],
        orElse: [
          If(
            read.en,
            then: [
              read.data <
                  List.generate(
                    read.dataWidth,
                    (i) => _mem[(read.addr + i) >> shift],
                  ).swizzle(),
              read.done < 1,
              read.valid < 1,
            ],
            orElse: [read.data < 0, read.done < 0, read.valid < 0],
          ),
          If(
            write.en,
            then: [
              _mem <
                  (_mem |
                      (write.data << (write.addr * write.dataWidth)).zeroExtend(
                        _mem.width,
                      )),
              write.done < 1,
              write.valid < 1,
            ],
            orElse: [write.done < 0, write.valid < 0],
          ),
        ],
      ),
    ]);
  }
}

class RiverSramModule extends DeviceModule {
  final String? externalName;

  RiverSramModule(Mxlen mxlen, Device config)
    : externalName = null,
      super(mxlen, config, resetState: false);
  RiverSramModule.ext(Mxlen mxlen, Device config, String name)
    : externalName = name,
      super(mxlen, config, resetState: false);

  @override
  Map<String, Logic> initState() {
    final clk = port('clk').port;
    final reset = port('reset').port;

    final busDataWidth = mxlen.size;
    final busAddrWidth = (config.mmap!.size ~/ mxlen.width).bitLength + 2;

    final dataWidth = externalName != null
        ? _kSramDataWidth[externalName!]!
        : busDataWidth;
    final addrWidth = externalName != null
        ? _kSramAddrWidth[externalName!]!
        : busAddrWidth;

    final readPort = DataPortInterface(busDataWidth, busAddrWidth);
    final writePort = DataPortInterface(busDataWidth, busAddrWidth);

    if (externalName == null) {
      _RiverSramArray(clk, reset, readPort, writePort);
    } else {
      if (busDataWidth != dataWidth && busAddrWidth != addrWidth) {
        final count = (busAddrWidth ~/ addrWidth) > 1
            ? (busAddrWidth ~/ addrWidth)
            : busDataWidth ~/ dataWidth;

        final shift = switch (mxlen.width) {
          4 => 2,
          8 => 3,
          _ => throw UnsupportedError('Unsupported XLEN=${mxlen.size}'),
        };

        final readAddr = (readPort.addr >> shift).slice(addrWidth - 1, 0);
        final writeAddr = (writePort.addr >> shift).slice(addrWidth - 1, 0);

        List<DataPortInterface> reads = [];
        List<DataPortInterface> writes = [];

        for (var i = 0; i < count; i++) {
          final innerRead = DataPortInterface(dataWidth, addrWidth);
          reads.add(innerRead);

          final innerWrite = DataPortInterface(dataWidth, addrWidth);
          writes.add(innerWrite);

          innerRead.en <= readPort.en;
          innerRead.addr <= readAddr;

          final hi = i * dataWidth;
          final lo = (i + 1) * dataWidth - 1;

          innerWrite.en <= writePort.en;
          innerWrite.addr <= writeAddr;
          innerWrite.data <= writePort.data.slice(hi, lo);

          _RiverSramExternal(
            externalName!,
            clk,
            reset,
            innerRead,
            innerWrite,
            name: 'bank$i',
          );
        }

        readPort.data <= reads.map((r) => r.data).toList().swizzle();
        readPort.done <=
            reads.map((r) => r.done).fold(Const(1), (acc, i) => acc & i);
        readPort.valid <=
            reads.map((r) => r.valid).fold(Const(1), (acc, i) => acc & i);

        writePort.done <=
            writes.map((w) => w.done).fold(Const(1), (acc, i) => acc & i);
        writePort.valid <=
            writes.map((w) => w.valid).fold(Const(1), (acc, i) => acc & i);
      } else {
        _RiverSramExternal(externalName!, clk, reset, readPort, writePort);
      }
    }

    return {
      'readEnable': readPort.en,
      'readAddr': readPort.addr,
      'readData': readPort.data,
      'readDone': readPort.done,
      'readValid': readPort.valid,
      'writeEnable': writePort.en,
      'writeAddr': writePort.addr,
      'writeData': writePort.data,
      'writeDone': writePort.done,
      'writeValid': writePort.valid,
    };
  }

  @override
  List<Conditional> reset() => [
    state('readEnable') < 0,
    state('readAddr') < 0,
    state('writeEnable') < 0,
    state('writeAddr') < 0,
    state('writeData') < 0,
  ];

  @override
  List<Conditional> readPort(
    Logic en,
    Logic addr,
    Logic data,
    Logic done,
    Logic valid,
  ) => [
    state('readEnable') < en,
    state('readAddr') < addr,
    If(
      en,
      then: [
        data < state('readData'),
        done < state('readDone'),
        valid < state('readValid'),
      ],
      orElse: [
        data < Const(0, width: mxlen.size),
        done < 0,
        valid < 0,
      ],
    ),
  ];

  @override
  List<Conditional> writePort(
    Logic en,
    Logic addr,
    Logic data,
    Logic done,
    Logic valid,
  ) => [
    state('writeEnable') < en,
    state('writeAddr') < addr,
    state('writeData') < data,
    If(
      en,
      then: [done < state('writeDone'), valid < state('writeValid')],
      orElse: [done < 0, valid < 0],
    ),
  ];

  static DeviceModule create(
    Mxlen mxlen,
    Device config,
    Map<String, String> options,
  ) {
    if (options.containsKey('definitionName')) {
      return RiverSramModule.ext(mxlen, config, options['definitionName']!);
    }
    return RiverSramModule(mxlen, config);
  }
}
