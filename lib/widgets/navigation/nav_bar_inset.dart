// lib/widgets/navigation/nav_bar_inset.dart
//
// The ONE place the persistent bottom nav dock's footprint is reserved for
// the content it floats over.
//
// MainScaffold draws the dock as the top child of a Stack, over a
// `Positioned.fill` branch host, with `extendBody: true` so content scrolls
// under the translucent glass. Because the dock is not a Scaffold
// `bottomNavigationBar`, nothing told the content how tall it is: every
// screen had to reserve the height itself with `navBarTotalHeight(context)`,
// and every screen (and bottom sheet) that forgot lost its last rows under
// the dock. That regressed repeatedly.
//
// [NavBarInsetShell] does what Scaffold does for an `extendBody` bottom bar:
// it injects the dock's height into `MediaQuery.padding.bottom` (and
// `viewPadding.bottom`) for everything beneath the dock. From there the
// framework's own conventions take over — a ListView with no explicit
// padding, a SafeArea, a Scaffold placing its FloatingActionButton, a bottom
// sheet reading `padding.bottom` — all clear the dock without knowing it
// exists. `navBarTotalHeight(context)` (app_colors.dart) now simply reads
// that inset back, so the explicit-padding call sites stay correct and the
// same widget rendered on the root navigator (no dock) gets the plain safe
// area instead of a phantom 100 px.
//
// The dock is measured after layout rather than assumed: the glass dock is
// `kNavBarContentHeight` tall at default text scale, but the simple-mode bar
// is a few px taller and both grow with text scale. Until the first
// measurement lands (one frame) the constant is used, so the first frame is
// never under-padded.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../app_colors.dart';

/// Lays out [body] under [navBar] and reserves the nav bar's height in the
/// body's [MediaQuery] bottom insets.
class NavBarInsetShell extends StatefulWidget {
  /// The content that scrolls under the dock (the branch host).
  final Widget body;

  /// The dock itself. Rendered at the bottom edge, above [body].
  final Widget navBar;

  const NavBarInsetShell({
    super.key,
    required this.body,
    required this.navBar,
  });

  @override
  State<NavBarInsetShell> createState() => _NavBarInsetShellState();
}

class _NavBarInsetShellState extends State<NavBarInsetShell> {
  /// The dock's rendered height, including the bottom safe-area it pads
  /// itself by. Null until the first layout has been measured.
  double? _measuredNavBarHeight;

  void _onNavBarHeight(double height) {
    if (!mounted || _measuredNavBarHeight == height) return;
    setState(() => _measuredNavBarHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // The dock's own content height: what it adds ABOVE the safe area.
    final measured = _measuredNavBarHeight;
    final dockContent = measured == null
        ? kNavBarContentHeight
        : (measured - mq.padding.bottom).clamp(0.0, double.infinity);

    return Stack(
      children: [
        Positioned.fill(
          child: NavBarInset(
            dockContentHeight: dockContent,
            child: widget.body,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _MeasureHeight(
            onHeight: _onNavBarHeight,
            child: widget.navBar,
          ),
        ),
      ],
    );
  }
}

/// Adds [dockContentHeight] to the bottom [MediaQuery] insets of [child].
///
/// Split out from [NavBarInsetShell] so a test (or any surface that mounts
/// a screen without the real dock) can reproduce exactly what the shell
/// injects, with a constant height and no measurement round-trip.
class NavBarInset extends StatelessWidget {
  final double dockContentHeight;
  final Widget child;

  const NavBarInset({
    super.key,
    this.dockContentHeight = kNavBarContentHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(
          bottom: mq.padding.bottom + dockContentHeight,
        ),
        viewPadding: mq.viewPadding.copyWith(
          bottom: mq.viewPadding.bottom + dockContentHeight,
        ),
      ),
      child: child,
    );
  }
}

/// Reports its child's laid-out height (after the frame) whenever it changes.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;

  const _MeasureHeight({required this.onHeight, required Widget child})
      : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
      BuildContext context, _RenderMeasureHeight renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _lastReported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _lastReported) return;
    _lastReported = height;
    // Never call back during layout; the listener calls setState.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}
