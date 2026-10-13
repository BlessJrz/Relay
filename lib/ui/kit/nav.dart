import 'package:flutter/widgets.dart';

import 'controls.dart';
import 'icons.dart';
import 'scope.dart';

class NavItem {
  final String icon;
  final String label;
  final int badge;
  const NavItem(this.icon, this.label, {this.badge = 0});
}

/// Floating bar for the folded (cover) screen.
class SkNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const SkNavBar({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final hud = skin.upperHeadings;
    return skin.surface(
      p,
      radius: hud ? 6 : 999,
      padding: const EdgeInsets.all(6),
      reduceEffects: context.settings.reduceMotion,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: Pressable(
              onTap: () => onTap(i),
              builder: (_) => skin.selectedFace(
                p,
                selected: i == index,
                radius: hud ? 2 : 999,
                child: SizedBox(
                  width: 76,
                  height: 58,
                  child: _ItemBody(item: items[i], selected: i == index),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Side rail for the unfolded (inner) screen.
class SkNavRail extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const SkNavRail({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final hud = skin.upperHeadings;
    return skin.surface(
      p,
      radius: hud ? 6 : 30,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 9),
      reduceEffects: context.settings.reduceMotion,
      child: Column(children: [
        skin.accentTile(p, size: 46, child: Ic('bolt', size: 22, color: p.onAccent)),
        const SizedBox(height: 18),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Pressable(
              onTap: () => onTap(i),
              builder: (_) => skin.selectedFace(
                p,
                selected: i == index,
                radius: hud ? 2 : 18,
                child: SizedBox(width: 68, height: 64, child: _ItemBody(item: items[i], selected: i == index)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ItemBody extends StatelessWidget {
  final NavItem item;
  final bool selected;
  const _ItemBody({required this.item, required this.selected});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final color = selected ? (skin.id.name == 'glass' ? p.text : p.accent) : p.text2;
    return Stack(clipBehavior: Clip.none, children: [
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedScale(
            scale: selected ? 1.08 : 1,
            duration: context.sc.d(skin.moveDuration),
            curve: Curves.easeOutBack,
            child: Ic(item.icon, size: 22, color: color, stroke: selected ? skin.iconStroke + .3 : skin.iconStroke),
          ),
          const SizedBox(height: 4),
          Text(
            skin.upperHeadings ? item.label.toUpperCase() : item.label,
            style: (skin.upperHeadings ? skin.caption(p).copyWith(fontSize: 9.5) : skin.caption(p)).copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
          ),
        ]),
      ),
      if (item.badge > 0) Positioned(top: 4, right: 10, child: CountBadge(item.badge)),
    ]);
  }
}
