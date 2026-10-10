// govee_lan.dart – Govee LAN-API (UDP) ohne Server
//
// Scan:    Multicast 239.255.255.250:4001
// Befehle: Unicast   <lampen-ip>:4003
// Antwort: an uns    Port 4002

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DeviceStatus {
  final bool on;
  final int brightness;
  final int? kelvin;

  const DeviceStatus({
    required this.on,
    required this.brightness,
    this.kelvin,
  });
}

class ScanResult {
  final String ip;
  final String mac;
  final String sku;

  const ScanResult({required this.ip, required this.mac, required this.sku});
}

class GoveeLan {
  static const String multicastAddress = '239.255.255.250';
  static const int scanPort = 4001;
  static const int listenPort = 4002;
  static const int controlPort = 4003;

  RawDatagramSocket? _socket;
  Future<void>? _starting;

  final Map<String, List<Completer<DeviceStatus>>> _statusWaiters = {};
  StreamController<ScanResult>? _scanStream;

  // ------------------------------------------------------------
  // Socket
  // ------------------------------------------------------------

  Future<void> start() {
    if (_socket != null) return Future.value();
    return _starting ??= _bind();
  }

  Future<void> _bind() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        listenPort,
        reuseAddress: true,
      );

      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;

      try {
        socket.joinMulticast(InternetAddress(multicastAddress));
      } catch (_) {
        // Nicht kritisch – Antworten kommen i.d.R. per Unicast.
      }

      socket.listen(_onEvent);
      _socket = socket;
    } finally {
      _starting = null;
    }
  }

  void dispose() {
    _socket?.close();
    _socket = null;
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final socket = _socket;
    if (socket == null) return;

    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      _handle(datagram!);
    }
  }

  void _handle(Datagram datagram) {
    Map<String, dynamic> msg;

    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      msg = Map<String, dynamic>.from(decoded['msg'] as Map);
    } catch (_) {
      return;
    }

    final cmd = msg['cmd'];
    final data = msg['data'] is Map
        ? Map<String, dynamic>.from(msg['data'] as Map)
        : <String, dynamic>{};

    if (cmd == 'scan') {
      final ip = (data['ip'] ?? datagram.address.address).toString();
      _scanStream?.add(ScanResult(
        ip: ip,
        mac: (data['device'] ?? ip).toString(),
        sku: (data['sku'] ?? '').toString(),
      ));
      return;
    }

    if (cmd == 'devStatus') {
      final ip = datagram.address.address;

      final status = DeviceStatus(
        on: _toInt(data['onOff']) == 1,
        brightness: _toInt(data['brightness']) ?? 0,
        kelvin: (_toInt(data['colorTemInKelvin']) ?? 0) > 0
            ? _toInt(data['colorTemInKelvin'])
            : null,
      );

      final waiters = _statusWaiters.remove(ip);
      if (waiters == null) return;

      for (final waiter in waiters) {
        if (!waiter.isCompleted) waiter.complete(status);
      }
    }
  }

  static int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _send(String ip, int port, String cmd, Map<String, dynamic> data) {
    final socket = _socket;
    if (socket == null) {
      throw const SocketException('UDP-Socket nicht bereit');
    }

    final payload = utf8.encode(jsonEncode({
      'msg': {'cmd': cmd, 'data': data},
    }));

    socket.send(payload, InternetAddress(ip), port);
  }

  // ------------------------------------------------------------
  // API
  // ------------------------------------------------------------

  /// Sucht Lampen im WLAN (LAN-Steuerung muss in der Govee-App aktiv sein).
  Future<List<ScanResult>> scan({
    Duration duration = const Duration(seconds: 3),
  }) async {
    await start();

    final found = <String, ScanResult>{};
    final stream = StreamController<ScanResult>.broadcast();
    _scanStream = stream;

    final sub = stream.stream.listen((result) {
      found[result.mac] = result;
    });

    // Mehrfach senden, UDP ist unzuverlässig
    for (var i = 0; i < 3; i++) {
      try {
        _send(multicastAddress, scanPort, 'scan', {'account_topic': 'reserve'});
      } catch (_) {}
      await Future.delayed(duration ~/ 3);
    }

    _scanStream = null;
    await sub.cancel();
    await stream.close();

    return found.values.toList();
  }

  Future<void> turn(String ip, bool on) async {
    await start();
    _send(ip, controlPort, 'turn', {'value': on ? 1 : 0});
  }

  Future<void> brightness(String ip, int value) async {
    await start();
    _send(ip, controlPort, 'brightness', {'value': value.clamp(1, 100)});
  }

  Future<DeviceStatus> status(
    String ip, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    await start();

    final completer = Completer<DeviceStatus>();
    _statusWaiters.putIfAbsent(ip, () => []).add(completer);

    _send(ip, controlPort, 'devStatus', {});

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _statusWaiters[ip]?.remove(completer);
      if (_statusWaiters[ip]?.isEmpty ?? false) _statusWaiters.remove(ip);
      rethrow;
    }
  }
}
