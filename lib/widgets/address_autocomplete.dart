import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/geocoding_service.dart';
import 'package:nexgen_command/theme.dart';

/// Autocomplete text field for address input with predictive suggestions.
class AddressAutocomplete extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final void Function(AddressSuggestion suggestion)? onAddressSelected;
  final void Function(String value)? onChanged;
  final String? labelText;
  final String? hintText;
  final int maxLines;

  const AddressAutocomplete({
    super.key,
    required this.controller,
    this.onAddressSelected,
    this.onChanged,
    this.labelText = 'Home Address',
    this.hintText,
    this.maxLines = 2,
  });

  @override
  ConsumerState<AddressAutocomplete> createState() => _AddressAutocompleteState();
}

class _AddressAutocompleteState extends ConsumerState<AddressAutocomplete> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  List<AddressSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _isLoading = false;
  bool _userSelectedAddress = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _debounce?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    // If user just selected an address, don't search again
    if (_userSelectedAddress) {
      _userSelectedAddress = false;
      return;
    }

    widget.onChanged?.call(widget.controller.text);

    _debounce?.cancel();
    final query = widget.controller.text.trim();

    if (query.length < 3) {
      _suggestions = [];
      _removeOverlay();
      return;
    }

    // Debounce to avoid spamming the API
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      await _searchAddresses(query);
    });
  }

  Future<void> _searchAddresses(String query) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final geocoder = ref.read(geocodingServiceProvider);
      final results = await geocoder.searchAddresses(query, limit: 5);

      if (!mounted) return;

      _suggestions = results;
      if (_suggestions.isNotEmpty && _focusNode.hasFocus) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    } catch (e) {
      debugPrint('AddressAutocomplete: search error $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Delay removal to allow tap on suggestions
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) {
          _removeOverlay();
        }
      });
    } else if (_suggestions.isNotEmpty) {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: NexGenPalette.gunmetal90,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return _AddressSuggestionTile(
                    suggestion: suggestion,
                    onTap: () {
                      _userSelectedAddress = true;
                      widget.controller.text = suggestion.shortAddress;
                      widget.controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: suggestion.shortAddress.length),
                      );
                      widget.onAddressSelected?.call(suggestion);
                      _removeOverlay();
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.streetAddress,
        maxLines: widget.maxLines,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.home_outlined),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        widget.controller.clear();
                        _suggestions = [];
                        _removeOverlay();
                      },
                    )
                  : null,
        ),
        onSubmitted: (value) {
          // If there's exactly one suggestion, select it
          if (_suggestions.length == 1) {
            _userSelectedAddress = true;
            widget.controller.text = _suggestions.first.shortAddress;
            widget.onAddressSelected?.call(_suggestions.first);
          }
          _removeOverlay();
        },
      ),
    );
  }
}

/// Individual suggestion tile in the dropdown
class _AddressSuggestionTile extends StatelessWidget {
  final AddressSuggestion suggestion;
  final VoidCallback onTap;

  const _AddressSuggestionTile({required this.suggestion, required this.onTap});

  IconData _iconForType(String? type) {
    switch (type) {
      case 'house':
      case 'residential':
        return Icons.home_rounded;
      case 'street':
      case 'road':
        return Icons.add_road;
      case 'city':
      case 'town':
      case 'village':
        return Icons.location_city;
      case 'state':
      case 'county':
        return Icons.map_outlined;
      default:
        return Icons.place_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _iconForType(suggestion.type),
              color: NexGenPalette.cyan,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.shortAddress,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (suggestion.displayName != suggestion.shortAddress) ...[
                    const SizedBox(height: 2),
                    Text(
                      suggestion.displayName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
