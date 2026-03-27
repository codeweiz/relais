import 'package:flutter/material.dart';

class SpecialKeyBar extends StatelessWidget {
  final void Function(String) onKey;

  const SpecialKeyBar({super.key, required this.onKey});

  @override
  Widget build(BuildContext context) {
    final keys = [
      ('Esc', '\x1b'),
      ('Tab', '\t'),
      ('Ctrl', ''), // modifier, handled specially
      ('\u2191', '\x1b[A'),
      ('\u2193', '\x1b[B'),
      ('\u2190', '\x1b[D'),
      ('\u2192', '\x1b[C'),
    ];

    return Container(
      height: 44,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: keys
            .map((k) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FilterChip(
                    label: Text(k.$1, style: const TextStyle(fontSize: 12)),
                    onSelected: (_) {
                      if (k.$2.isNotEmpty) onKey(k.$2);
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ))
            .toList(),
      ),
    );
  }
}
