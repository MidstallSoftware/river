import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

class MmioReadInterface extends PairInterface {
  late final int dataWidth;
  late final int addrWidth;

  Logic get en => port('en');
  Logic get addr => port('addr');
  Logic get data => port('data');
  Logic get done => port('done');
  Logic get valid => port('valid');

  MmioReadInterface(int dataWidth, int addrWidth)
    : super(
        portsFromConsumer: [Logic.port('en'), Logic.port('addr', addrWidth)],
        portsFromProvider: [
          Logic.port('data', dataWidth),
          Logic.port('done'),
          Logic.port('valid'),
        ],
      ) {
    this.dataWidth = dataWidth;
    this.addrWidth = addrWidth;
  }

  @override
  MmioReadInterface clone() => MmioReadInterface(dataWidth, addrWidth);
}

class MmioWriteInterface extends PairInterface {
  late final int dataWidth;
  late final int addrWidth;

  Logic get en => port('en');
  Logic get addr => port('addr');
  Logic get data => port('data');
  Logic get done => port('done');
  Logic get valid => port('valid');

  MmioWriteInterface(int dataWidth, int addrWidth)
    : super(
        portsFromConsumer: [Logic.port('done'), Logic.port('valid')],
        portsFromProvider: [
          Logic.port('en'),
          Logic.port('addr', addrWidth),
          Logic.port('data', dataWidth),
        ],
      ) {
    this.dataWidth = dataWidth;
    this.addrWidth = addrWidth;
  }

  @override
  MmioWriteInterface clone() => MmioWriteInterface(dataWidth, addrWidth);
}

class DeviceModule extends BridgeModule {
  final Device config;
  final bool? useFields;

  Logic? get interrupt =>
      config.interrupts.isNotEmpty ? output('interrupt') : null;

  late final InterfaceReference<MmioReadInterface>? mmioRead;
  late final InterfaceReference<MmioWriteInterface>? mmioWrite;

  DeviceModule(Mxlen mxlen, this.config, super.name, {this.useFields}) {
    if (config.clock != null) createPort('clk', PortDirection.input);
    createPort('reset', PortDirection.input);

    if (config.interrupts.isNotEmpty)
      addOutput('interrupt', width: config.interrupts.length.bitLength);

    final clk = config.clock != null ? input('clk') : null;
    final reset = input('reset');

    List<Conditional> doReset = [
      if (config.interrupts.isNotEmpty) interrupt! < 0,
      ...this.reset(),
    ];

    List<Conditional> inner = [if (config.clock != null) ...increment()];

    if (config.range != null) {
      final addrWidth = config.range!.size.bitLength;

      mmioRead = addInterface(
        MmioReadInterface(mxlen.size, addrWidth),
        name: 'mmioRead',
        role: PairRole.provider,
      );
      mmioWrite = addInterface(
        MmioWriteInterface(mxlen.size, addrWidth),
        name: 'mmioWrite',
        role: PairRole.consumer,
      );

      final ifRead = read(
        mmioRead!.internalInterface!.addr,
        mmioRead!.internalInterface!.data,
      );
      final ifWrite = write(
        mmioWrite!.internalInterface!.addr,
        mmioWrite!.internalInterface!.data,
      );

      doReset.addAll([
        mmioRead!.internalInterface!.data < 0,
        mmioRead!.internalInterface!.done < 0,
        mmioRead!.internalInterface!.valid < 0,
        mmioWrite!.internalInterface!.done < 0,
        mmioWrite!.internalInterface!.valid < 0,
      ]);

      inner.addAll([
        if (config.interrupts.isNotEmpty) interrupt! < interrupts(),
        If(
          mmioRead!.internalInterface!.en,
          then: [
            If.block([
              for (final r in ifRead)
                Iff(r.condition, [
                  ...r.then,
                  mmioRead!.internalInterface!.done < 1,
                  mmioRead!.internalInterface!.valid < 1,
                ]),
              if (ifRead.isNotEmpty)
                Else([
                  mmioRead!.internalInterface!.data < 0,
                  mmioRead!.internalInterface!.done < 1,
                  mmioRead!.internalInterface!.valid < 0,
                ]),
            ]),
          ],
          orElse: [
            mmioRead!.internalInterface!.data < 0,
            mmioRead!.internalInterface!.done < 0,
            mmioRead!.internalInterface!.valid < 0,
          ],
        ),
        If(
          mmioWrite!.internalInterface!.en,
          then: [
            If.block([
              for (final w in ifWrite)
                Iff(w.condition, [
                  ...w.then,
                  mmioWrite!.internalInterface!.done < 1,
                  mmioWrite!.internalInterface!.valid < 1,
                ]),
              if (ifWrite.isNotEmpty)
                Else([
                  mmioWrite!.internalInterface!.done < 1,
                  mmioWrite!.internalInterface!.valid < 0,
                ]),
            ]),
          ],
          orElse: [
            mmioWrite!.internalInterface!.done < 0,
            mmioWrite!.internalInterface!.valid < 0,
          ],
        ),
      ]);
    } else {
      mmioRead = null;
      mmioWrite = null;
    }

    if (config.clock != null) {
      assert(clk != null, 'Device requires a clock input');

      Sequential(clk!, [If(reset, then: doReset, orElse: inner)]);
    } else {
      Combinational([If(reset, then: doReset, orElse: inner)]);
    }
  }

  List<Conditional> reset() => [];
  List<Conditional> increment() => [];

  Logic interrupts() => Const(0, width: config.interrupts.length.bitLength);

  List<Conditional> readField(String name, Logic data) => [];
  List<Conditional> writeField(String name, Logic data) => [];

  List<Iff> read(Logic addr, Logic data) {
    if (useFields ?? config.accessor != null) {
      List<Iff> result = [];

      for (final field in config.accessor!.fields.values) {
        final start = config.accessor!.fieldAddress(field.name)!;
        final end = start + field.width;

        result.add(
          Iff(addr.gte(start) & addr.lt(end), readField(field.name, data)),
        );
      }

      return result;
    }

    return [];
  }

  List<Iff> write(Logic addr, Logic data) {
    if (useFields ?? config.accessor != null) {
      List<Iff> result = [];

      for (final field in config.accessor!.fields.values) {
        final start = config.accessor!.fieldAddress(field.name)!;
        final end = start + field.width;

        result.add(
          Iff(addr.gte(start) & addr.lt(end), writeField(field.name, data)),
        );
      }

      return result;
    }

    return [];
  }
}
