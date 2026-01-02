import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

typedef DeviceModuleFactory =
    DeviceModule Function(Mxlen, Device, Map<String, String>);

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
  final Mxlen mxlen;
  late final Device config;
  final bool? useFields;
  final bool resetState;

  late Map<String, Logic> _state;

  Logic? get interrupt =>
      config.interrupts.isNotEmpty ? output('interrupt') : null;

  late final InterfaceReference<MmioReadInterface>? mmioRead;
  late final InterfaceReference<MmioWriteInterface>? mmioWrite;

  DeviceModule(
    this.mxlen,
    Device config, {
    this.useFields,
    this.resetState = true,
  }) : super(config.module, name: config.name) {
    this.config = config;

    if (config.clock != null) createPort('clk', PortDirection.input);
    createPort('reset', PortDirection.input);

    if (config.interrupts.isNotEmpty)
      addOutput('interrupt', width: config.interrupts.length.bitLength);

    for (final port in config.ports) {
      createPort(
        port.name,
        port.isOutput ? PortDirection.output : PortDirection.input,
        width: port.width,
      );
    }

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
    } else {
      mmioRead = null;
      mmioWrite = null;
    }

    final clk = config.clock != null ? port('clk').port : null;
    final reset = port('reset').port;

    _state = initState();

    final innerReset = this.reset();
    final resetUses = innerReset
        .map((r) => r.receivers)
        .fold<List<Logic>>([], (acc, i) => [...acc, ...i]);

    List<Conditional> doReset = [
      if (config.interrupts.isNotEmpty) interrupt! < 0,
      for (final p
          in config.ports
              .where((p) => p.isOutput)
              .where((p) => !resetUses.contains(port(p.name).port)))
        port(p.name).port < 0,
      if (resetState)
        for (final s in _state.values.where((r) => !resetUses.contains(r)))
          s < 0,
      ...innerReset,
    ];

    List<Conditional> inner = [if (config.clock != null) ...increment()];

    if (config.range != null) {
      doReset.addAll([
        mmioRead!.internalInterface!.data < 0,
        mmioRead!.internalInterface!.done < 0,
        mmioRead!.internalInterface!.valid < 0,
        mmioWrite!.internalInterface!.done < 0,
        mmioWrite!.internalInterface!.valid < 0,
      ]);

      inner.addAll([
        if (config.interrupts.isNotEmpty) interrupt! < interrupts(),
        ...readPort(
          mmioRead!.internalInterface!.en,
          mmioRead!.internalInterface!.addr,
          mmioRead!.internalInterface!.data,
          mmioRead!.internalInterface!.done,
          mmioRead!.internalInterface!.valid,
        ),
        ...writePort(
          mmioWrite!.internalInterface!.en,
          mmioWrite!.internalInterface!.addr,
          mmioWrite!.internalInterface!.data,
          mmioWrite!.internalInterface!.done,
          mmioWrite!.internalInterface!.valid,
        ),
      ]);
    }

    if (config.clock != null) {
      assert(clk != null, 'Device requires a clock input');

      Sequential(clk!, [If(reset, then: doReset, orElse: inner)]);
    } else {
      Combinational([If(reset, then: doReset, orElse: inner)]);
    }
  }

  Logic state(String name) => _state[name]!;

  Map<String, Logic> initState() => {};

  List<Conditional> reset() => [];

  List<Conditional> increment() => [];

  Logic interrupts() => Const(0, width: config.interrupts.length.bitLength);

  List<Conditional> readField(String name, Logic data) => [data < 0];

  List<Conditional> writeField(String name, Logic data) => [];

  List<Conditional> read(Logic addr, Logic data, Logic done, Logic valid) {
    if (!(useFields ?? config.accessor != null)) return [];

    final busBytes = data.width ~/ 8;
    final busEnd = addr + Const(busBytes, width: addr.width);

    final conds = <Conditional>[];

    final fieldValues = Map.fromEntries(
      config.accessor!.fields.values.map(
        (field) => MapEntry(
          field.name,
          Logic(name: 'readField_${field.name}', width: field.width * 8),
        ),
      ),
    );

    final hitAny = Logic(name: 'mmioReadHit');

    conds.addAll([data < 0, done < 1, hitAny < 0, valid < 0]);

    for (final field in config.accessor!.fields.values) {
      final fieldStart = config.accessor!.fieldAddress(field.name)!;
      final fieldBytes = field.width;
      final fieldEnd = fieldStart + fieldBytes;

      final overlaps =
          Const(fieldStart, width: addr.width).lt(busEnd) &
          Const(fieldEnd, width: addr.width).gt(addr);

      final fieldValue = fieldValues[field.name]!;

      conds.add(
        If(
          overlaps,
          then: [
            ...readField(field.name, fieldValue),

            for (var lane = 0; lane < busBytes; lane++)
              for (var fb = 0; fb < fieldBytes; fb++) ...[
                If(
                  (addr + Const(lane, width: addr.width)).eq(
                    Const(fieldStart + fb, width: addr.width),
                  ),
                  then: [
                    hitAny < 1,
                    data <
                        (data |
                            (fieldValue
                                    .getRange(fb * 8, (fb + 1) * 8)
                                    .zeroExtend(data.width) <<
                                (lane * 8))),
                  ],
                ),
              ],
          ],
        ),
      );
    }

    conds.add(valid < hitAny);
    return conds;
  }

  List<Conditional> write(Logic addr, Logic data, Logic done, Logic valid) {
    if (!(useFields ?? config.accessor != null)) return [];

    final busBytes = data.width ~/ 8;
    final busEnd = addr + Const(busBytes, width: addr.width);

    final conds = <Conditional>[];

    final hitAny = Logic(name: 'mmioWriteHit');

    conds.addAll([done < 1, hitAny < 0, valid < 0]);

    for (final field in config.accessor!.fields.values) {
      final fieldStart = config.accessor!.fieldAddress(field.name)!;
      final fieldBytes = field.width;
      final fieldEnd = fieldStart + fieldBytes;

      final overlaps =
          Const(fieldStart, width: addr.width).lt(busEnd) &
          Const(fieldEnd, width: addr.width).gt(addr);

      final fieldValue = Logic(
        name: 'writeField_${field.name}',
        width: fieldBytes * 8,
      );
      final fieldHit = Logic(name: 'writeFieldHit_${field.name}');

      conds.addAll([fieldValue < 0, fieldHit < 0]);

      conds.add(
        If(
          overlaps,
          then: [
            for (var lane = 0; lane < busBytes; lane++)
              for (var fb = 0; fb < fieldBytes; fb++) ...[
                If(
                  (addr + Const(lane, width: addr.width)).eq(
                    Const(fieldStart + fb, width: addr.width),
                  ),
                  then: [
                    fieldHit < 1,
                    hitAny < 1,
                    fieldValue <
                        (fieldValue |
                            (data
                                    .getRange(lane * 8, (lane + 1) * 8)
                                    .zeroExtend(fieldValue.width) <<
                                (fb * 8))),
                  ],
                ),
              ],
          ],
        ),
      );

      conds.add(If(fieldHit, then: [...writeField(field.name, fieldValue)]));
    }

    conds.add(valid < hitAny);
    return conds;
  }

  List<Conditional> readPort(
    Logic en,
    Logic addr,
    Logic data,
    Logic done,
    Logic valid,
  ) => [
    If(
      en,
      then: read(addr, data, done, valid),
      orElse: [data < 0, done < 0, valid < 0],
    ),
  ];

  List<Conditional> writePort(
    Logic en,
    Logic addr,
    Logic data,
    Logic done,
    Logic valid,
  ) => [
    If(en, then: write(addr, data, done, valid), orElse: [done < 0, valid < 0]),
  ];
}
