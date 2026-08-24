import 'package:flutter/foundation.dart';

import 'ble_channel.dart';
import 'ring_stats.dart';

enum HrZone { rest, warmUp, fatBurn, cardio, peak }

String hrZoneLabel(HrZone zone) {
  switch (zone) {
    case HrZone.rest:
      return 'Rest';
    case HrZone.warmUp:
      return 'Warm-up';
    case HrZone.fatBurn:
      return 'Fat burn';
    case HrZone.cardio:
      return 'Cardio';
    case HrZone.peak:
      return 'Peak';
  }
}

/// Buckets a reading using the standard 220-age max-HR estimate. Age isn't
/// collected yet, so this defaults to 30 - a visible approximation, not a
/// personalized calculation.
HrZone classifyHrZone(int bpm, {int age = 30}) {
  final maxHr = 220 - age;
  final pct = bpm / maxHr;
  if (pct < 0.5) return HrZone.rest;
  if (pct < 0.6) return HrZone.warmUp;
  if (pct < 0.7) return HrZone.fatBurn;
  if (pct < 0.85) return HrZone.cardio;
  return HrZone.peak;
}

class HrSample {
  final int bpm;
  final DateTime time;

  const HrSample({required this.bpm, required this.time});
}

/// Derived, app-side health metrics - separate from RingStatsStore, which
/// only holds values the ring itself reported. Everything in this file is
/// either a direct live measurement (heart rate, HRV) or something Zentra
/// calculated from those readings (zones, readiness). The readiness score
/// especially: it is NOT a device reading, and the UI should always label
/// it as an estimate.
class HealthMetricsStore {
  HealthMetricsStore._();

  static final ValueNotifier<int?> lastHeartRate = ValueNotifier(null);
  static final ValueNotifier<int?> lastStress = ValueNotifier(null);
  static final ValueNotifier<int?> lastHrv = ValueNotifier(null);

  /// Every HR reading seen today (from "Check heart rate" taps and live
  /// Activity sessions) - in memory only, resets on app restart. This is
  /// "readings we happened to take", not continuous monitoring, so it
  /// backs a "lowest reading today" stat, not a clinical "resting heart
  /// rate" (which needs continuous overnight sensing this app doesn't do).
  static final ValueNotifier<List<HrSample>> todaySamples = ValueNotifier([]);

  static void recordHeartRate(int bpm) {
    lastHeartRate.value = bpm;
    todaySamples.value = [...todaySamples.value, HrSample(bpm: bpm, time: DateTime.now())];
  }

  static void recordStress(int stress) {
    lastStress.value = stress;
  }

  /// Pulls the ring's latest periodic heart-rate sample (see
  /// BleChannel.syncHeartRate) - this is what Home actually uses. Throws
  /// on failure; the caller should catch and surface that.
  static Future<void> syncHeartRateNow() async {
    final raw = await BleChannel.syncHeartRate();
    recordHeartRate((raw['bpm'] as num).toInt());
  }

  /// WARNING: confirmed non-functional on the H59MAX_F104 ring - see
  /// BleChannel.checkHeartRate. Kept in case other hardware supports it;
  /// not called by the current UI.
  static Future<void> checkHeartRateNow() async {
    final raw = await BleChannel.checkHeartRate();
    recordHeartRate((raw['bpm'] as num).toInt());
    if (raw['stress'] != null) {
      recordStress((raw['stress'] as num).toInt());
    }
  }

  static Future<void> checkHrvNow() async {
    final raw = await BleChannel.checkHrv();
    lastHrv.value = (raw['hrvMs'] as num).toInt();
  }

  static int? get todayMinBpm {
    final s = todaySamples.value;
    if (s.isEmpty) return null;
    return s.map((e) => e.bpm).reduce((a, b) => a < b ? a : b);
  }

  static int? get todayMaxBpm {
    final s = todaySamples.value;
    if (s.isEmpty) return null;
    return s.map((e) => e.bpm).reduce((a, b) => a > b ? a : b);
  }

  static double? get todayAvgBpm {
    final s = todaySamples.value;
    if (s.isEmpty) return null;
    return s.map((e) => e.bpm).reduce((a, b) => a + b) / s.length;
  }

  /// Count of today's readings per zone - a distribution of spot-checks,
  /// not time-in-zone. True time-in-zone needs continuous sampling this
  /// app doesn't do; don't relabel this as "time in zone" without building
  /// that first.
  static Map<HrZone, int> get todayZoneCounts {
    final counts = {for (final z in HrZone.values) z: 0};
    for (final sample in todaySamples.value) {
      final zone = classifyHrZone(sample.bpm);
      counts[zone] = (counts[zone] ?? 0) + 1;
    }
    return counts;
  }

  /// A simple composite score - Zentra's own formula, not a device
  /// reading. v1: based on today's latest readings only; no multi-day
  /// baseline yet (would need persisted history across days - a natural
  /// next step, not built here). Null until at least a heart rate reading
  /// exists; SpO2 and HRV fold in opportunistically when available.
  static int? get readinessScore {
    final hr = lastHeartRate.value;
    if (hr == null) return null;

    double score = 70;

    if (hr < 60) {
      score += 15;
    } else if (hr <= 75) {
      score += 5;
    } else if (hr <= 90) {
      score -= 5;
    } else {
      score -= 15;
    }

    final spo2Latest = RingStatsStore.spo2.value?.latest;
    if (spo2Latest != null) {
      if (spo2Latest >= 97) {
        score += 10;
      } else if (spo2Latest >= 95) {
        score += 3;
      } else {
        score -= 15;
      }
    }

    final hrv = lastHrv.value;
    if (hrv != null) {
      if (hrv >= 60) {
        score += 10;
      } else if (hrv >= 30) {
        score += 2;
      } else {
        score -= 8;
      }
    }

    return score.clamp(0, 100).round();
  }
}
