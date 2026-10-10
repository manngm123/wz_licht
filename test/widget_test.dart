import 'package:flutter_test/flutter_test.dart';

import 'package:wohnzimmer_licht/device_store.dart';

void main() {
  test('Lamp JSON roundtrip', () {
    final lamp = Lamp(name: 'Vorn', ip: '192.168.1.20', mac: 'AA:BB', sku: 'H6008');
    final copy = Lamp.fromJson(lamp.toJson());

    expect(copy.name, 'Vorn');
    expect(copy.ip, '192.168.1.20');
    expect(copy.id, 'AA:BB');
  });
}
