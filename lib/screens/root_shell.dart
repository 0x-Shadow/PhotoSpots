import 'dart:math' as math;

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
  static const double actionSize = 52;

  /// Destinations and the Add slot, in bar order.
  static const int slotCount = 5;
  static const int addSlot = 2;

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> with TickerProviderStateMixin {
  late final AnimationController _springController;
  late Animation<double> _slotAnimation;

  /// The bar settles into place instead of popping in with the page.
  late final AnimationController _entranceController;
  late final Animation<double> _entrance;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController.unbounded(vsync: this);
    _slotAnimation = AlwaysStoppedAnimation(widget.selectedSlot.toDouble());
    _springController.value = widget.selectedSlot.toDouble();

    _entranceController = AnimationController(
      vsync: this,
      duration: AppMotion.layout,
    );
    _entrance = CurvedAnimation(
      parent: _entranceController,
      curve: AppMotion.easeOut,
    );
    _entranceController.forward();
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
        const SpringDescription(mass: 1.0, stiffness: 280.0, damping: 23.0),
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
    _entranceController.dispose();
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: AnimatedBuilder(
        animation: _entrance,
        builder: (context, child) {
          final t = reduceMotion ? 1.0 : _entrance.value;
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 16),
              child: child,
            ),
          );
        },
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
                    // passing behind the Add disc at the centre. It stretches
                    // along its travel axis with the spring's velocity and
                    // settles back, the way liquid drags before it stops.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _slotAnimation,
                          builder: (context, _) {
                            final value = _slotAnimation.value
                                .clamp(0.0, (_NavBar.slotCount - 1).toDouble())
                                .toDouble();
                            final stretch = reduceMotion
                                ? 0.0
                                : math.min(
                                    _springController.velocity.abs() * 0.9,
                                    9.0,
                                  );
                            return Stack(
                              children: [
                                Positioned(
                                  left: value * slotWidth + 5 - stretch / 2,
                                  top: 7,
                                  bottom: 7,
                                  width: slotWidth - 10 + stretch,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(29),
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0x40328AFF),
                                          Color(0x14328AFF),
                                        ],
                                      ),
                                      border: Border.fromBorderSide(
                                        BorderSide(color: Color(0x33328AFF)),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x38328AFF),
                                          blurRadius: 18,
                                          spreadRadius: -4,
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
                : const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              // The icon arrives with a small overshoot and a lift, so the
              // selection lands with weight instead of fading blue.
              final pop = reduceMotion ? 1.0 : Curves.easeOutBack.transform(t);
              final color = Color.lerp(
                AppColors.textSecondary,
                AppColors.accent,
                t,
              )!;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: Offset(0, -1.5 * t),
                    child: Transform.scale(
                      scale: 1 + 0.13 * pop,
                      child: Icon(
                        selected ? activeIcon : icon,
                        color: color,
                        size: 21,
                      ),
                    ),
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
                        fontWeight: FontWeight.w600,
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

/// The prominent action: the app's white action treatment on a turning disc.
/// It sits in the centre slot on the same glass as the destinations, and the
/// wide rail reuses it as its leading action.
class _AddAction extends StatefulWidget {
  const _AddAction({required this.onTap, this.size = _NavBar.actionSize});

  final VoidCallback onTap;
  final double size;

  @override
  State<_AddAction> createState() => _AddActionState();
}

class _AddActionState extends State<_AddAction>
    with SingleTickerProviderStateMixin {
  /// A single accent ripple that leaves the disc on tap — the bar's loudest
  /// moment, kept to one ripple so nothing loops on screen.
  late final AnimationController _ripple;

  @override
  void initState() {
    super.initState();
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!MediaQuery.disableAnimationsOf(context)) {
      _ripple.forward(from: 0);
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) {
                if (_ripple.value == 0) return const SizedBox.shrink();
                final t = Curves.easeOutCubic.transform(_ripple.value);
                return Transform.scale(
                  scale: 1 + 0.35 * t,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.4 * (1 - t)),
                    ),
                  ),
                );
              },
            ),
          ),
          PressButton(
            semanticLabel: 'Add a spot',
            onTap: _handleTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Lit from above: the same light the capsule's rim catches.
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0xFFDFE2E8)],
                ),
                border: Border.all(color: const Color(0x1F000000)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x73000000),
                    blurRadius: 14,
                    spreadRadius: -3,
                    offset: Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Color(0x2E328AFF),
                    blurRadius: 20,
                    spreadRadius: -2,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Gloss across the top half keeps the disc from reading flat.
                  Positioned(
                    top: 1,
                    left: 1,
                    right: 1,
                    height: size * 0.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(size / 2),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFFFFFFFF).withValues(alpha: 0.9),
                            const Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.add_rounded,
                      color: AppColors.onAction,
                      size: size * 0.48,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
      selectedIconTheme: const IconThemeData(color: AppColors.accent, size: 24),
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
