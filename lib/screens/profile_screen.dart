import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'plan_trip_screen.dart';
import 'settings_screen.dart';

/// Profile: avatar, stats, and working account/preferences rows.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tagCount = state.spots.expand((spot) => spot.tags).toSet().length;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: PressButton(
                  semanticLabel: 'Open settings',
                  onTap: () => Navigator.of(context)
                      .push(AppMotion.slideUp(const SettingsScreen())),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0x14FFFFFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.settings_rounded,
                        color: AppColors.textPrimary, size: 21),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline, width: 2),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2A2A2E), Color(0xFF141416)],
                        ),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: AppColors.textPrimary, size: 42),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      AppInfo.handle,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${AppInfo.name} explorer',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _Stat('${state.viewedCount}', 'Viewed'),
                  _Stat('${state.savedSpots.length}', 'Saved'),
                  _Stat('$tagCount', 'Tags'),
                ],
              ),
              const SizedBox(height: 24),
              _RowTile(
                icon: Icons.map_outlined,
                title: 'Plan a trip',
                onTap: () => Navigator.of(context)
                    .push(AppMotion.slideUp(const PlanTripScreen())),
              ),
              const SizedBox(height: 10),
              _RowTile(
                icon: Icons.tune_rounded,
                title: 'Settings',
                onTap: () => Navigator.of(context)
                    .push(AppMotion.slideUp(const SettingsScreen())),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  '${AppInfo.name} v${AppInfo.version}',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textFaint, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}
