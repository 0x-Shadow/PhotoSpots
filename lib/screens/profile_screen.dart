import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

/// Profile: photo circle, handle, stats, account rows.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
          children: [
            const SizedBox(height: 10),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: AppColors.textPrimary, size: 42),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ox-shadow',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Explorer · 42 places',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'Inter'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _Stat('42', 'Visited'),
                _Stat('12', 'Saved'),
                _Stat('8', 'Collections'),
              ],
            ),
            const SizedBox(height: 26),
            _RowTile(Icons.collections_bookmark_rounded, 'My Collections', trailing: 3),
            const SizedBox(height: 10),
            _RowTile(Icons.settings_rounded, 'Preferences'),
            const SizedBox(height: 10),
            _RowTile(Icons.brightness_6_rounded, 'App Settings'),
            const SizedBox(height: 30),
            Center(
              child: Text(
                'PhotoSpot v1.0.0 · Demo',
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
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
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontFamily: 'Inter'),
          ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile(this.icon, this.title, {this.trailing});

  final IconData icon;
  final String title;
  final int? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(icon, color: AppColors.textSecondary, size: 22),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
        trailing: trailing != null
            ? Text('$trailing', style: const TextStyle(
                color: AppColors.textFaint, fontSize: 13, fontWeight: FontWeight.w600))
            : const Icon(Icons.chevron_right_rounded,
                color: AppColors.textFaint, size: 20),
      ),
    );
  }
}
