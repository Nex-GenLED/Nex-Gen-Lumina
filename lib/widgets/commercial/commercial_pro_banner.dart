import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_theme.dart';

/// Dismissible pro-tier banner for commercial screens.
///
/// [bannerKey] controls persistence — each placement uses a unique key so
/// dismiss state is tracked independently.
///
/// [maxShows] limits how many times the banner appears before auto-hiding.
/// Set to `0` for unlimited (only manual dismiss hides it).
class CommercialProBanner extends StatefulWidget {
  final String bannerKey;
  final int maxShows;

  const CommercialProBanner({
    super.key,
    required this.bannerKey,
    this.maxShows = 0,
  });

  @override
  State<CommercialProBanner> createState() => _CommercialProBannerState();
}

class _CommercialProBannerState extends State<CommercialProBanner> {
  bool _visible = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _checkVisibility();
  }

  Future<void> _checkVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissKey = 'pro_banner_dismissed_${widget.bannerKey}';
    final countKey = 'pro_banner_count_${widget.bannerKey}';

    final dismissed = prefs.getBool(dismissKey) ?? false;
    if (dismissed) {
      if (mounted) setState(() => _loaded = true);
      return;
    }

    // Track show count
    final count = (prefs.getInt(countKey) ?? 0) + 1;
    await prefs.setInt(countKey, count);

    // Check max shows limit
    if (widget.maxShows > 0 && count > widget.maxShows) {
      await prefs.setBool(dismissKey, true);
      if (mounted) setState(() => _loaded = true);
      return;
    }

    if (mounted) setState(() { _visible = true; _loaded = true; });
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pro_banner_dismissed_${widget.bannerKey}', true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_visible) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: const Border(
          left: BorderSide(color: NexGenPalette.cyan, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Multi-location management and advanced commercial '
                    'features are currently included.',
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'A Lumina Commercial subscription is coming \u2014 '
                    'set up now to be grandfathered.',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _dismiss,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    size: 16, color: NexGenPalette.textMedium),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
