import 'package:flutter/material.dart';

class NeoTableScroll extends StatefulWidget {
  const NeoTableScroll({required this.child, super.key});

  final Widget child;

  @override
  State<NeoTableScroll> createState() => _NeoTableScrollState();
}

class _NeoTableScrollState extends State<NeoTableScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 8,
      scrollbarOrientation: ScrollbarOrientation.top,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 12),
        child: widget.child,
      ),
    );
  }
}
