import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/ble_channel.dart';
import '../../core/health_metrics.dart';
import '../../core/permissions.dart';
import '../../core/ring_stats.dart';
import '../../core/theme.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _connected = false;
  bool _checkingHr = false;
  bool _checkingHrv = false;

  @override
  void initState() {
    super.initState();
    _refreshConnectionState();
    BleChannel.events().listen((e) {
      if (!mounted) return;
      switch (e['type']) {
        case 'connectionState':
          setState(() => _connected = e['state'] == 'connected');
          break;
        case 'heartRate':
          HealthMetricsStore.recordHeartRate((e['bpm'] as num).toInt());
          if (e['stress'] != null) {
            HealthMetricsStore.recordStress((e['stress'] as num).toInt());
          }
          break;
      }
    });
  }

  Future<void> _refreshConnectionState() async {
    final connected = await BleChannel.isConnected();
    if (mounted) setState(() => _connected = connected);
  }

  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout')) return 'ring didn\'t respond in time - make sure it\'s worn snugly';
    return e.toString();
  }

  Future<void> _syncHeartRateNow() async {
    final ok = await BluetoothGate.ensureGrantedOrPrompt(context);
    if (!ok) return;
    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect your ring first, from the Devices tab.')),
      );
      return;
    }
    setState(() => _checkingHr = true);
    try {
      await HealthMetricsStore.syncHeartRateNow();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get a reading: ${_friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingHr = false);
    }
  }

  Future<void> _checkHrvNow() async {
    final ok = await BluetoothGate.ensureGrantedOrPrompt(context);
    if (!ok) return;
    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect your ring first, from the Devices tab.')),
      );
      return;
    }
    setState(() => _checkingHrv = true);
    try {
      await HealthMetricsStore.checkHrvNow();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get an HRV reading: ${_friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingHrv = false);
    }
  }

  Color _zoneColor(HrZone zone) {
    switch (zone) {
      case HrZone.rest:
        return const Color(0xFF5B7DB1);
      case HrZone.warmUp:
        return ZentraColors.teal;
      case HrZone.fatBurn:
        return ZentraColors.gold;
      case HrZone.cardio:
        return const Color(0xFFE08A3C);
      case HrZone.peak:
        return ZentraColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Good to see you', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          _connected ? 'Ring connected' : 'Ring not connected',
          style: TextStyle(color: _connected ? ZentraColors.teal : ZentraColors.textSecondary),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: Listenable.merge([
            RingStatsStore.current,
            RingStatsStore.spo2,
            HealthMetricsStore.lastHeartRate,
            HealthMetricsStore.lastStress,
            HealthMetricsStore.lastHrv,
            HealthMetricsStore.todaySamples,
          ]),
          builder: (context, _) {
            final stats = RingStatsStore.current.value;
            final spo2 = RingStatsStore.spo2.value;
            final hr = HealthMetricsStore.lastHeartRate.value;
            final stress = HealthMetricsStore.lastStress.value;
            final hrv = HealthMetricsStore.lastHrv.value;
            final readiness = HealthMetricsStore.readinessScore;
            final zoneCounts = HealthMetricsStore.todayZoneCounts;
            final hasAnyZoneData = HealthMetricsStore.todaySamples.value.isNotEmpty;
            final hasAnything = stats != null || spo2 != null || hr != null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero action card - the primary "check now" entry point.
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [ZentraColors.teal.withValues(alpha: 0.9), ZentraColors.surfaceElevated],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Heart rate', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              hr != null ? '$hr bpm' : 'Tap to sync',
                              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Ring\'s latest reading - not a live measurement',
                              style: TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _checkingHr ? null : _syncHeartRateNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: ZentraColors.background,
                        ),
                        icon: _checkingHr
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync, size: 18),
                        label: Text(_checkingHr ? 'Syncing...' : 'Sync'),
                      ),
                    ],
                  ),
                ),

                if (readiness != null) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Text(
                            '$readiness',
                            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: ZentraColors.teal),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Zentra Readiness · estimate', style: TextStyle(fontWeight: FontWeight.w600)),
                                SizedBox(height: 2),
                                Text(
                                  'Calculated by Zentra from today\'s readings - not a device measurement.',
                                  style: TextStyle(fontSize: 11, color: ZentraColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.15,
                  children: [
                    _VitalCard(
                      label: 'Stress',
                      value: stress != null ? '$stress' : '--',
                      unit: 'ring reading',
                      icon: Icons.spa_outlined,
                      accent: ZentraColors.gold,
                    ),
                    _VitalCard(
                      label: 'Steps',
                      value: stats != null ? '${stats.steps}' : '--',
                      unit: 'today',
                      icon: Icons.directions_walk,
                      accent: ZentraColors.teal,
                    ),
                    _VitalCard(
                      label: 'Sleep',
                      value: stats != null ? '${(stats.sleepMinutes / 60).toStringAsFixed(1)}h' : '--',
                      unit: 'last night',
                      icon: Icons.bedtime_outlined,
                      accent: ZentraColors.gold,
                    ),
                    _VitalCard(
                      label: 'Calories',
                      value: stats != null ? '${stats.calories}' : '--',
                      unit: 'kcal today',
                      icon: Icons.bolt_outlined,
                      accent: ZentraColors.teal,
                    ),
                    _VitalCard(
                      label: 'SpO2',
                      value: spo2 != null ? '${spo2.latest}' : '--',
                      unit: '% today',
                      icon: Icons.air_outlined,
                      accent: const Color(0xFF5B9FD1),
                    ),
                    _VitalCard(
                      label: 'HRV',
                      value: hrv != null ? '$hrv' : '--',
                      unit: 'ms',
                      icon: Icons.show_chart,
                      accent: const Color(0xFFE08A3C),
                      trailing: _checkingHrv
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 16,
                              icon: const Icon(Icons.refresh, color: ZentraColors.textSecondary),
                              onPressed: _checkHrvNow,
                            ),
                    ),
                  ],
                ),

                if (hasAnyZoneData) ...[
                  const SizedBox(height: 20),
                  Text('Today\'s heart-rate zones', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  const Text(
                    'Distribution of spot-checks today, not continuous time-in-zone.',
                    style: TextStyle(fontSize: 11, color: ZentraColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 140,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 32,
                              sections: [
                                for (final zone in HrZone.values)
                                  if ((zoneCounts[zone] ?? 0) > 0)
                                    PieChartSectionData(
                                      value: (zoneCounts[zone] ?? 0).toDouble(),
                                      color: _zoneColor(zone),
                                      title: '',
                                      radius: 22,
                                    ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final zone in HrZone.values)
                                if ((zoneCounts[zone] ?? 0) > 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(color: _zoneColor(zone), shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${hrZoneLabel(zone)} (${zoneCounts[zone]})',
                                          style: const TextStyle(fontSize: 12, color: ZentraColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (!hasAnything) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'No data yet - tap "Sync" above for heart rate, or open the Devices '
                    'tab and tap "Sync ring data" for steps, sleep, and SpO2.',
                    style: TextStyle(color: ZentraColors.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VitalCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color accent;
  final Widget? trailing;

  const _VitalCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 22),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            Text(unit, style: const TextStyle(color: ZentraColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: ZentraColors.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
