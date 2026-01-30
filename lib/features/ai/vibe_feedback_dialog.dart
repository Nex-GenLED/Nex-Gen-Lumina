import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Available vibe options for feedback correction
enum VibeOption {
  moreCalm,
  moreEnergetic,
  moreElegant,
  morePlayful,
  moreRomantic,
  moreDramatic,
  moreSubtle,
  moreFestive,
  other,
}

extension VibeOptionDisplay on VibeOption {
  String get label {
    switch (this) {
      case VibeOption.moreCalm:
        return 'More calm';
      case VibeOption.moreEnergetic:
        return 'More energetic';
      case VibeOption.moreElegant:
        return 'More elegant';
      case VibeOption.morePlayful:
        return 'More playful';
      case VibeOption.moreRomantic:
        return 'More romantic';
      case VibeOption.moreDramatic:
        return 'More dramatic';
      case VibeOption.moreSubtle:
        return 'More subtle';
      case VibeOption.moreFestive:
        return 'More festive';
      case VibeOption.other:
        return 'Something else';
    }
  }

  IconData get icon {
    switch (this) {
      case VibeOption.moreCalm:
        return Icons.spa_outlined;
      case VibeOption.moreEnergetic:
        return Icons.bolt_outlined;
      case VibeOption.moreElegant:
        return Icons.diamond_outlined;
      case VibeOption.morePlayful:
        return Icons.celebration_outlined;
      case VibeOption.moreRomantic:
        return Icons.favorite_outline;
      case VibeOption.moreDramatic:
        return Icons.theater_comedy_outlined;
      case VibeOption.moreSubtle:
        return Icons.visibility_outlined;
      case VibeOption.moreFestive:
        return Icons.star_outline;
      case VibeOption.other:
        return Icons.edit_outlined;
    }
  }
}

/// Result from the vibe feedback dialog
class VibeFeedbackResult {
  final String feedbackType;
  final String? desiredVibe;
  final String? customFeedback;

  const VibeFeedbackResult({
    required this.feedbackType,
    this.desiredVibe,
    this.customFeedback,
  });
}

/// Shows an enhanced feedback dialog when user taps thumbs down.
/// Includes clarifying questions for "Wrong Vibe" to help Lumina learn.
Future<VibeFeedbackResult?> showEnhancedFeedbackDialog(BuildContext context) async {
  return showDialog<VibeFeedbackResult>(
    context: context,
    builder: (ctx) => const _EnhancedFeedbackDialog(),
  );
}

class _EnhancedFeedbackDialog extends StatefulWidget {
  const _EnhancedFeedbackDialog();

  @override
  State<_EnhancedFeedbackDialog> createState() => _EnhancedFeedbackDialogState();
}

class _EnhancedFeedbackDialogState extends State<_EnhancedFeedbackDialog> {
  String? _selectedType;
  VibeOption? _selectedVibe;
  final TextEditingController _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.feedback_outlined,
                        color: NexGenPalette.cyan,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Help Lumina improve',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  'What was wrong?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 12),

                // Main feedback options
                _FeedbackOption(
                  icon: Icons.palette_outlined,
                  label: 'Wrong Colors',
                  description: 'The colors didn\'t match what I wanted',
                  isSelected: _selectedType == 'Wrong Colors',
                  onTap: () {
                    Navigator.of(context).pop(const VibeFeedbackResult(
                      feedbackType: 'Wrong Colors',
                    ));
                  },
                ),
                const SizedBox(height: 8),

                _FeedbackOption(
                  icon: Icons.speed,
                  label: 'Too Fast',
                  description: 'The motion/animation was too quick',
                  isSelected: _selectedType == 'Too Fast',
                  onTap: () {
                    Navigator.of(context).pop(const VibeFeedbackResult(
                      feedbackType: 'Too Fast',
                    ));
                  },
                ),
                const SizedBox(height: 8),

                _FeedbackOption(
                  icon: Icons.slow_motion_video,
                  label: 'Too Slow',
                  description: 'The motion/animation was too slow',
                  isSelected: _selectedType == 'Too Slow',
                  onTap: () {
                    Navigator.of(context).pop(const VibeFeedbackResult(
                      feedbackType: 'Too Slow',
                    ));
                  },
                ),
                const SizedBox(height: 8),

                // Wrong Vibe - expandable
                _ExpandableFeedbackOption(
                  icon: Icons.mood_outlined,
                  label: 'Wrong Vibe',
                  description: 'The overall feel wasn\'t right',
                  isExpanded: _selectedType == 'Wrong Vibe',
                  onTap: () {
                    setState(() {
                      _selectedType = _selectedType == 'Wrong Vibe' ? null : 'Wrong Vibe';
                      _selectedVibe = null;
                    });
                  },
                  expandedContent: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        'What vibe were you hoping for?',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.cyan,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: VibeOption.values.map((vibe) {
                          if (vibe == VibeOption.other) return const SizedBox.shrink();
                          return _VibeChip(
                            vibe: vibe,
                            isSelected: _selectedVibe == vibe,
                            onTap: () {
                              Navigator.of(context).pop(VibeFeedbackResult(
                                feedbackType: 'Wrong Vibe',
                                desiredVibe: vibe.label,
                              ));
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      // Custom input
                      TextField(
                        controller: _customController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Or describe what you wanted...',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send, size: 18, color: NexGenPalette.cyan),
                            onPressed: () {
                              if (_customController.text.isNotEmpty) {
                                Navigator.of(context).pop(VibeFeedbackResult(
                                  feedbackType: 'Wrong Vibe',
                                  desiredVibe: 'custom',
                                  customFeedback: _customController.text,
                                ));
                              }
                            },
                          ),
                        ),
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            Navigator.of(context).pop(VibeFeedbackResult(
                              feedbackType: 'Wrong Vibe',
                              desiredVibe: 'custom',
                              customFeedback: value,
                            ));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                _FeedbackOption(
                  icon: Icons.lightbulb_outline,
                  label: 'Too Bright',
                  description: 'The brightness was too high',
                  isSelected: _selectedType == 'Too Bright',
                  onTap: () {
                    Navigator.of(context).pop(const VibeFeedbackResult(
                      feedbackType: 'Too Bright',
                    ));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _FeedbackOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? NexGenPalette.cyan.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? NexGenPalette.cyan : Colors.white70, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? NexGenPalette.cyan : Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandableFeedbackOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget expandedContent;

  const _ExpandableFeedbackOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isExpanded,
    required this.onTap,
    required this.expandedContent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isExpanded
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isExpanded ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.1),
            width: isExpanded ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(icon, color: isExpanded ? NexGenPalette.cyan : Colors.white70, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: isExpanded ? NexGenPalette.cyan : Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            description,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right,
                        color: isExpanded ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.4),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: expandedContent,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _VibeChip extends StatelessWidget {
  final VibeOption vibe;
  final bool isSelected;
  final VoidCallback onTap;

  const _VibeChip({
    required this.vibe,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? NexGenPalette.cyan.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? NexGenPalette.cyan
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                vibe.icon,
                size: 16,
                color: isSelected ? NexGenPalette.cyan : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                vibe.label,
                style: TextStyle(
                  color: isSelected ? NexGenPalette.cyan : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
