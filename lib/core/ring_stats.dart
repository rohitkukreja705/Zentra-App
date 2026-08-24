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

class SpO2Reading {
  final int latest;
  final int dayMin;
  final DateTime timestamp;

  const SpO2Reading({required this.latest, required this.dayMin, required this.timestamp});

  factory SpO2Reading.fromMap(Map<String, dynamic> m) => SpO2Reading(
        latest: (m['latest'] as num?)?.toInt() ?? 0,
        dayMin: (m['dayMin'] as num?)?.toInt() ?? 0,
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
///
/// Deliberately does NOT include blood pressure: the SDK's BP value is
/// generated with Math.random() app-side (confirmed by reading
/// CalcBloodPressureByHeart.java and manualModePressure in the decompiled
/// SDK), not read from a real sensor. Displaying it as a health metric
/// would mean showing users a fabricated number.
class RingStatsStore {
  RingStatsStore._();

  static final ValueNotifier<RingStats?> current = ValueNotifier(null);
  static final ValueNotifier<SpO2Reading?> spo2 = ValueNotifier(null);

  /// Throws on failure (not connected, permission slip, GATT error) -
  /// callers should catch and surface the message rather than swallow it.
  static Future<void> sync() async {
    final raw = await BleChannel.syncTodayStats();
    current.value = RingStats.fromMap(raw);
  }

  static Future<void> syncSpO2() async {
    final raw = await BleChannel.syncSpO2();
    spo2.value = SpO2Reading.fromMap(raw);
  }
}
