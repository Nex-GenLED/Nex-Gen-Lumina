import 'package:flutter/material.dart';
import 'package:nexgen_command/app_colors.dart';

/// Collapsible "Why does this matter?" card — the first in-app educational
/// surface in the installer feature. Renders a title row with a chevron;
/// tapping toggles a body slot below. Carbon background, Frost text,
/// Lumina accent on the chevron.
///
/// The body is supplied as a list of [InfoExpansionParagraph] entries to
/// keep the prose structured: each paragraph has an optional heading and
/// a body string. Bullets render with a Lumina-tinted dot.
class InfoExpansionCard extends StatefulWidget {
  const InfoExpansionCard({
    super.key,
    required this.title,
    required this.paragraphs,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<InfoExpansionParagraph> paragraphs;
  final bool initiallyExpanded;

  @override
  State<InfoExpansionCard> createState() => _InfoExpansionCardState();
}

class _InfoExpansionCardState extends State<InfoExpansionCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal, // CARBON
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: NexGenPalette.cyan,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: NexGenPalette.textHigh, // FROST
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.expand_more,
                      color: NexGenPalette.cyan,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _expanded
                ? Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final p in widget.paragraphs) ...[
                          if (p.heading != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              p.heading!,
                              style: const TextStyle(
                                color: NexGenPalette.textHigh,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ] else
                            const SizedBox(height: 8),
                          Text(
                            p.body,
                            style: const TextStyle(
                              color: NexGenPalette.textHigh,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// One paragraph inside an [InfoExpansionCard]. Heading is optional —
/// when set, it renders as a bold-weight label above the body text.
class InfoExpansionParagraph {
  const InfoExpansionParagraph({this.heading, required this.body});

  final String? heading;
  final String body;
}
