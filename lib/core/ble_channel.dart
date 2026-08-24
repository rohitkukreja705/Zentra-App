import 'dart:async';

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
///
/// Every method call is also routed through [_serialized]: BleOperateManager
/// is a singleton that stores in-flight measurement state in shared mutable
/// fields (confirmed by reading the decompiled SDK - the same fields
/// manualModePressure and manualModeHrv both write to), not per-call state.
/// Two commands fired at the same time - e.g. the 1-minute auto-sync tick
/// landing while a manual "Check now" is still running - can interfere with
/// each other and both time out. Running everything through one queue
/// means nothing ever overlaps, regardless of what triggered it.
class BleChannel {
  BleChannel._();

  static const MethodChannel _method = MethodChannel('wearables/ble');
  static const EventChannel _events = EventChannel('wearables/ble/events');

  static Stream<Map<dynamic, dynamic>>? _eventStream;
  static Future<void> _queue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Connection state changes, live heart-rate samples, and scan results
  /// pushed from the native side. Payload shape:
  ///   {type: "connectionState", state: "connected"|"connecting"|"disconnected"}
  ///   {type: "heartRate", bpm: 72, timestamp: 1234567890}
  ///   {type: "scanResult", name: "...", address: "AA:BB:...", rssi: -60}
  ///
  /// Not routed through the queue - this is an incoming push stream, not
  /// an outgoing command, so it isn't part of the overlap problem above.
  static Stream<Map<dynamic, dynamic>> events() {
    _eventStream ??= _events.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>);
    return _eventStream!;
  }

  static Future<void> startScan({Duration timeout = const Duration(seconds: 8)}) {
    return _serialized(() => _method.invokeMethod('startScan', {'timeoutMs': timeout.inMilliseconds}));
  }

  static Future<void> stopScan() => _serialized(() => _method.invokeMethod('stopScan'));

  static Future<bool> connect(String address) {
    return _serialized(() async {
      final ok = await _method.invokeMethod<bool>('connect', {'address': address});
      return ok ?? false;
    });
  }

  static Future<void> disconnect() => _serialized(() => _method.invokeMethod('disconnect'));

  static Future<bool> isConnected() {
    return _serialized(() async {
      final ok = await _method.invokeMethod<bool>('isConnected');
      return ok ?? false;
    });
  }

  static Future<void> startLiveHeartRate() => _serialized(() => _method.invokeMethod('startLiveHeartRate'));

  static Future<void> stopLiveHeartRate() => _serialized(() => _method.invokeMethod('stopLiveHeartRate'));

  /// Pulls today's step/calorie/distance/sleep totals stored on the ring.
  /// This is a pull, not a stream - the ring counts steps on its own
  /// hardware and holds the running total; there's no live push for this
  /// in the SDK (unlike heart rate), so this needs to be called whenever
  /// you want a fresh number, not just once.
  static Future<Map<String, dynamic>> syncTodayStats() {
    return _serialized(() async {
      final result = await _method.invokeMapMethod<String, dynamic>('syncTodayStats');
      if (result == null) {
        throw PlatformException(code: 'SYNC_FAILED', message: 'No data returned');
      }
      return result;
    });
  }

  /// Pulls the ring's own periodically auto-sampled heart rate (latest
  /// non-zero reading today). This is the reliable path on hardware where
  /// manual/on-demand measurement isn't supported - see checkHeartRate
  /// doc and QRingBridge.kt for why that matters here.
  static Future<Map<String, dynamic>> syncHeartRate() {
    return _serialized(() async {
      final result = await _method.invokeMapMethod<String, dynamic>('syncHeartRate');
      if (result == null) {
        throw PlatformException(code: 'SYNC_FAILED', message: 'No data returned');
      }
      return result;
    });
  }

  /// Pulls today's SpO2 reading(s) already stored on the ring. Pull-based,
  /// same as syncTodayStats - does not trigger a new measurement.
  static Future<Map<String, dynamic>> syncSpO2() {
    return _serialized(() async {
      final result = await _method.invokeMapMethod<String, dynamic>('syncSpO2');
      if (result == null) {
        throw PlatformException(code: 'SYNC_FAILED', message: 'No data returned');
      }
      return result;
    });
  }

  /// One-shot: actively commands the ring to take a fresh heart-rate
  /// reading right now, waits for the first valid sample (up to ~30s),
  /// then stops the measurement automatically. Unlike
  /// startLiveHeartRate/stopLiveHeartRate (continuous stream used by the
  /// Activity tab), this resolves once with a single result - built for a
  /// tap-and-wait "check now" button.
  ///
  /// WARNING: confirmed non-functional on the H59MAX_F104 ring - see the
  /// matching comment in QRingBridge.kt. Not used by the current UI;
  /// syncHeartRate is what Home actually calls.
  static Future<Map<String, dynamic>> checkHeartRate() {
    return _serialized(() async {
      final result = await _method.invokeMapMethod<String, dynamic>('checkHeartRate');
      if (result == null) {
        throw PlatformException(code: 'CHECK_FAILED', message: 'No data returned');
      }
      return result;
    });
  }

  /// One-shot live HRV measurement - same tap-and-wait shape as
  /// checkHeartRate. Deliberately not a "today" pull; see QRingBridge.kt
  /// for why.
  static Future<Map<String, dynamic>> checkHrv() {
    return _serialized(() async {
      final result = await _method.invokeMapMethod<String, dynamic>('checkHrv');
      if (result == null) {
        throw PlatformException(code: 'CHECK_FAILED', message: 'No data returned');
      }
      return result;
    });
  }
}
