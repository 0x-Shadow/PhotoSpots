import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/glass.dart';
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

class _RootShellState extends State<RootShell> with TickerProviderStateMixin {
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
    _tabScale = Tween<double>(begin: 0.985, end: 1.0).animate(_tabFade);
    RootShell._tabOpener = _selectSlot;
  }

  void _openSubmit() {
    Navigator.of(context).push(AppMotion.slideUpModal(const SubmitScreen()));
  }

  /// Handles a bar slot: Add opens the flow, the other slots switch tabs and
  /// replay a short fade + lift.
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
    _tabController.forward(from: 0.4);
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
          // Let the content continue behind the floating pill so the frosted
          // material samples the actual page instead of an opaque gutter.
          extendBody: true,
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

/// A destination on the floating bar. [slot] is the shell's slot id, which
/// skips 2 because that slot belongs to the Add action.
class _Destination {
  const _Destination({
    required this.slot,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final int slot;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// A floating liquid-glass navigation bar.
///
/// Everything lives on one piece of glass: Home, Map, the prominent Add in the
/// centre, then Saved and Profile. The Add is a solid blue disc seated inside
/// the capsule instead of a badge floating over a gap, so the bar is one
/// uninterrupted surface and the middle action still carries the most weight.
class _NavBar extends StatefulWidget {
  const _NavBar({required this.selectedSlot, required this.onSlotSelected});

  final int selectedSlot;
  final ValueChanged<int> onSlotSelected;

  static const _destinations = <_Destination>[
    _Destination(
      slot: 0,
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _Destination(
      slot: 1,
      icon: Icons.map_outlined,
      activeIcon: Icons.map_rounded,
      label: 'Map',
    ),
    _Destination(
      slot: 3,
      icon: Icons.bookmark_outline_rounded,
      activeIcon: Icons.bookmark_rounded,
      label: 'Saved',
    ),
    _Destination(
      slot: 4,
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  static const double barHeight = 72;

  /// The Add disc inside the capsule. Small enough to leave the glass visible
  /// around it, large enough to read as the bar's primary action.
  static const double actionSize = 50;

  /// Destinations and the Add slot, in bar order.
  static const int slotCount = 5;
  static const int addSlot = 2;

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> with SingleTickerProviderStateMixin {
  late final AnimationController _springController;
  late Animation<double> _slotAnimation;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController.unbounded(vsync: this);
    _slotAnimation = AlwaysStoppedAnimation(
      widget.selectedSlot.toDouble(),
    );
    _springController.value = widget.selectedSlot.toDouble();
  }

  void _animateToSlot(int slot) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _springController.value = slot.toDouble();
      return;
    }
    _slotAnimation = Tween<double>(
      begin: _slotAnimation.value,
      end: slot.toDouble(),
    ).animate(_springController);
    _springController.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 260.0, damping: 26.0),
        _springController.value,
        slot.toDouble(),
        0,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _NavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSlot != widget.selectedSlot) {
      _animateToSlot(widget.selectedSlot);
    }
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _handleSlot(int slot) {
    // The Add slot opens the submit flow; the lens should stay where it is.
    if (slot != _NavBar.addSlot) _animateToSlot(slot);
    widget.onSlotSelected(slot);
  }

  @override
  Widget build(BuildContext context) {
    final selectedSlot = widget.selectedSlot;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SizedBox(
        height: _NavBar.barHeight,
        child: GlassPanel(
          borderRadius: _NavBar.barHeight / 2,
          blur: 32,
          shadows: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 30,
              spreadRadius: -6,
              offset: Offset(0, 14),
            ),
          ],
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth = constraints.maxWidth / _NavBar.slotCount;

              return Stack(
                children: [
                  // Specular highlight: the top edge catches light like real
                  // glass, brightest through the middle.
                  Positioned(
                    top: 0,
                    left: 24,
                    right: 24,
                    child: Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0x59FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // The active lens glides between destinations on a spring,
                  // passing behind the Add disc at the centre.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _slotAnimation,
                        builder: (context, _) {
                          final value = _slotAnimation.value
                              .clamp(0.0, (_NavBar.slotCount - 1).toDouble())
                              .toDouble();
                          return Stack(
                            children: [
                              Positioned(
                                left: value * slotWidth + 5,
                                top: 7,
                                bottom: 7,
                                width: slotWidth - 10,
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSoft,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(29),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x33328AFF),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var slot = 0; slot < _NavBar.slotCount; slot++)
                        Expanded(
                          child: slot == _NavBar.addSlot
                              ? Center(
                                  child: _AddAction(
                                    size: _NavBar.actionSize,
                                    onTap: () => _handleSlot(slot),
                                  ),
                                )
                              : _NavItem(
                                  icon: _destinationForSlot(slot).icon,
                                  activeIcon: _destinationForSlot(slot)
                                      .activeIcon,
                                  label: _destinationForSlot(slot).label,
                                  selected: selectedSlot == slot,
                                  onTap: () => _handleSlot(slot),
                                ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  _Destination _destinationForSlot(int slot) => _NavBar._destinations
      .firstWhere((destination) => destination.slot == slot);
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = selected ? AppColors.accent : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PressButton(
        onTap: onTap,
        child: SizedBox(
          height: _NavBar.barHeight,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? activeIcon : icon,
                    color: color,
                    size: 21 + 2 * t,
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: color,
                        fontSize: 10,
                        height: 1.1,
                        letterSpacing: 0.1,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
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

/// The prominent action: one blue glass disc. In the bar it sits in the centre
/// slot on the same glass as the destinations; the wide rail reuses it as its
/// leading action.
class _AddAction extends StatelessWidget {
  const _AddAction({required this.onTap, this.size = _NavBar.actionSize});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PressButton(
      semanticLabel: 'Add a spot',
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4A9BFF), Color(0xFF2A78E8)],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x66328AFF),
              blurRadius: 20,
              spreadRadius: -2,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Rim light so the circle sits on the same glass language as the
            // capsule beside it.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
              ),
            ),
            Center(
              child: Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: size * 0.5,
              ),
            ),
          ],
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
      indicatorColor: AppColors.accentSoft,
      selectedIconTheme: const IconThemeData(
        color: AppColors.accent,
        size: 24,
      ),
      unselectedIconTheme: const IconThemeData(
        color: AppColors.textFaint,
        size: 23,
      ),
      selectedLabelTextStyle: labelStyle.copyWith(
        color: AppColors.accent,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: labelStyle.copyWith(color: AppColors.textFaint),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: _AddAction(size: 56, onTap: onAdd),
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
