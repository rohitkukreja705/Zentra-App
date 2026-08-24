import 'dart:async';

import 'ble_channel.dart';
import 'permissions.dart';
import 'ring_stats.dart';

/// Periodically re-pulls the cheap "already stored on the ring" data -
/// steps/calories/sleep and SpO2 - every minute while the app is open.
///
/// Deliberately does NOT include heart rate, stress, or HRV: those need an
/// active PPG measurement each time (manualModeHeart/manualModeHrv), which
/// takes up to ~30s and draws more ring power. Running that automatically
/// every 60s isn't how any reference app does it either - they're all
/// tap-to-check for exactly that reason. Heart rate/HRV stay manual, via
/// the "Check heart rate" button and Activity tab.
///
/// App-open only for now (started from MainShell, stopped on dispose) -
/// not a background service. Checks silently, no permission prompts or
/// error toasts: a revoked permission or disconnected ring just means
/// "skip this cycle", since this is a convenience refresh, not a
/// user-initiated action expecting a result.
class AutoSyncController {
  AutoSyncController._();

  static Timer? _timer;

  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _tick() async {
    if (!await BluetoothGate.isGranted()) return;
    if (!await BleChannel.isConnected()) return;

    try {
      await RingStatsStore.sync();
    } catch (_) {
      // Silent by design - see class doc.
    }
    try {
      await RingStatsStore.syncSpO2();
    } catch (_) {
      // Silent by design - see class doc.
    }
  }
}
