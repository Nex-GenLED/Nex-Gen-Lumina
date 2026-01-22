import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/led_channel_config.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:uuid/uuid.dart';

/// Multi-step wizard for setting up roofline configuration.
///
/// Steps:
/// 1. Welcome & Overview
/// 2. LED Count & Controller Info
/// 3. Segment Definition
/// 4. Anchor Point Identification
/// 5. Review & Save
class RooflineSetupWizard extends ConsumerStatefulWidget {
  const RooflineSetupWizard({super.key});

  @override
  ConsumerState<RooflineSetupWizard> createState() => _RooflineSetupWizardState();
}

class _RooflineSetupWizardState extends ConsumerState<RooflineSetupWizard> {
  final _pageController = PageController();
  int _currentStep = 0;
  final _uuid = const Uuid();

  // Step 1: Basic info
  int _totalLedCount = 200;
  String _startLocation = '';
  String _endLocation = '';
  ArchitectureType _architectureType = ArchitectureType.gabled;

  // Step 2: Segments
  final List<_SegmentDraft> _segments = [];

  // Step 3: Validation
  bool _isValidating = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveConfiguration() async {
    setState(() => _isValidating = true);

    try {
      // Build the configuration
      final segments = <RooflineSegment>[];
      int currentStart = 0;

      for (int i = 0; i < _segments.length; i++) {
        final draft = _segments[i];
        segments.add(RooflineSegment(
          id: _uuid.v4(),
          name: draft.name,
          pixelCount: draft.ledCount,
          startPixel: currentStart,
          type: draft.type,
          direction: draft.direction,
          anchorPixels: draft.anchorIndices,
          anchorLedCount: 2,
          sortOrder: i,
        ));
        currentStart += draft.ledCount;
      }

      final config = RooflineConfiguration(
        id: '',
        name: 'My Roofline',
        segments: segments,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save via provider - need user ID
      final userId = ref.read(authStateProvider).maybeWhen(
        data: (user) => user?.uid,
        orElse: () => null,
      );

      if (userId == null) {
        throw Exception('User not logged in');
      }

      final service = ref.read(rooflineConfigServiceProvider);
      await service.saveConfiguration(userId, config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Roofline configuration saved!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving configuration: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Roofline Setup'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgressIndicator(),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildWelcomeStep(),
                _buildLedInfoStep(),
                _buildSegmentsStep(),
                _buildAnchorsStep(),
                _buildReviewStep(),
              ],
            ),
          ),

          // Navigation buttons
          _buildNavigationButtons(),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(5, (index) {
          final isActive = index <= _currentStep;
          final isCurrent = index == _currentStep;

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? NexGenPalette.cyan : NexGenPalette.gunmetal90,
                    border: Border.all(
                      color: isCurrent ? NexGenPalette.cyan : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isActive && !isCurrent
                        ? const Icon(Icons.check, size: 16, color: Colors.black)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.black : NexGenPalette.textMedium,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
                if (index < 4)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: index < _currentStep
                          ? NexGenPalette.cyan
                          : NexGenPalette.gunmetal90,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [NexGenPalette.cyan, NexGenPalette.violet],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.home_rounded, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Text(
              'Welcome to Design Studio Setup',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'This wizard will help you configure your roofline so Lumina can create perfectly customized lighting designs for your home.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // What we'll capture
          _buildInfoCard(
            icon: Icons.lightbulb_outline,
            title: 'What we\'ll capture:',
            items: [
              'Total LED count and positions',
              'Segment boundaries (corners, peaks)',
              'Direction of light flow',
              'Anchor points for accent lighting',
            ],
          ),
          const SizedBox(height: 16),

          _buildInfoCard(
            icon: Icons.tips_and_updates_outlined,
            title: 'Tips for best results:',
            items: [
              'Have your WLED controller connected',
              'Know your total LED count',
              'Identify where corners and peaks are',
              'Use the "Find LED" feature to verify positions',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLedInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LED Installation Info',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us about your LED installation.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const SizedBox(height: 24),

          // Total LED count
          _buildGlassField(
            label: 'Total LED Count',
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    if (_totalLedCount > 10) {
                      setState(() => _totalLedCount -= 10);
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    '$_totalLedCount',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: NexGenPalette.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    setState(() => _totalLedCount += 10);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Auto-detect button
          _buildActionButton(
            icon: Icons.search,
            label: 'Auto-detect from Controller',
            onTap: _autoDetectLedCount,
          ),
          const SizedBox(height: 24),

          // Start location
          _buildGlassTextField(
            label: 'Where is LED #1 located?',
            hint: 'e.g., Left side of garage',
            value: _startLocation,
            onChanged: (v) => setState(() => _startLocation = v),
          ),
          const SizedBox(height: 16),

          // End location
          _buildGlassTextField(
            label: 'Where is the last LED located?',
            hint: 'e.g., Right side of front door',
            value: _endLocation,
            onChanged: (v) => setState(() => _endLocation = v),
          ),
          const SizedBox(height: 24),

          // Architecture type
          _buildGlassField(
            label: 'Home Architecture Type',
            child: Column(
              children: ArchitectureType.values.map((type) {
                final isSelected = _architectureType == type;
                return GestureDetector(
                  onTap: () => setState(() => _architectureType = type),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? NexGenPalette.cyan.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                type.displayName,
                                style: TextStyle(
                                  color: NexGenPalette.textHigh,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              Text(
                                type.description,
                                style: TextStyle(
                                  color: NexGenPalette.textMedium,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentsStep() {
    final remainingLeds = _totalLedCount - _segments.fold(0, (sum, s) => sum + s.ledCount);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Define Segments',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Break your roofline into logical segments (runs, corners, peaks).',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
              ),
              const SizedBox(height: 12),

              // LED count status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: remainingLeds == 0
                      ? Colors.green.withValues(alpha: 0.15)
                      : remainingLeds < 0
                          ? Colors.red.withValues(alpha: 0.15)
                          : NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: remainingLeds == 0
                        ? Colors.green
                        : remainingLeds < 0
                            ? Colors.red
                            : NexGenPalette.cyan,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      remainingLeds == 0
                          ? Icons.check_circle
                          : remainingLeds < 0
                              ? Icons.error
                              : Icons.info_outline,
                      color: remainingLeds == 0
                          ? Colors.green
                          : remainingLeds < 0
                              ? Colors.red
                              : NexGenPalette.cyan,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      remainingLeds == 0
                          ? 'All $_totalLedCount LEDs assigned!'
                          : remainingLeds > 0
                              ? '$remainingLeds LEDs remaining to assign'
                              : '${remainingLeds.abs()} LEDs over budget',
                      style: TextStyle(
                        color: remainingLeds == 0
                            ? Colors.green
                            : remainingLeds < 0
                                ? Colors.red
                                : NexGenPalette.cyan,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Segments list
        Expanded(
          child: _segments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        size: 64,
                        color: NexGenPalette.textMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No segments yet',
                        style: TextStyle(color: NexGenPalette.textMedium),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the button below to add your first segment',
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _segments.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = _segments.removeAt(oldIndex);
                      _segments.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final segment = _segments[index];
                    return _buildSegmentCard(segment, index);
                  },
                ),
        ),

        // Add segment button
        Padding(
          padding: const EdgeInsets.all(24),
          child: _buildActionButton(
            icon: Icons.add,
            label: 'Add Segment',
            onTap: _showAddSegmentDialog,
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentCard(_SegmentDraft segment, int index) {
    return Card(
      key: ValueKey(segment.id),
      margin: const EdgeInsets.only(bottom: 12),
      color: NexGenPalette.gunmetal90,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: NexGenPalette.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Drag handle
            Icon(Icons.drag_handle, color: NexGenPalette.textMedium, size: 20),
            const SizedBox(width: 12),

            // Segment type icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _getSegmentTypeColor(segment.type).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getSegmentTypeIcon(segment.type),
                color: _getSegmentTypeColor(segment.type),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.name,
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${segment.ledCount} LEDs • ${segment.type.displayName} • ${segment.direction.shortName}',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Edit button
            IconButton(
              icon: Icon(Icons.edit, color: NexGenPalette.cyan, size: 20),
              onPressed: () => _showEditSegmentDialog(index),
            ),

            // Delete button
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () {
                setState(() => _segments.removeAt(index));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnchorsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify Anchor Points',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Anchor points are key positions (corners, peaks) that receive accent colors in patterns.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const SizedBox(height: 16),

          // Find LED button
          _buildActionButton(
            icon: Icons.search,
            label: 'Find LED on Controller',
            subtitle: 'Light up specific LEDs to verify positions',
            onTap: _showFindLedDialog,
          ),
          const SizedBox(height: 24),

          // Segments with anchors
          if (_segments.isEmpty)
            Center(
              child: Text(
                'Add segments first to configure anchors',
                style: TextStyle(color: NexGenPalette.textMedium),
              ),
            )
          else
            ...List.generate(_segments.length, (index) {
              final segment = _segments[index];
              return _buildAnchorConfigCard(segment, index);
            }),
        ],
      ),
    );
  }

  Widget _buildAnchorConfigCard(_SegmentDraft segment, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: NexGenPalette.gunmetal90,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: NexGenPalette.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getSegmentTypeIcon(segment.type),
                  color: _getSegmentTypeColor(segment.type),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  segment.name,
                  style: TextStyle(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${segment.ledCount} LEDs',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Anchor points display
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...segment.anchorIndices.map((idx) {
                  return Chip(
                    label: Text('LED $idx'),
                    backgroundColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                    labelStyle: TextStyle(color: NexGenPalette.cyan, fontSize: 12),
                    deleteIcon: Icon(Icons.close, size: 16, color: NexGenPalette.cyan),
                    onDeleted: () {
                      setState(() {
                        segment.anchorIndices.remove(idx);
                      });
                    },
                  );
                }),
                ActionChip(
                  label: const Text('+ Add'),
                  onPressed: () => _showAddAnchorDialog(index),
                  backgroundColor: NexGenPalette.gunmetal90,
                  labelStyle: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewStep() {
    final totalAssigned = _segments.fold(0, (sum, s) => sum + s.ledCount);
    final isValid = totalAssigned == _totalLedCount && _segments.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review Configuration',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),

          // Summary card
          _buildGlassCard(
            child: Column(
              children: [
                _buildSummaryRow('Total LEDs', '$_totalLedCount'),
                _buildSummaryRow('Segments', '${_segments.length}'),
                _buildSummaryRow('Architecture', _architectureType.displayName),
                _buildSummaryRow('Start Location', _startLocation.isEmpty ? 'Not set' : _startLocation),
                _buildSummaryRow('End Location', _endLocation.isEmpty ? 'Not set' : _endLocation),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Segments summary
          Text(
            'Segments',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),

          ...List.generate(_segments.length, (index) {
            final segment = _segments[index];
            final startLed = _segments.take(index).fold(0, (sum, s) => sum + s.ledCount);
            final endLed = startLed + segment.ledCount - 1;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _getSegmentTypeColor(segment.type).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: _getSegmentTypeColor(segment.type),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          segment.name,
                          style: TextStyle(
                            color: NexGenPalette.textHigh,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'LEDs $startLed-$endLed (${segment.ledCount}) • ${segment.type.displayName}',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),

          // Validation status
          if (!isValid)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _segments.isEmpty
                          ? 'Please add at least one segment'
                          : 'LED count mismatch: $totalAssigned assigned vs $_totalLedCount total',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    final totalAssigned = _segments.fold(0, (sum, s) => sum + s.ledCount);
    final canProceed = _currentStep < 4 ||
        (totalAssigned == _totalLedCount && _segments.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        border: Border(top: BorderSide(color: NexGenPalette.line)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _previousStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexGenPalette.textHigh,
                  side: BorderSide(color: NexGenPalette.line),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Back'),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            child: FilledButton(
              onPressed: canProceed
                  ? (_currentStep == 4 ? _saveConfiguration : _nextStep)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                disabledBackgroundColor: NexGenPalette.gunmetal90,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isValidating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_currentStep == 4 ? 'Save Configuration' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widgets
  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: NexGenPalette.cyan, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: NexGenPalette.cyan,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              color: NexGenPalette.textMedium,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: NexGenPalette.textMedium,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassTextField({
    required String label,
    required String hint,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: NexGenPalette.textMedium,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: value,
          onChanged: onChanged,
          style: TextStyle(color: NexGenPalette.textHigh),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
            filled: true,
            fillColor: NexGenPalette.gunmetal90,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: NexGenPalette.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: NexGenPalette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: NexGenPalette.cyan),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NexGenPalette.cyan.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: NexGenPalette.cyan),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: NexGenPalette.cyan,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: NexGenPalette.textMedium)),
          Text(
            value,
            style: TextStyle(
              color: NexGenPalette.textHigh,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Dialogs and actions
  Future<void> _autoDetectLedCount() async {
    // Try to fetch segments from the connected controller to determine LED count
    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      try {
        final segments = await repo.fetchSegments();
        if (segments.isNotEmpty) {
          // Calculate total LEDs from all segments
          int totalLeds = 0;
          for (final seg in segments) {
            if (seg.stop > totalLeds) {
              totalLeds = seg.stop;
            }
          }
          if (totalLeds > 0) {
            setState(() => _totalLedCount = totalLeds);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Detected $totalLeds LEDs from controller'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('Auto-detect LED count failed: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not detect LED count - is controller connected?'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showAddSegmentDialog() {
    final nameController = TextEditingController();
    final ledCountController = TextEditingController(text: '20');
    var selectedType = SegmentType.run;
    var selectedDirection = SegmentDirection.leftToRight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                border: Border(top: BorderSide(color: NexGenPalette.line)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Segment',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: NexGenPalette.textHigh,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Name
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: NexGenPalette.textHigh),
                    decoration: InputDecoration(
                      labelText: 'Segment Name',
                      hintText: 'e.g., Front Peak',
                      labelStyle: TextStyle(color: NexGenPalette.textMedium),
                      hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: NexGenPalette.matteBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // LED count
                  TextField(
                    controller: ledCountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: NexGenPalette.textHigh),
                    decoration: InputDecoration(
                      labelText: 'LED Count',
                      labelStyle: TextStyle(color: NexGenPalette.textMedium),
                      filled: true,
                      fillColor: NexGenPalette.matteBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Type selection
                  Text(
                    'Segment Type',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SegmentType.values.map((type) {
                      final isSelected = selectedType == type;
                      return ChoiceChip(
                        label: Text(type.displayName),
                        selected: isSelected,
                        selectedColor: NexGenPalette.cyan,
                        backgroundColor: NexGenPalette.matteBlack,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : NexGenPalette.textMedium,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setDialogState(() => selectedType = type);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Direction selection
                  Text(
                    'LED Direction',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SegmentDirection.values.take(6).map((dir) {
                      final isSelected = selectedDirection == dir;
                      return ChoiceChip(
                        label: Text(dir.shortName),
                        selected: isSelected,
                        selectedColor: NexGenPalette.cyan,
                        backgroundColor: NexGenPalette.matteBlack,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : NexGenPalette.textMedium,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setDialogState(() => selectedDirection = dir);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NexGenPalette.textHigh,
                            side: BorderSide(color: NexGenPalette.line),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final name = nameController.text.trim();
                            final ledCount = int.tryParse(ledCountController.text) ?? 0;

                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a name')),
                              );
                              return;
                            }
                            if (ledCount <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid LED count')),
                              );
                              return;
                            }

                            setState(() {
                              _segments.add(_SegmentDraft(
                                id: _uuid.v4(),
                                name: name,
                                ledCount: ledCount,
                                type: selectedType,
                                direction: selectedDirection,
                              ));
                            });
                            Navigator.pop(context);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: NexGenPalette.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Add'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditSegmentDialog(int index) {
    final segment = _segments[index];
    final nameController = TextEditingController(text: segment.name);
    final ledCountController = TextEditingController(text: '${segment.ledCount}');
    var selectedType = segment.type;
    var selectedDirection = segment.direction;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                border: Border(top: BorderSide(color: NexGenPalette.line)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit Segment',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: NexGenPalette.textHigh,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: nameController,
                    style: TextStyle(color: NexGenPalette.textHigh),
                    decoration: InputDecoration(
                      labelText: 'Segment Name',
                      labelStyle: TextStyle(color: NexGenPalette.textMedium),
                      filled: true,
                      fillColor: NexGenPalette.matteBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: ledCountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: NexGenPalette.textHigh),
                    decoration: InputDecoration(
                      labelText: 'LED Count',
                      labelStyle: TextStyle(color: NexGenPalette.textMedium),
                      filled: true,
                      fillColor: NexGenPalette.matteBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Segment Type',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SegmentType.values.map((type) {
                      final isSelected = selectedType == type;
                      return ChoiceChip(
                        label: Text(type.displayName),
                        selected: isSelected,
                        selectedColor: NexGenPalette.cyan,
                        backgroundColor: NexGenPalette.matteBlack,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : NexGenPalette.textMedium,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setDialogState(() => selectedType = type);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'LED Direction',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SegmentDirection.values.take(6).map((dir) {
                      final isSelected = selectedDirection == dir;
                      return ChoiceChip(
                        label: Text(dir.shortName),
                        selected: isSelected,
                        selectedColor: NexGenPalette.cyan,
                        backgroundColor: NexGenPalette.matteBlack,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : NexGenPalette.textMedium,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setDialogState(() => selectedDirection = dir);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NexGenPalette.textHigh,
                            side: BorderSide(color: NexGenPalette.line),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              _segments[index] = _SegmentDraft(
                                id: segment.id,
                                name: nameController.text.trim(),
                                ledCount: int.tryParse(ledCountController.text) ?? segment.ledCount,
                                type: selectedType,
                                direction: selectedDirection,
                                anchorIndices: segment.anchorIndices,
                              );
                            });
                            Navigator.pop(context);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: NexGenPalette.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddAnchorDialog(int segmentIndex) {
    final segment = _segments[segmentIndex];
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: Text(
          'Add Anchor Point',
          style: TextStyle(color: NexGenPalette.textHigh),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the local LED index (0-${segment.ledCount - 1})',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: TextStyle(color: NexGenPalette.textHigh),
              decoration: InputDecoration(
                labelText: 'LED Index',
                labelStyle: TextStyle(color: NexGenPalette.textMedium),
                filled: true,
                fillColor: NexGenPalette.matteBlack,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          FilledButton(
            onPressed: () {
              final index = int.tryParse(controller.text);
              if (index != null && index >= 0 && index < segment.ledCount) {
                setState(() {
                  if (!segment.anchorIndices.contains(index)) {
                    segment.anchorIndices.add(index);
                    segment.anchorIndices.sort();
                  }
                });
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showFindLedDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: Text(
          'Find LED',
          style: TextStyle(color: NexGenPalette.textHigh),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter an LED number to light it up on your roofline',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: TextStyle(color: NexGenPalette.textHigh),
              decoration: InputDecoration(
                labelText: 'LED Number (0-${_totalLedCount - 1})',
                labelStyle: TextStyle(color: NexGenPalette.textMedium),
                filled: true,
                fillColor: NexGenPalette.matteBlack,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          FilledButton(
            onPressed: () async {
              final ledIndex = int.tryParse(controller.text);
              if (ledIndex != null && ledIndex >= 0 && ledIndex < _totalLedCount) {
                // Send command to WLED to light up this LED
                final repo = ref.read(wledRepositoryProvider);
                if (repo != null) {
                  await repo.applyJson({
                    'on': true,
                    'bri': 255,
                    'seg': [
                      {
                        'i': [ledIndex, 255, 0, 0], // Red LED at index
                      }
                    ],
                  });
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
            ),
            child: const Text('Light It Up'),
          ),
        ],
      ),
    );
  }

  IconData _getSegmentTypeIcon(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return Icons.horizontal_rule;
      case SegmentType.corner:
        return Icons.turn_right;
      case SegmentType.peak:
        return Icons.change_history;
      case SegmentType.column:
        return Icons.height;
      case SegmentType.connector:
        return Icons.link;
    }
  }

  Color _getSegmentTypeColor(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return NexGenPalette.cyan;
      case SegmentType.corner:
        return Colors.orange;
      case SegmentType.peak:
        return Colors.purple;
      case SegmentType.column:
        return Colors.green;
      case SegmentType.connector:
        return NexGenPalette.textMedium;
    }
  }
}

/// Draft segment data during wizard
class _SegmentDraft {
  final String id;
  String name;
  int ledCount;
  SegmentType type;
  SegmentDirection direction;
  List<int> anchorIndices;

  _SegmentDraft({
    required this.id,
    required this.name,
    required this.ledCount,
    this.type = SegmentType.run,
    this.direction = SegmentDirection.leftToRight,
    List<int>? anchorIndices,
  }) : anchorIndices = anchorIndices ?? [];
}
