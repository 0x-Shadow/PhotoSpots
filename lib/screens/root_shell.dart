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
    setState(() => _index = index);
    _tabController.forward(from: 0.35);
  }

  Widget _animatedScreen() {
    if (MediaQuery.disableAnimationsOf(context)) {
      return IndexedStack(index: _index, children: _screens);
    }
    return FadeTransition(
      opacity: _tabFade,
      child: ScaleTransition(
        scale: _tabScale,
        child: IndexedStack(index: _index, children: _screens),
      ),
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

  /// Bar height, and the gap it floats above the home indicator.
  static const double barHeight = 82;
  static const double sideInset = 16;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        0,
        sideInset,
        bottomInset > 8 ? bottomInset - 2 : 14,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF71E1E22), Color(0xFA0B0B0C)],
          ),
          border: Border.all(color: const Color(0x2EFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0xC7000000),
              blurRadius: 32,
              spreadRadius: -6,
              offset: Offset(0, 16),
            ),
            BoxShadow(
              color: Color(0x14FFFFFF),
              blurRadius: 2,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / _items.length;
              // Slot 2 is the Add action; nothing sits behind it.
              final showIndicator = selectedSlot != 2;
              return Stack(
                children: [
                  // Liquid-glass sheen: a specular edge along the top and a
                  // diagonal light sweep. Painted, not a backdrop filter, so
                  // no saveLayer is created and text behind never softens.
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0x2EFFFFFF),
                              Color(0x00FFFFFF),
                              Color(0x0FFFFFFF),
                            ],
                            stops: [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 22,
                    right: 22,
                    child: Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0x99FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // One travelling glass pill marks the active tab.
                  AnimatedPositioned(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.layout,
                    curve: AppMotion.easeOut,
                    left: itemWidth * selectedSlot + 7,
                    top: 10,
                    width: itemWidth - 14,
                    height: barHeight - 20,
                    child: AnimatedOpacity(
                      duration: AppMotion.instant,
                      opacity: showIndicator ? 1 : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x2EFFFFFF), Color(0x14FFFFFF)],
                          ),
                          border: Border.all(color: const Color(0x2EFFFFFF)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
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
                ],
              );
            },
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
              AnimatedScale(
                duration: motion,
                curve: AppMotion.easeOut,
                scale: selected ? 1.0 : 0.94,
                child: AnimatedSwitcher(
                  duration: motion,
                  switchInCurve: AppMotion.easeOut,
                  child: Icon(
                    selected ? activeIcon : icon,
                    key: ValueKey(selected),
                    color: color,
                    size: 23,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: motion,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: color,
                  fontSize: 11,
                  height: 1.1,
                  letterSpacing: 0.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFE2E2E7)],
              ),
              border: Border.all(color: const Color(0x8CFFFFFF), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: Offset(0, 6),
                ),
                BoxShadow(
                  color: Color(0x4DFFFFFF),
                  blurRadius: 18,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: const Icon(
              Icons.near_me_rounded,
              color: AppColors.onAction,
              size: 27,
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
