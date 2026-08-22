import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ble_channel.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';

class DevicesTab extends StatefulWidget {
  const DevicesTab({super.key});

  @override
  State<DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<DevicesTab> {
  final Map<String, ScannedRing> _found = {};
  StreamSubscription? _sub;
  bool _scanning = false;
  String? _connectingAddress;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _sub = BleChannel.events().listen((e) {
      if (!mounted) return;
      switch (e['type']) {
        case 'scanResult':
          final ring = ScannedRing.fromMap(e);
          setState(() => _found[ring.address] = ring);
          break;
        case 'connectionState':
          setState(() {
            _connected = e['state'] == 'connected';
            if (_connected || e['state'] == 'disconnected') {
              _connectingAddress = null;
            }
          });
          break;
      }
    });
    BleChannel.isConnected().then((c) {
      if (mounted) setState(() => _connected = c);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_scanning) BleChannel.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    // The single most important line in this screen: nothing below this
    // point may call into BleChannel unless this returned true. See
    // core/permissions.dart for why.
    final ok = await BluetoothGate.ensureGrantedOrPrompt(context);
    if (!ok) return;

    setState(() {
      _found.clear();
      _scanning = true;
    });
    await BleChannel.startScan();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _scanning) setState(() => _scanning = false);
    });
  }

  Future<void> _connect(ScannedRing ring) async {
    final ok = await BluetoothGate.ensureGrantedOrPrompt(context);
    if (!ok) return;

    setState(() => _connectingAddress = ring.address);
    await BleChannel.stopScan();
    setState(() => _scanning = false);
    final success = await BleChannel.connect(ring.address);
    if (!mounted) return;
    if (!success) {
      setState(() => _connectingAddress = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not connect to ${ring.name}. Make sure it\'s nearby and charged.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rings = _found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Devices', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            _connected ? 'Ring connected' : 'No ring connected',
            style: TextStyle(color: _connected ? ZentraColors.teal : ZentraColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _scanning ? null : _startScan,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_scanning ? 'Scanning...' : 'Scan for rings'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: rings.isEmpty
                ? Center(
                    child: Text(
                      _scanning ? 'Looking for nearby rings...' : 'Tap "Scan for rings" to find your device.',
                      style: const TextStyle(color: ZentraColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: rings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final ring = rings[i];
                      final connecting = _connectingAddress == ring.address;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.watch, color: ZentraColors.teal),
                          title: Text(ring.name),
                          subtitle: Text(ring.address),
                          trailing: connecting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text('${ring.rssi} dBm', style: const TextStyle(color: ZentraColors.textSecondary)),
                          onTap: connecting ? null : () => _connect(ring),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
