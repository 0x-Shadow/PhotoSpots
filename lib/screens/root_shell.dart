import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
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

  /// Lets a deep link (e.g. a spot's mini-map) switch tabs and focus the map.
  static void Function(int slot)? _tabOpener;

  static void openTab(int slot) => _tabOpener?.call(slot);

  static void openMapAt(LatLng point) {
    MapScreen.focusRequest.value = point;
    openTab(1);
  }

  @override
  State<RootShell> createState() => _RootShellState();
}

/// The bar has five slots but only four screens; Add is the middle slot.
int _screenIndexForSlot(int slot) => slot > 2 ? slot - 1 : slot;

int _slotForScreenIndex(int index) => index >= 2 ? index + 1 : index;

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  /// Screen index (0–3); the Add slot sits between Map and Saved in the bar.
  int _index = 0;

  /// Screens are built the first time they are visited. An IndexedStack would
  /// otherwise build and keep alive the map, its tiles and every animation
  /// while the user is on Home.
  final Set<int> _built = {0};

  late final AnimationController _tabController;
  late final Animation<double> _tabFade;
  late final Animation<double> _tabScale;

  static const _screens = <Widget>[
    HomeScreen(),
    MapScreen(),
    SavedScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = AnimationController(
      vsync: this,
      duration: AppMotion.quick,
      value: 1,
    );
    _tabFade = CurvedAnimation(
      parent: _tabController,
      curve: AppMotion.easeOut,
    );
    _tabScale = Tween<double>(begin: 0.98, end: 1.0).animate(_tabFade);
    RootShell._tabOpener = _selectSlot;
  }

  void _openSubmit() {
    Navigator.of(context).push(AppMotion.slideUpModal(const SubmitScreen()));
  }

  /// Handles a bar slot: Add opens the flow, the other slots switch tabs and
  /// replay a short fade + lift so the change does not feel abrupt.
  void _selectSlot(int slot) {
    if (slot == 2) {
      _openSubmit();
      return;
    }
    final index = _screenIndexForSlot(slot);
    if (index == _index) return;
    setState(() {
      _index = index;
      _built.add(index);
    });
    _tabController.forward(from: 0.35);
  }

  Widget _animatedScreen() {
    final stack = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _screens.length; i++)
          if (_built.contains(i))
            TickerMode(enabled: i == _index, child: _screens[i])
          else
            const SizedBox.shrink(),
      ],
    );
    if (MediaQuery.disableAnimationsOf(context)) return stack;
    return FadeTransition(
      opacity: _tabFade,
      child: ScaleTransition(scale: _tabScale, child: stack),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (RootShell._tabOpener == _selectSlot) RootShell._tabOpener = null;
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
                  selectedSlot: _slotForScreenIndex(_index),
                  onSlotSelected: _selectSlot,
                  onAdd: _openSubmit,
                ),
                const VerticalDivider(width: 1, color: AppColors.hairline),
                Expanded(child: _animatedScreen()),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          // The bar floats visually (rounded glass pill on inset margins) but
          // still owns its layout space, so page content can never slide under
          // it and steal taps. No BackdropFilter: that forces the whole body
          // into an offscreen layer that renders soft on GLES emulators.
          body: _animatedScreen(),
          bottomNavigationBar: _NavBar(
            selectedSlot: _slotForScreenIndex(_index),
            onSlotSelected: _selectSlot,
          ),
        );
      },
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.selectedSlot, required this.onSlotSelected});

  final int selectedSlot;
  final ValueChanged<int> onSlotSelected;

  static const _items = <({IconData icon, IconData active, String label})?>[
    (icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home'),
    (icon: Icons.map_outlined, active: Icons.map_rounded, label: 'Map'),
    null,
    (
      icon: Icons.bookmark_outline_rounded,
      active: Icons.bookmark_rounded,
      label: 'Saved',
    ),
    (
      icon: Icons.person_outline_rounded,
      active: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  /// Bar height above the home indicator.
  static const double barHeight = 62;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E10),
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _items[i] == null
                      ? _AddAction(onTap: () => onSlotSelected(2))
                      : _NavItem(
                          icon: _items[i]!.icon,
                          activeIcon: _items[i]!.active,
                          label: _items[i]!.label,
                          selected: selectedSlot == i,
                          onTap: () => onSlotSelected(i),
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
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.quick;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PressButton(
        onTap: onTap,
        child: SizedBox(
          height: _NavBar.barHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: motion,
                curve: AppMotion.easeOut,
                width: 52,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0x14FFFFFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  selected ? activeIcon : icon,
                  color: color,
                  size: 21,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: motion,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: color,
                  fontSize: 10.5,
                  height: 1.1,
                  letterSpacing: 0.1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(label, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The always-available middle slot. It is a real bar item, not a floating
/// button, so it can never cover a map pin or a list card.
class _AddAction extends StatelessWidget {
  const _AddAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressButton(
      semanticLabel: 'Add a spot',
      onTap: onTap,
      child: SizedBox(
        height: _NavBar.barHeight,
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.action,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_rounded,
              color: AppColors.onAction,
              size: 25,
            ),
          ),
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.selectedSlot,
    required this.onSlotSelected,
    required this.onAdd,
  });

  final int selectedSlot;
  final ValueChanged<int> onSlotSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium!;
    return NavigationRail(
      backgroundColor: AppColors.background,
      selectedIndex: _screenIndexForSlot(selectedSlot),
      onDestinationSelected: (index) =>
          onSlotSelected(_slotForScreenIndex(index)),
      labelType: NavigationRailLabelType.all,
      indicatorColor: const Color(0x1AFFFFFF),
      selectedIconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 23,
      ),
      unselectedIconTheme: const IconThemeData(
        color: AppColors.textFaint,
        size: 23,
      ),
      selectedLabelTextStyle: labelStyle.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: labelStyle.copyWith(
        color: AppColors.textFaint,
      ),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: _AddAction(onTap: onAdd),
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
