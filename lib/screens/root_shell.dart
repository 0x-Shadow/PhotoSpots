import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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
  late final AnimationController _warmPulseController;
  late final Animation<double> _warmPulse;

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
    _warmPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _warmPulse = CurvedAnimation(
      parent: _warmPulseController,
      curve: Curves.easeOutCubic,
    );
    RootShell._tabOpener = _selectSlot;
  }

  void _openSubmit() {
    Navigator.of(context).push(AppMotion.slideUpModal(const SubmitScreen()));
  }

  /// Handles a bar slot: Add opens the flow, the other slots switch tabs and
  /// replay a short fade + lift plus a warm ambient light bloom.
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
    if (!MediaQuery.disableAnimationsOf(context)) {
      _warmPulseController.forward(from: 0);
    }
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
    _warmPulseController.dispose();
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
          // Let the content continue behind the pill so the frosted material
          // samples the actual page instead of an opaque scaffold gutter.
          extendBody: true,
          body: Stack(
            children: [
              _animatedScreen(),
              if (!MediaQuery.disableAnimationsOf(context))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 180,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _WarmPageGlowPainter(progress: _warmPulse),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _NavBar(
            selectedSlot: _slotForScreenIndex(_index),
            onSlotSelected: _selectSlot,
          ),
        );
      },
    );
  }
}

/// Soft cool ambient bloom that rises from the floating glass when switching pages.
class _WarmPageGlowPainter extends CustomPainter {
  const _WarmPageGlowPainter({required this.progress});

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final intensity = math.sin(t * math.pi);
    final center = Offset(size.width / 2, size.height + 20);
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        size.width * 0.65,
        [
          const Color(0xFF57B6FF).withValues(alpha: 0.14 * intensity),
          const Color(0xFF2D6CFF).withValues(alpha: 0.05 * intensity),
          const Color(0xFF2D6CFF).withValues(alpha: 0.0),
        ],
        [0.0, 0.45, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _WarmPageGlowPainter oldDelegate) => true;
}

/// Floating rounded, genuinely blurred glass navigation bar.
class _NavBar extends StatefulWidget {
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

  /// Pill height floating above the bottom safe area.
  static const double barHeight = 66;

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> with SingleTickerProviderStateMixin {
  late final AnimationController _springController;
  late Animation<double> _slotAnimation;
  int _tappedSlot = 0;

  @override
  void initState() {
    super.initState();
    _tappedSlot = widget.selectedSlot;
    _springController = AnimationController.unbounded(vsync: this);
    _slotAnimation = Tween<double>(
      begin: widget.selectedSlot.toDouble(),
      end: widget.selectedSlot.toDouble(),
    ).animate(_springController);
    _springController.value = widget.selectedSlot.toDouble();
  }

  void _animateToSlot(int slot) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _springController.value = slot.toDouble();
      return;
    }
    final from = _slotAnimation.value;
    final to = slot.toDouble();
    _tappedSlot = slot;
    _slotAnimation = Tween<double>(
      begin: from,
      end: to,
    ).animate(_springController);
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 210.0, damping: 17.0),
      _springController.value,
      to,
      0,
    );
    _springController.animateWith(simulation);
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
    _animateToSlot(slot);
    widget.onSlotSelected(slot);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: SizedBox(
        height: _NavBar.barHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_NavBar.barHeight / 2),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _GlassBarPainter(
                        slotAnimation: _slotAnimation,
                        springValue: _springController,
                        tappedSlot: _tappedSlot,
                        slotCount: _NavBar._items.length,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < _NavBar._items.length; i++)
                  Expanded(
                    child: _NavBar._items[i] == null
                        ? _AddAction(onTap: () => _handleSlot(2))
                        : _NavItem(
                            icon: _NavBar._items[i]!.icon,
                            activeIcon: _NavBar._items[i]!.active,
                            label: _NavBar._items[i]!.label,
                            selected: widget.selectedSlot == i,
                            onTap: () => _handleSlot(i),
                          ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassBarPainter extends CustomPainter {
  _GlassBarPainter({
    required this.slotAnimation,
    required this.springValue,
    required this.tappedSlot,
    required this.slotCount,
  }) : super(repaint: slotAnimation);

  final Animation<double> slotAnimation;
  final AnimationController springValue;
  final int tappedSlot;
  final int slotCount;

  static const _liquidTop = Color(0xFFA9E4FF);
  static const _liquidMid = Color(0xFF57B6FF);
  static const _liquidDeep = Color(0xFF2D6CFF);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final slotWidth = width / slotCount;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(31));

    // 1. Floating shadow gives the material a clear edge above the content.
    final shadowPaint = Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.save();
    canvas.translate(0, 7);
    canvas.drawRRect(rrect, shadowPaint);
    canvas.restore();

    // 2. A translucent layer over a real BackdropFilter creates the frosted
    // glass instead of imitating blur with a solid painted background.
    final glassPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, height), const [
        Color(0xB81E2330),
        Color(0xA0101119),
      ]);
    canvas.drawRRect(rrect, glassPaint);

    // Subtle top sheen
    final sheenPaint = Paint()
      ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, height * 0.65), [
        Colors.white.withValues(alpha: 0.07),
        Colors.white.withValues(alpha: 0.0),
      ]);
    canvas.drawRRect(rrect, sheenPaint);

    // 3. Cool liquid light follows the selected destination.
    final activeX = (slotAnimation.value + 0.5) * slotWidth;
    final centerY = height / 2;
    final pulseT = springValue.value.clamp(0.0, 1.0);
    final pulseBoost = (1.0 - pulseT) * 0.22;

    canvas.save();
    canvas.clipRRect(rrect);
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(activeX, centerY + 2),
        slotWidth * 0.78,
        [
          _liquidTop.withValues(alpha: 0.28 + pulseBoost),
          _liquidMid.withValues(alpha: 0.12 + pulseBoost * 0.5),
          _liquidDeep.withValues(alpha: 0.0),
        ],
        [0.0, 0.45, 1.0],
      );

    // The add control stays quietly discoverable without competing with the
    // selected-tab indicator.
    final addCenterX = 2.5 * slotWidth;
    final addGlowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(addCenterX, centerY),
        slotWidth * 0.65,
        [
          _liquidMid.withValues(alpha: 0.16),
          _liquidDeep.withValues(alpha: 0.0),
        ],
        [0.0, 1.0],
      );

    canvas.drawCircle(
      Offset(activeX, centerY + 2),
      slotWidth * 0.78,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(addCenterX, centerY),
      slotWidth * 0.65,
      addGlowPaint,
    );

    // Expanding liquid tap ripple.
    if (pulseT > 0 && pulseT < 1) {
      final tappedX = (tappedSlot + 0.5) * slotWidth;
      final rippleRadius = 8.0 + pulseT * (slotWidth * 0.65);
      final ripplePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = _liquidTop.withValues(alpha: (1.0 - pulseT) * 0.2);
      canvas.drawCircle(Offset(tappedX, centerY), rippleRadius, ripplePaint);
    }
    canvas.restore();

    // 4. Active tab capsule with a softly refracted rim.
    final capsuleLeft = slotAnimation.value * slotWidth + 5.0;
    final capsuleRect = Rect.fromLTWH(
      capsuleLeft,
      5.0,
      slotWidth - 10.0,
      height - 10.0,
    );
    final capsuleRRect = RRect.fromRectAndRadius(
      capsuleRect,
      const Radius.circular(26),
    );

    final capsuleFill = Paint()..color = _liquidTop.withValues(alpha: 0.10);
    canvas.drawRRect(capsuleRRect, capsuleFill);

    final rimGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = _liquidMid.withValues(alpha: 0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(capsuleRRect, rimGlowPaint);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..shader = ui.Gradient.linear(
        Offset(capsuleLeft, 0),
        Offset(capsuleLeft + capsuleRect.width, 0),
        [
          _liquidTop.withValues(alpha: 0.05),
          _liquidTop.withValues(alpha: 0.78),
          _liquidMid.withValues(alpha: 0.9),
          _liquidTop.withValues(alpha: 0.05),
        ],
        [0.0, 0.28, 0.72, 1.0],
      );
    canvas.drawRRect(capsuleRRect, rimPaint);

    // 5. Outer glass border (bright specular highlight at top fading down)
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, height),
        [
          Colors.white.withValues(alpha: 0.48),
          Colors.white.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.07),
        ],
        [0.0, 0.5, 1.0],
      );
    canvas.drawRRect(rrect.deflate(0.6), borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GlassBarPainter oldDelegate) {
    return oldDelegate.tappedSlot != tappedSlot ||
        oldDelegate.slotAnimation != slotAnimation ||
        oldDelegate.springValue != springValue;
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = selected ? const Color(0xFFA9E4FF) : AppColors.textSecondary;
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
            curve: Curves.easeOutBack,
            builder: (context, t, _) {
              final scale = 1.0 + 0.12 * math.sin(t * math.pi);
              return Transform.scale(
                scale: reduceMotion ? 1.0 : scale,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? activeIcon : icon,
                      color: color,
                      size: 21.5,
                      shadows: selected && !reduceMotion
                          ? [
                              Shadow(
                                color: const Color(0xFF57B6FF)
                                    .withValues(alpha: 0.65 * t),
                                blurRadius: 9,
                              ),
                            ]
                          : null,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: color,
                        fontSize: 10,
                        height: 1.1,
                        letterSpacing: 0.1,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The always-available middle slot with a refracted liquid-glass orb.
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFA9E4FF), Color(0xFF57B6FF)],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x6657B6FF),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Color(0xFF07111E),
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
      unselectedLabelTextStyle: labelStyle.copyWith(color: AppColors.textFaint),
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
