import 'package:flutter/foundation.dart';

import 'ble_channel.dart';

class RingStats {
  final int steps;
  final int calories;
  final double distanceKm;
  final int sleepMinutes;

  const RingStats({
    required this.steps,
    required this.calories,
    required this.distanceKm,
    required this.sleepMinutes,
  });

  factory RingStats.fromMap(Map<String, dynamic> m) => RingStats(
        steps: (m['steps'] as num?)?.toInt() ?? 0,
        calories: (m['calories'] as num?)?.toInt() ?? 0,
        distanceKm: ((m['distanceMeters'] as num?)?.toInt() ?? 0) / 1000.0,
        sleepMinutes: (m['sleepMinutes'] as num?)?.toInt() ?? 0,
      );
}

class BloodPressureReading {
  final int systolic;
  final int diastolic;
  final DateTime timestamp;

  const BloodPressureReading({
    required this.systolic,
    required this.diastolic,
    required this.timestamp,
  });

  factory BloodPressureReading.fromMap(Map<String, dynamic> m) => BloodPressureReading(
        systolic: (m['systolic'] as num?)?.toInt() ?? 0,
        diastolic: (m['diastolic'] as num?)?.toInt() ?? 0,
        // The SDK's other timestamp fields are unix seconds (matches
        // getDayStartUnixSeconds used elsewhere), so assuming seconds
        // here too rather than milliseconds.
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          ((m['timestampSeconds'] as num?)?.toInt() ?? 0) * 1000,
        ),
      );
}

/// App-wide holder for the last-synced ring stats. This is a plain
/// ValueNotifier rather than a new state-management dependency - Home and
/// Devices both just listen to it. Callers (screens) are responsible for
/// running this through BluetoothGate first, same as every other
/// BleChannel entry point.
class RingStatsStore {
  RingStatsStore._();

  static final ValueNotifier<RingStats?> current = ValueNotifier(null);
  static final ValueNotifier<BloodPressureReading?> bloodPressure = ValueNotifier(null);

  /// Throws on failure (not connected, permission slip, GATT error) -
  /// callers should catch and surface the message rather than swallow it.
  static Future<void> sync() async {
    final raw = await BleChannel.syncTodayStats();
    current.value = RingStats.fromMap(raw);
  }

  /// Throws on failure, including when the ring simply has no reading
  /// recorded yet today - that's a normal, expected case, not a bug.
  static Future<void> syncBloodPressure() async {
    final raw = await BleChannel.syncBloodPressure();
    bloodPressure.value = BloodPressureReading.fromMap(raw);
  }
}
