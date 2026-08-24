import 'package:flutter/material.dart';

import '../../core/auto_sync.dart';
import '../activity/live_workout_screen.dart';
import '../devices/devices_tab.dart';
import '../home/home_tab.dart';
import '../profile/profile_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = [
    HomeTab(),
    LiveWorkoutScreen(),
    DevicesTab(),
    ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    // App-open auto-sync, every 1 minute. See core/auto_sync.dart for
    // exactly what it does and doesn't cover.
    AutoSyncController.start();
  }

  @override
  void dispose() {
    AutoSyncController.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: _tabs)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_outline), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Icons.watch_outlined), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
