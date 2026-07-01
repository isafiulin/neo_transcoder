import 'package:flutter/material.dart';

class NeoSearchField extends StatelessWidget {
  const NeoSearchField({
    required this.onChanged,
    this.hintText = 'Search',
    super.key,
  });

  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, size: 18),
        ),
      ),
    );
  }
}
