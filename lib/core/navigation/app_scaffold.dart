import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:flutter/material.dart';

/// Puts the navigation beside the content instead of over it, when the
/// window is wide enough to hold both.
///
/// A till sits at a fixed desk and gets used all day: a menu that slides
/// over the work costs a gesture every time and hides what you were looking
/// at. Below [persistentFrom] there isn't room, so screens fall back to the
/// hamburger and an overlay — the same drawer, opened differently.
///
/// Screens wrap their body in this and hide their own `drawer:` above the
/// same breakpoint, so exactly one navigation is ever present.
class NavRail extends StatelessWidget {
  const NavRail({required this.destination, required this.child, super.key});

  final String destination;
  final Widget child;

  static const persistentFrom = 1100.0;

  static bool isPersistent(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= persistentFrom;

  @override
  Widget build(BuildContext context) {
    if (!isPersistent(context)) return child;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 248,
          child: AppDrawer(current: destination, persistent: true),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: child),
      ],
    );
  }
}
