import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Central Bluetooth permission gate.
///
/// Why this file exists: the QRing SDK (com.oudmon.ble.base /
/// com.realsil.sdk.bbpro) never checks Android runtime permissions itself
/// and never catches SecurityException - a single missed check before any
/// scan/connect/GATT call throws straight out of the SDK and crashes the
/// app. Every screen that touches BleChannel MUST call
/// `BluetoothGate.ensureGrantedOrPrompt(context)` first and bail out if it
/// returns false. Do not add a second, ad-hoc permission check somewhere
/// else - route everything through here so there is exactly one place to
/// fix if Android's permission model changes again.
class BluetoothGate {
  BluetoothGate._();

  static const List<Permission> _required = <Permission>[
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    // Still required for BLE scan results on Android 6-11 (API 23-30).
    // permission_handler no-ops this on newer OS versions where it isn't
    // needed, so it's safe to always include.
    Permission.locationWhenInUse,
  ];

  /// True only if every permission the ring SDK needs is currently granted.
  /// Cheap - call this on screen entry / resume, not just once at pairing,
  /// since the user (or Android) can revoke permissions between sessions.
  static Future<bool> isGranted() async {
    for (final p in _required) {
      if (!await p.isGranted) return false;
    }
    return true;
  }

  /// Requests anything missing. Returns true only if the user ends up
  /// granting all of it.
  static Future<bool> ensureGranted() async {
    final statuses = await _required.request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// Convenience for screens: ensures permissions are granted, and if not,
  /// shows an explanatory dialog (with a shortcut to system settings when
  /// the user has permanently denied) instead of letting a stray
  /// SecurityException from the SDK crash the app.
  ///
  /// Returns true iff it's now safe to call into BleChannel.
  static Future<bool> ensureGrantedOrPrompt(BuildContext context) async {
    if (await isGranted()) return true;

    final granted = await ensureGranted();
    if (granted) return true;

    if (!context.mounted) return false;

    final permanentlyDenied = await Permission.bluetoothConnect.isPermanentlyDenied;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bluetooth permission needed'),
        content: Text(
          permanentlyDenied
              ? 'Zentra needs Bluetooth and Nearby devices permission to '
                'talk to your ring. You\'ve denied this permanently - '
                'enable it from app settings to continue.'
              : 'Zentra needs Bluetooth and Nearby devices permission to '
                'talk to your ring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          if (permanentlyDenied)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openAppSettings();
              },
              child: const Text('Open settings'),
            )
          else
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ensureGranted();
              },
              child: const Text('Grant'),
            ),
        ],
      ),
    );

    return isGranted();
  }
}
