import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/ble_channel.dart';
import '../../core/health_metrics.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';

class LiveWorkoutScreen extends StatefulWidget {
  const LiveWorkoutScreen({super.key});

  @override
  State<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends State<LiveWorkoutScreen> {
  StreamSubscription? _sub;
  bool _active = false;
  bool _starting = false;
  int? _currentBpm;
  final List<FlSpot> _samples = [];

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _sub = BleChannel.events().listen((e) {
      if (!mounted || e['type'] != 'heartRate') return;
      final bpm = (e['bpm'] as num).toInt();
      // Feed the same shared tracker Home's "Check heart rate" uses, so
      // today's zone breakdown reflects workout readings too, not just
      // one-shot checks.
      HealthMetricsStore.recordHeartRate(bpm);
      if (e['stress'] != null) {
        HealthMetricsStore.recordStress((e['stress'] as num).toInt());
      }
      setState(() {
        _currentBpm = bpm;
        _samples.add(FlSpot(_samples.length.toDouble(), bpm.toDouble()));
        if (_samples.length > 60) _samples.removeAt(0);
      });
    });
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'zentra_workout_channel',
        channelName: 'Workout tracking',
        channelDescription: 'Shown while Zentra is tracking a live workout from your ring.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      // Bluetooth first - this is the exact call sequence that used to
      // crash: connect() could succeed while a later GATT write (starting
      // the HR stream) threw because permission was never actually
      // confirmed at *this* point in the flow.
      final btOk = await BluetoothGate.ensureGrantedOrPrompt(context);
      if (!btOk) return;

      final connected = await BleChannel.isConnected();
      if (!connected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connect your ring first, from the Devices tab.')),
        );
        return;
      }

      // Android 13+ requires POST_NOTIFICATIONS before a foreground
      // service can show its status notification.
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Workout in progress',
          notificationText: 'Tracking live heart rate from your ring',
        );
      }

      await BleChannel.startLiveHeartRate();
      setState(() => _active = true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    await BleChannel.stopLiveHeartRate();
    await FlutterForegroundTask.stopService();
    setState(() {
      _active = false;
      _samples.clear();
      _currentBpm = null;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: ZentraColors.danger),
                      const SizedBox(width: 8),
                      Text(
                        _currentBpm != null ? '$_currentBpm bpm' : '-- bpm',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 140,
                    child: _samples.length < 2
                        ? const Center(
                            child: Text('Live trace appears once tracking starts',
                                style: TextStyle(color: ZentraColors.textSecondary)),
                          )
                        : LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _samples,
                                  isCurved: true,
                                  color: ZentraColors.teal,
                                  barWidth: 2,
                                  dotData: const FlDotData(show: false),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _starting
                ? null
                : (_active ? _stop : _start),
            style: _active
                ? ElevatedButton.styleFrom(backgroundColor: ZentraColors.danger)
                : null,
            child: Text(_active ? 'Stop workout' : 'Start workout'),
          ),
        ],
      ),
    );
  }
}
