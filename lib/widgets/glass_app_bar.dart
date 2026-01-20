import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// A premium, frosted-glass AppBar with backdrop blur and subtle border.
/// Drop-in replacement for AppBar.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.leading, this.actions, this.centerTitle, this.bottom});

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool? centerTitle;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Frosted glass backdrop
      ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(height: preferredSize.height + MediaQuery.of(context).padding.top, color: NexGenPalette.gunmetal90.withValues(alpha: 0.6)),
        ),
      ),
      // Border and AppBar contents
      Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NexGenPalette.line, width: 1))),
        child: AppBar(
          title: title,
          leading: leading,
          actions: actions,
          centerTitle: centerTitle,
          bottom: bottom,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
    ]);
  }
}
