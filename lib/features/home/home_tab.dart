import 'package:flutter/material.dart';

import '../../core/ble_channel.dart';
import '../../core/theme.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _connected = false;
  int? _lastBpm;

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
          setState(() => _lastBpm = (e['bpm'] as num).toInt());
          break;
      }
    });
  }

  Future<void> _refreshConnectionState() async {
    final connected = await BleChannel.isConnected();
    if (mounted) setState(() => _connected = connected);
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
          style: TextStyle(
            color: _connected ? ZentraColors.teal : ZentraColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.15,
          children: [
            _VitalCard(
              label: 'Heart rate',
              value: _lastBpm != null ? '$_lastBpm' : '--',
              unit: 'bpm',
              icon: Icons.favorite,
              accent: ZentraColors.danger,
            ),
            const _VitalCard(
              label: 'Steps',
              value: '--',
              unit: 'today',
              icon: Icons.directions_walk,
              accent: ZentraColors.teal,
            ),
            const _VitalCard(
              label: 'Sleep',
              value: '--',
              unit: 'last night',
              icon: Icons.bedtime_outlined,
              accent: ZentraColors.gold,
            ),
            const _VitalCard(
              label: 'Recovery',
              value: '--',
              unit: 'score',
              icon: Icons.bolt_outlined,
              accent: ZentraColors.teal,
            ),
          ],
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

  const _VitalCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 22),
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
