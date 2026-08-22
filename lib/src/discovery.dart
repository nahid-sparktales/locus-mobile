import 'package:multicast_dns/multicast_dns.dart';

import 'protocol.dart';

class BonjourDiscovery {
  const BonjourDiscovery();

  Future<List<String>> discover({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final client = MDnsClient();
    final endpoints = <String>{};
    try {
      await client.start();
      final pointers = client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('$locusServiceType.local'),
          )
          .timeout(timeout);
      await for (final pointer in pointers) {
        final services = client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(pointer.domainName),
        );
        await for (final service in services) {
          final ipv4 = client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(service.target),
          );
          await for (final address in ipv4) {
            endpoints.add('wss://${address.address.address}:${service.port}');
          }
          final ipv6 = client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv6(service.target),
          );
          await for (final address in ipv6) {
            final value = address.address.address.split('%').first;
            endpoints.add('wss://[$value]:${service.port}');
          }
        }
      }
    } on Object {
      // Discovery is an optimization. Saved LAN and Tailscale endpoints remain.
    } finally {
      client.stop();
    }
    return endpoints.toList(growable: false);
  }
}
