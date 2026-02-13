import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/theme.dart';

/// Widget for displaying clarification questions one at a time.
///
/// Presents each question with:
/// - Clear question text
/// - Visual options with previews
/// - Progress indicator
/// - Manual control escape hatch
class ClarificationDialogWidget extends ConsumerWidget {
  final VoidCallback onComplete;
  final void Function(String aspect)? onManualRequested;

  const ClarificationDialogWidget({
    super.key,
    required this.onComplete,
    this.onManualRequested,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentQuestion = ref.watch(currentQuestionProvider);
    final questions = ref.watch(pendingClarificationsProvider);
    final currentIndex = ref.watch(currentQuestionIndexProvider);
    final choices = ref.watch(clarificationChoicesProvider);
    final allAnswered = ref.watch(allQuestionsAnsweredProvider);

    if (currentQuestion == null) {
      return const SizedBox.shrink();
    }

    final selectedOption = choices[currentQuestion.id];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with progress
          Row(
            children: [
              Icon(
                currentQuestion.type.icon,
                color: NexGenPalette.cyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                currentQuestion.type.displayName,
                style: const TextStyle(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Progress indicator
              _ProgressDots(
                total: questions.length,
                current: currentIndex,
                answered: choices.keys.length,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Question text
          Text(
            currentQuestion.questionText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),

          // Context if available
          if (currentQuestion.context != null) ...[
            const SizedBox(height: 8),
            Text(
              currentQuestion.context!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Options
          Expanded(
            child: ListView.separated(
              itemCount: currentQuestion.options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final option = currentQuestion.options[index];
                final isSelected = selectedOption?.id == option.id;

                return _OptionCard(
                  option: option,
                  isSelected: isSelected,
                  questionType: currentQuestion.type,
                  onTap: () {
                    selectClarificationOption(ref, option);

                    // If manual was selected, trigger callback
                    if (option.id == 'manual' && onManualRequested != null) {
                      onManualRequested!(currentQuestion.type.displayName);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Navigation buttons
          Row(
            children: [
              // Back button
              if (currentIndex > 0)
                TextButton.icon(
                  onPressed: () => previousClarificationQuestion(ref),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white54,
                  ),
                ),
              const Spacer(),

              // Continue/Done button
              ElevatedButton(
                onPressed: selectedOption != null
                    ? () {
                        if (allAnswered) {
                          onComplete();
                        } else if (currentIndex < questions.length - 1) {
                          ref.read(currentQuestionIndexProvider.notifier).state =
                              currentIndex + 1;
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  allAnswered && selectedOption != null ? 'Continue' : 'Next',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Progress dots indicator.
class _ProgressDots extends StatelessWidget {
  final int total;
  final int current;
  final int answered;

  const _ProgressDots({
    required this.total,
    required this.current,
    required this.answered,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (index) {
        final isActive = index == current;
        final isAnswered = index < answered || (index == current && answered > current);

        return Container(
          width: isActive ? 16 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isAnswered
                ? NexGenPalette.cyan
                : isActive
                    ? NexGenPalette.cyan.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

/// Card for a single option.
class _OptionCard extends StatelessWidget {
  final ClarificationOption option;
  final bool isSelected;
  final ClarificationType questionType;
  final VoidCallback onTap;

  const _OptionCard({
    required this.option,
    required this.isSelected,
    required this.questionType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? NexGenPalette.cyan.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? NexGenPalette.cyan
                  : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Icon or color swatch
              _buildLeading(),
              const SizedBox(width: 14),

              // Label and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (option.isRecommended)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: NexGenPalette.cyan.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Recommended',
                              style: TextStyle(
                                color: NexGenPalette.cyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (option.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        option.description!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Selection indicator
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  color: isSelected ? NexGenPalette.cyan : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.black)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading() {
    // Color swatches for color questions
    if (option.colorSwatches != null && option.colorSwatches!.isNotEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: option.colorSwatches!.first,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: option.colorSwatches!.first.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: option.colorSwatches!.first.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
      );
    }

    // Icon for other questions
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isSelected
            ? NexGenPalette.cyan.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        option.icon ?? _getDefaultIcon(),
        color: isSelected ? NexGenPalette.cyan : Colors.white54,
        size: 22,
      ),
    );
  }

  IconData _getDefaultIcon() {
    switch (questionType) {
      case ClarificationType.zoneAmbiguity:
        return Icons.location_on;
      case ClarificationType.colorAmbiguity:
        return Icons.palette;
      case ClarificationType.spacingImpossible:
        return Icons.straighten;
      case ClarificationType.directionAmbiguity:
        return Icons.swap_horiz;
      case ClarificationType.conflictResolution:
        return Icons.layers;
      case ClarificationType.effectAmbiguity:
        return Icons.auto_awesome;
      case ClarificationType.brightnessAmbiguity:
        return Icons.brightness_6;
      case ClarificationType.speedAmbiguity:
        return Icons.speed;
      case ClarificationType.confirmation:
        return Icons.check_circle;
      case ClarificationType.manualFallback:
        return Icons.tune;
    }
  }
}
