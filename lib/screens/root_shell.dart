import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/state_views.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'saved_screen.dart';
import 'submit_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _locationRequested = false;

  late final AnimationController _tabFadeController;
  late final Animation<double> _tabFade;

  static const _screens = <Widget>[
    HomeScreen(),
    MapScreen(),
    SavedScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _tabFadeController = AnimationController(
      vsync: this,
      duration: AppMotion.quick,
      value: 1,
    );
    _tabFade = CurvedAnimation(
      parent: _tabFadeController,
      curve: AppMotion.easeOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_locationRequested && mounted) {
        _locationRequested = true;
        // Ask once at startup; harmless if denied.
        context.read<AppState>().requestLocation();
      }
    });
  }

  void _openSubmit() {
    Navigator.of(context).push(
      AppMotion.slideUpModal(const SubmitScreen()),
    );
  }

  /// Switches tab and replays a short fade so the change does not feel abrupt.
  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _tabFadeController.forward(from: 0.35);
  }

  @override
  void dispose() {
    _tabFadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.loading && state.spots.isEmpty) {
      return const Scaffold(body: LoadingView());
    }

    if (state.error != null && state.spots.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: ErrorView(
            message:
                'Check your connection and try again. Your saves are safe on '
                'this device.',
            onRetry: state.load,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kWideBreakpoint;

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                _SideRail(
                  index: _index,
                  onChanged: _selectTab,
                ),
                const VerticalDivider(width: 1, color: AppColors.hairline),
                Expanded(
                  child: FadeTransition(
                    opacity: _tabFade,
                    child: IndexedStack(index: _index, children: _screens),
                  ),
                ),
              ],
            ),
            floatingActionButton: (_index == 0 || _index == 1)
                ? _SubmitFab(onTap: _openSubmit)
                : null,
          );
        }

        return Scaffold(
          body: FadeTransition(
            opacity: _tabFade,
            child: IndexedStack(index: _index, children: _screens),
          ),
          bottomNavigationBar: _NavBar(
            index: _index,
            onChanged: _selectTab,
          ),
          floatingActionButton: (_index == 0 || _index == 1)
              ? _SubmitFab(onTap: _openSubmit)
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home'),
    (icon: Icons.map_outlined, active: Icons.map_rounded, label: 'Map'),
    (
      icon: Icons.bookmark_outline_rounded,
      active: Icons.bookmark_rounded,
      label: 'Saved'
    ),
    (
      icon: Icons.person_outline_rounded,
      active: Icons.person_rounded,
      label: 'Profile'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: _items[i].icon,
                    activeIcon: _items[i].active,
                    label: _items[i].label,
                    selected: index == i,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textFaint;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PressButton(
        onTap: onTap,
        child: SizedBox(
          height: 62,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, color: color, size: 23),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      backgroundColor: AppColors.background,
      selectedIndex: index,
      onDestinationSelected: onChanged,
      labelType: NavigationRailLabelType.all,
      indicatorColor: const Color(0x1AFFFFFF),
      selectedIconTheme:
          const IconThemeData(color: AppColors.textPrimary, size: 23),
      unselectedIconTheme:
          const IconThemeData(color: AppColors.textFaint, size: 23),
      selectedLabelTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: AppColors.textFaint,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        fontFamily: 'Inter',
      ),
      leading: const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'p.',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            fontFamily: 'Inter',
          ),
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map_rounded),
          label: Text('Map'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.bookmark_outline_rounded),
          selectedIcon: Icon(Icons.bookmark_rounded),
          label: Text('Saved'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: Text('Profile'),
        ),
      ],
    );
  }
}

class _SubmitFab extends StatelessWidget {
  const _SubmitFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add a spot',
      child: PressButton(
        semanticLabel: 'Add a spot',
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.action,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded,
              color: AppColors.onAction, size: 28),
        ),
      ),
    );
  }
}
