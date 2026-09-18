import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../../app/theme/theme_x.dart';
import '../constants/india_locations.dart';

/// State / district typeahead matching [AppTextField] look.
class LocationTypeAheadField extends StatefulWidget {
  const LocationTypeAheadField({
    required this.controller,
    required this.label,
    required this.suggestionsFor,
    super.key,
    this.hint,
    this.validator,
    this.onChanged,
    this.onSelected,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSelected;

  /// Returns filtered suggestions for the current query.
  final Future<List<String>> Function(String query) suggestionsFor;

  @override
  State<LocationTypeAheadField> createState() => _LocationTypeAheadFieldState();
}

class _LocationTypeAheadFieldState extends State<LocationTypeAheadField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TypeAheadField<String>(
          controller: widget.controller,
          focusNode: _focusNode,
          debounceDuration: const Duration(milliseconds: 180),
          showOnFocus: true,
          hideOnUnfocus: true,
          hideOnSelect: true,
          suggestionsCallback: (pattern) async {
            await IndiaLocations.ensureLoaded();
            return widget.suggestionsFor(pattern);
          },
          builder: (context, controller, focusNode) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              textCapitalization: TextCapitalization.words,
              validator: widget.validator,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: widget.hint,
                suffixIcon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: context.muted,
                ),
                counterText: '',
              ),
            );
          },
          itemBuilder: (context, suggestion) {
            return ListTile(
              dense: true,
              title: Text(
                suggestion,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          },
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'No matches',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.muted,
                  ),
            ),
          ),
          decorationBuilder: (context, child) {
            return Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: scheme.surface,
              child: child,
            );
          },
          constraints: const BoxConstraints(maxHeight: 260),
          onSelected: (value) {
            widget.controller.text = value;
            widget.onChanged?.call(value);
            widget.onSelected?.call(value);
          },
        ),
      ],
    );
  }
}
