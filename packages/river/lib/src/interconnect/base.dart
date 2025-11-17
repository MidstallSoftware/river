import '../bus.dart';

/// Transaction type
enum TransactionType {
  /// A read transaction
  ///
  /// Reads data from the client to the host
  read,

  /// A write transaction
  ///
  /// Takes data from the host and writes it to the client
  write,
}

/// Interconnect transaction
class Transaction {
  /// Host port name
  final String host;

  /// Client port name
  final String client;

  /// Type of transaction to perform
  final TransactionType type;

  /// Address on the client
  final int address;

  /// Width of the data
  final int width;

  const Transaction({
    required this.host,
    required this.client,
    required this.type,
    required this.address,
    required this.width,
  });

  const Transaction.read({
    required this.host,
    required this.client,
    required this.address,
    required this.width,
  }) : type = TransactionType.read;

  const Transaction.write({
    required this.host,
    required this.client,
    required this.address,
    required this.width,
  }) : type = TransactionType.read;
}

/// Abstract interconnect interface
abstract class Interconnect {
  /// Arbitration method on the interconnect
  BusArbitration get arbitration;

  /// Host ports on the interconnect
  List<BusHostPort> get hosts;

  /// Client ports on the interconnect
  List<BusClientPort> get clients;

  const Interconnect();

  BusClientPort? getClient(int addr) {
    for (final client in clients) {
      if (client.range.contains(addr)) {
        return client;
      }
    }
    return null;
  }

  /// Creates a read transaction
  Transaction? read(String hostName, BusRead req);

  /// Creates a write transaction
  Transaction? write(String hostName, BusWrite req);
}
