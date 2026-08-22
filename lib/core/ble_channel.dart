import 'package:flutter/services.dart';

class ScannedRing {
  final String name;
  final String address;
  final int rssi;

  const ScannedRing({required this.name, required this.address, required this.rssi});

  factory ScannedRing.fromMap(Map<dynamic, dynamic> m) => ScannedRing(
        name: (m['name'] as String?)?.trim().isNotEmpty == true ? m['name'] as String : 'Unknown ring',
        address: m['address'] as String,
        rssi: (m['rssi'] as num?)?.toInt() ?? 0,
      );
}

enum RingConnectionState { disconnected, connecting, connected }

/// Dart side of the bridge to `QRingBridge.kt`, which wraps
/// `BleOperateManager` (com.oudmon.ble.base.bluetooth) from the QRing SDK.
///
/// Every method here assumes `BluetoothGate.ensureGrantedOrPrompt` has
/// already returned true - this class does not check permissions itself,
/// by design, so there is exactly one place (core/permissions.dart) that
/// owns that logic.
class BleChannel {
  BleChannel._();

  static const MethodChannel _method = MethodChannel('wearables/ble');
  static const EventChannel _events = EventChannel('wearables/ble/events');

  static Stream<Map<dynamic, dynamic>>? _eventStream;

  /// Connection state changes, live heart-rate samples, and scan results
  /// pushed from the native side. Payload shape:
  ///   {type: "connectionState", state: "connected"|"connecting"|"disconnected"}
  ///   {type: "heartRate", bpm: 72, timestamp: 1234567890}
  ///   {type: "scanResult", name: "...", address: "AA:BB:...", rssi: -60}
  static Stream<Map<dynamic, dynamic>> events() {
    _eventStream ??= _events.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>);
    return _eventStream!;
  }

  static Future<void> startScan({Duration timeout = const Duration(seconds: 8)}) {
    return _method.invokeMethod('startScan', {'timeoutMs': timeout.inMilliseconds});
  }

  static Future<void> stopScan() => _method.invokeMethod('stopScan');

  static Future<bool> connect(String address) async {
    final ok = await _method.invokeMethod<bool>('connect', {'address': address});
    return ok ?? false;
  }

  static Future<void> disconnect() => _method.invokeMethod('disconnect');

  static Future<bool> isConnected() async {
    final ok = await _method.invokeMethod<bool>('isConnected');
    return ok ?? false;
  }

  static Future<void> startLiveHeartRate() => _method.invokeMethod('startLiveHeartRate');

  static Future<void> stopLiveHeartRate() => _method.invokeMethod('stopLiveHeartRate');
}
