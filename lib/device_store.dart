// device_store.dart – Lampen lokal speichern (Name, IP, MAC)

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Lamp {
  String name;
  String ip;
  String mac;
  String sku;

  Lamp({
    required this.name,
    required this.ip,
    required this.mac,
    this.sku = '',
  });

  /// Eindeutiger Schlüssel: MAC, bei manuell angelegten Lampen die IP.
  String get id => mac.isNotEmpty ? mac : ip;

  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        'mac': mac,
        'sku': sku,
      };

  factory Lamp.fromJson(Map<String, dynamic> json) => Lamp(
        name: (json['name'] ?? '').toString(),
        ip: (json['ip'] ?? '').toString(),
        mac: (json['mac'] ?? '').toString(),
        sku: (json['sku'] ?? '').toString(),
      );
}

class DeviceStore {
  static const _key = 'lamps';

  Future<List<Lamp>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Lamp.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Lamp> lamps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(lamps.map((l) => l.toJson()).toList()),
    );
  }
}
