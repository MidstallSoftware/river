import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:riscv/riscv.dart';
import 'package:river/river.dart';
import '../dev.dart';

class RiverUartModule extends DeviceModule {
  final int rxFifoDepth;
  final int txFifoDepth;

  late final Fifo _rxFifo;
  late final Fifo _txFifo;

  RiverUartModule(
    super.mxlen,
    super.config, {
    this.rxFifoDepth = 8,
    this.txFifoDepth = 8,
  }) : super(useFields: true);

  @override
  Map<String, Logic> initState() {
    final clk = port('clk').port;
    final reset = port('reset').port;

    final rxWrite = Logic(name: 'rxWrite');
    final rxRead = Logic(name: 'rxRead');
    final rxData = Logic(name: 'rxData', width: 8);

    final txWrite = Logic(name: 'txWrite');
    final txRead = Logic(name: 'txRead');
    final txData = Logic(name: 'txData', width: 8);

    _rxFifo = Fifo(
      clk,
      reset,
      writeEnable: rxWrite,
      writeData: rxData,
      readEnable: rxRead,
      depth: rxFifoDepth,
      name: 'rx_fifo',
    );

    _txFifo = Fifo(
      clk,
      reset,
      writeEnable: txWrite,
      writeData: txData,
      readEnable: txRead,
      depth: txFifoDepth,
      name: 'tx_fifo',
    );

    return {
      'dll': Logic(width: 8),
      'dlm': Logic(width: 8),
      'ier': Logic(width: 8),
      'iir': Logic(width: 8),
      'lcr': Logic(width: 8),
      'mcr': Logic(width: 8),
      'lsr': Logic(width: 8),
      'msr': Logic(width: 8),
      'scr': Logic(width: 8),
      'fcr': Logic(width: 8),

      'rxWrite': rxWrite,
      'rxRead': rxRead,
      'rxData': rxData,

      'txWrite': txWrite,
      'txRead': txRead,
      'txData': txData,

      'baudCount': Logic(width: 16),
      'baudDiv': Logic(width: 16),
      'baudTick': Logic(),

      'rxDiv': Logic(width: 16),
      'rxCount': Logic(width: 16),
      'rxTick': Logic(),

      'txBusy': Logic(),
      'txCount': Logic(width: 4),
      'txShift': Logic(width: 10),

      'rxBusy': Logic(),
      'rxPhase': Logic(width: 4),
      'rxSample': Logic(width: 4),
      'rxShift': Logic(width: 8),
    };
  }

  @override
  List<Conditional> reset() => [
    state('iir') < Const(1, width: 8),
    state('lsr') < Const(0x60, width: 8),
    port('tx').port < 1,
  ];

  @override
  List<Conditional> increment() {
    final rx = port('rx').port;
    final tx = port('tx').port;

    final dlab = state('lcr')[7];
    final div16 = [state('dlm'), state('dll')].swizzle();
    final rxDiv = mux(
      div16.lt(Const(16, width: 16)),
      Const(1, width: 16),
      div16 >> 4,
    );

    return [
      state('rxWrite') < 0,
      state('rxRead') < 0,
      state('txWrite') < 0,
      state('txRead') < 0,
      state('baudTick') < 0,
      state('rxTick') < 0,

      state('baudDiv') < div16,
      If(
        state('baudCount').eq(0),
        then: [
          state('baudCount') < mux(div16.eq(0), Const(1, width: 16), div16),
          state('baudTick') < 1,
        ],
        orElse: [state('baudCount') < state('baudCount') - 1],
      ),

      state('rxDiv') < rxDiv,
      If(
        state('rxCount').eq(0),
        then: [state('rxCount') < rxDiv, state('rxTick') < 1],
        orElse: [state('rxCount') < state('rxCount') - 1],
      ),

      If(
        ~state('txBusy') & ~_txFifo.empty,
        then: [
          state('txRead') < 1,
          state('txShift') <
              [
                Const(0, width: 1),
                _txFifo.readData,
                Const(1, width: 1),
              ].swizzle(),
          state('txCount') < 0,
          state('txBusy') < 1,
        ],
      ),

      If(
        state('txBusy') & state('baudTick'),
        then: [
          tx < state('txShift')[state('txCount')],
          state('txCount') < state('txCount') + 1,
          If(state('txCount').eq(9), then: [state('txBusy') < 0, tx < 1]),
        ],
        orElse: [
          If(~state('txBusy'), then: [tx < 1]),
        ],
      ),

      If(
        ~state('rxBusy') & rx.eq(0),
        then: [
          state('rxBusy') < 1,
          state('rxPhase') < 0,
          state('rxSample') < 0,
        ],
      ),

      If(
        state('rxBusy') & state('rxTick'),
        then: [
          state('rxSample') < state('rxSample') + 1,
          If(
            state('rxSample').eq(7),
            then: [
              If(
                state('rxPhase').eq(0),
                then: [
                  If(
                    rx.eq(0),
                    then: [state('rxPhase') < 1, state('rxShift') < 0],
                    orElse: [state('rxBusy') < 0],
                  ),
                ],
                orElse: [
                  If(
                    state('rxPhase').gte(1) & state('rxPhase').lte(8),
                    then: [
                      state('rxShift') <
                          (state('rxShift') |
                              (rx.zeroExtend(8) << (state('rxPhase') - 1))),
                      state('rxPhase') < state('rxPhase') + 1,
                    ],
                    orElse: [
                      If(
                        state('rxPhase').eq(9),
                        then: [
                          If(
                            rx.eq(1) & ~_rxFifo.full,
                            then: [
                              state('rxWrite') < 1,
                              state('rxData') < state('rxShift'),
                            ],
                          ),
                          state('rxBusy') < 0,
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              state('rxSample') < 0,
            ],
          ),
        ],
      ),

      state('lsr') <
          (Const(0, width: 8) |
              mux(~_rxFifo.empty, Const(0x01, width: 8), Const(0, width: 8)) |
              mux(
                ~_txFifo.empty | state('txBusy'),
                Const(0, width: 8),
                Const(0x20, width: 8),
              ) |
              mux(
                ~_txFifo.empty | state('txBusy'),
                Const(0, width: 8),
                Const(0x40, width: 8),
              )),

      If(
        state('ier')[0] & ~_rxFifo.empty,
        then: [state('iir') < Const(0x04, width: 8)],
        orElse: [
          If(
            state('ier')[1] & ~state('txBusy') & _txFifo.empty,
            then: [state('iir') < Const(0x02, width: 8)],
            orElse: [state('iir') < Const(0x01, width: 8)],
          ),
        ],
      ),
    ];
  }

  @override
  Logic interrupts() =>
      (~state('iir')[0]).zeroExtend(config.interrupts.length.bitLength);

  @override
  List<Conditional> readField(String name, Logic data) => switch (name) {
    'rbr_thr_dll' => [
      data <
          mux(
            state('lcr')[7],
            state('dll'),
            mux(~_rxFifo.empty, _rxFifo.readData, Const(0, width: 8)),
          ),
      If(~state('lcr')[7] & ~_rxFifo.empty, then: [state('rxRead') < 1]),
    ],
    'ier_dlm' => [data < mux(state('lcr')[7], state('dlm'), state('ier'))],
    'iir_fcr' => [
      data < (state('iir') | (state('fcr') & Const(0xC0, width: 8))),
    ],
    'lcr' => [data < state('lcr')],
    'mcr' => [data < state('mcr')],
    'lsr' => [data < state('lsr')],
    'msr' => [data < state('msr')],
    'scr' => [data < state('scr')],
    _ => [data < 0],
  };

  @override
  List<Conditional> writeField(String name, Logic data) => switch (name) {
    'rbr_thr_dll' => [
      If(
        state('lcr')[7],
        then: [state('dll') < data],
        orElse: [
          If(
            ~_txFifo.full,
            then: [state('txWrite') < 1, state('txData') < data],
          ),
        ],
      ),
    ],
    'ier_dlm' => [
      If(
        state('lcr')[7],
        then: [state('dlm') < data],
        orElse: [state('ier') < data],
      ),
    ],
    'iir_fcr' => [state('fcr') < data],
    'lcr' => [state('lcr') < data],
    'mcr' => [state('mcr') < data],
    'scr' => [state('scr') < data],
    _ => [],
  };

  static DeviceModule create(
    Mxlen mxlen,
    Device config,
    Map<String, String> options,
  ) {
    final rxFifoDepth = options.containsKey('rxFifoDepth')
        ? int.parse(options['rxFifoDepth']!)
        : 8;
    final txFifoDepth = options.containsKey('txFifoDepth')
        ? int.parse(options['txFifoDepth']!)
        : 8;

    return RiverUartModule(
      mxlen,
      config,
      rxFifoDepth: rxFifoDepth,
      txFifoDepth: txFifoDepth,
    );
  }
}
