import 'package:flutter/material.dart';

import '../../core/theme.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Profile, goals, and settings screens go here. '
                'This tab is intentionally a placeholder in this rebuild - '
                'swap in your real profile/settings UI whenever you have it.',
                style: TextStyle(color: ZentraColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
