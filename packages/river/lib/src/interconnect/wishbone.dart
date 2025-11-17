import '../bus.dart';
import 'base.dart';

class WishboneFabric extends Interconnect {
  @override
  final BusArbitration arbitration;

  final List<BusClientPort> clients;
  final List<BusHostPort> hosts;

  const WishboneFabric({
    required this.arbitration,
    required this.hosts,
    required this.clients,
  });

  @override
  Transaction? read(String hostName, BusRead req) {
    final client = getClient(req.addr);
    if (client == null) return null;

    return Transaction.read(
      host: hostName,
      client: client!.name,
      address: req.addr,
      width: req.width,
    );
  }

  @override
  Transaction? write(String hostName, BusWrite req) {
    final client = getClient(req.addr);
    if (client == null) return null;

    return Transaction.write(
      host: hostName,
      client: client!.name,
      address: req.addr,
      width: req.width,
    );
  }

  @override
  String toString() =>
      'WishboneFabric(arbitration: $arbitration, hosts: $hosts, clients: $clients)';
}
