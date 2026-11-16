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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Scrollbar(
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
          child: ConstrainedBox(
            // Stretch the table to fill the panel when there is spare width;
            // horizontal scrolling still applies when it does not fit.
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
