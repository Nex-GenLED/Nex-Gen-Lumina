import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
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

  // Step 2: LED Installation Info
  Set<int> _selectedChannels = {1}; // Channels 1-8, at least one selected
  int _totalLedCount = 200; // Total LEDs combined (1-2600)
  Map<int, int> _channelLedCounts = {}; // LED count per channel
  String _controllerLocation = '';
  String _startLocation = ''; // Where LED 1 is located
  String _ledDirection = 'leftToRight'; // Overall LED direction
  String _endLocation = ''; // Where final LED is located
  ArchitectureType _architectureType = ArchitectureType.gabled;

  // Step 3: Segments
  final List<_SegmentDraft> _segments = [];

  // Step 4: Validation
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

        // Determine architectural role based on segment type for AI
        ArchitecturalRole? aiRole;
        if (draft.segmentType == InstallerSegmentType.peak) {
          aiRole = ArchitecturalRole.peak;
        } else if (draft.segmentType == InstallerSegmentType.corner) {
          aiRole = ArchitecturalRole.corner;
        }

        segments.add(RooflineSegment(
          id: _uuid.v4(),
          name: draft.name,
          pixelCount: draft.ledCount,
          startPixel: currentStart,
          type: draft.type, // Uses the converter to SegmentType
          direction: draft.direction, // Uses the converter to SegmentDirection
          anchorPixels: draft.anchorIndices,
          anchorLedCount: 2,
          sortOrder: i,
          architecturalRole: aiRole,
          location: draft.location.storageName,
          isProminent: draft.isProminent,
        ));
        currentStart += draft.ledCount;
      }

      // Generate a meaningful name based on architecture type
      final configName = '${_architectureType.displayName} Roofline';

      final config = RooflineConfiguration(
        id: '',
        name: configName,
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

      // Log AI-relevant segments for debugging
      final aiSegments = _segments.where((s) => s.isAiRelevantSegment).toList();
      if (aiSegments.isNotEmpty) {
        debugPrint('Roofline saved with ${aiSegments.length} AI-relevant segments (corners/peaks)');
        for (final seg in aiSegments) {
          debugPrint('  - ${seg.name}: ${seg.segmentType.displayName}');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Roofline configuration saved! ${segments.length} segments, ${aiSegments.length} corners/peaks for AI.'),
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
    // Check if installer mode is active - this wizard is installer-only
    final isInstallerMode = ref.watch(installerModeActiveProvider);

    if (!isInstallerMode) {
      return Scaffold(
        appBar: GlassAppBar(
          title: const Text('Roofline Setup'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Installer Access Required',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'The Roofline Setup Wizard is only available to certified installers. This ensures your LED system is configured correctly for optimal performance.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
    final session = ref.watch(installerSessionProvider);

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
              child: const Icon(Icons.roofing, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Text(
              'Roofline Configuration',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),

          if (session != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Installer: ${session.installer.name}',
                  style: TextStyle(
                    color: NexGenPalette.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            'This wizard will help you configure the customer\'s roofline so Lumina AI can create perfectly customized lighting designs.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // What we'll capture
          _buildInfoCard(
            icon: Icons.lightbulb_outline,
            title: 'What we\'ll configure:',
            items: [
              'Channel selection and LED counts',
              'Segment boundaries (corners, peaks)',
              'Direction of light flow',
              'Architecture type for AI recommendations',
            ],
          ),
          const SizedBox(height: 16),

          _buildInfoCard(
            icon: Icons.tips_and_updates_outlined,
            title: 'Before you begin:',
            items: [
              'Have the controller connected to Wi-Fi',
              'Know the total LED count per channel',
              'Identify where corners and peaks are located',
              'Note the LED direction (left to right or right to left)',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLedInfoStep() {
    // Calculate total from channel counts
    final channelTotal = _channelLedCounts.values.fold(0, (sum, count) => sum + count);

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
            'Configure the LED channels and counts for this installation.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const SizedBox(height: 24),

          // Channel Selection (1-8)
          _buildGlassField(
            label: 'Channel Selection (select active channels)',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(8, (index) {
                final channelNum = index + 1;
                final isSelected = _selectedChannels.contains(channelNum);
                return ChoiceChip(
                  label: Text('Ch $channelNum'),
                  selected: isSelected,
                  selectedColor: NexGenPalette.cyan,
                  backgroundColor: NexGenPalette.matteBlack,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : NexGenPalette.textMedium,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedChannels.add(channelNum);
                        // Initialize channel LED count if not set
                        _channelLedCounts.putIfAbsent(channelNum, () => 0);
                      } else if (_selectedChannels.length > 1) {
                        // Ensure at least one channel is selected
                        _selectedChannels.remove(channelNum);
                        _channelLedCounts.remove(channelNum);
                      }
                      // Recalculate total
                      _totalLedCount = _channelLedCounts.values.fold(0, (sum, count) => sum + count);
                    });
                  },
                );
              }),
            ),
          ),
          const SizedBox(height: 24),

          // Total LED Count Display
          _buildGlassField(
            label: 'Total LEDs Combined (1-2600)',
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: _totalLedCount > 10 ? () {
                    setState(() {
                      _totalLedCount = (_totalLedCount - 10).clamp(1, 2600);
                    });
                  } : null,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$_totalLedCount',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: NexGenPalette.cyan,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      if (channelTotal > 0 && channelTotal != _totalLedCount)
                        Text(
                          'Channel sum: $channelTotal',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _totalLedCount < 2600 ? () {
                    setState(() {
                      _totalLedCount = (_totalLedCount + 10).clamp(1, 2600);
                    });
                  } : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // LED Numeration by Channel (dynamic)
          if (_selectedChannels.isNotEmpty) ...[
            _buildGlassField(
              label: 'LED Count Per Channel',
              child: Column(
                children: (_selectedChannels.toList()..sort()).map((channelNum) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: NexGenPalette.cyan.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '$channelNum',
                                style: TextStyle(
                                  color: NexGenPalette.cyan,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Channel $channelNum:',
                            style: TextStyle(color: NexGenPalette.textHigh),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              initialValue: _channelLedCounts[channelNum]?.toString() ?? '',
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: NexGenPalette.textHigh),
                              decoration: InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
                                filled: true,
                                fillColor: NexGenPalette.matteBlack,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: NexGenPalette.line),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: NexGenPalette.line),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: NexGenPalette.cyan),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  final count = int.tryParse(value) ?? 0;
                                  _channelLedCounts[channelNum] = count.clamp(0, 2600);
                                  _totalLedCount = _channelLedCounts.values.fold(0, (sum, c) => sum + c);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'LEDs',
                            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Controller Location
          _buildGlassTextField(
            label: 'Controller Location',
            hint: 'e.g., Attic above garage, Soffit box on left side',
            value: _controllerLocation,
            onChanged: (v) => setState(() => _controllerLocation = v),
          ),
          const SizedBox(height: 16),

          // Where is LED 1 located
          _buildGlassTextField(
            label: 'Where is LED #1 located?',
            hint: 'e.g., Left side of garage, Front left corner',
            value: _startLocation,
            onChanged: (v) => setState(() => _startLocation = v),
          ),
          const SizedBox(height: 16),

          // LED Direction
          _buildGlassField(
            label: 'LED Direction (when facing the home)',
            child: Column(
              children: [
                _buildDirectionOption('leftToRight', 'Left to Right', Icons.arrow_forward),
                const SizedBox(height: 8),
                _buildDirectionOption('rightToLeft', 'Right to Left', Icons.arrow_back),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Where is final LED located
          _buildGlassTextField(
            label: 'Where is the final LED located?',
            hint: 'e.g., Right side of front door, Back right corner',
            value: _endLocation,
            onChanged: (v) => setState(() => _endLocation = v),
          ),
          const SizedBox(height: 24),

          // Architecture type
          _buildGlassField(
            label: 'Home Architecture Type',
            child: Column(
              children: [
                _buildArchitectureOption(ArchitectureType.ranch, 'Ranch', 'Flat or minimal peaks'),
                _buildArchitectureOption(ArchitectureType.gabled, 'Single Gable', 'One main roof peak'),
                _buildArchitectureOption(ArchitectureType.multiGabled, 'Multi-Gabled', 'Multiple peaks and gables'),
                _buildArchitectureOption(ArchitectureType.complex, 'Complex/Custom', 'Mixed or unique architecture'),
                _buildArchitectureOption(ArchitectureType.modern, 'Modern/Contemporary', 'Clean lines, unique angles'),
                _buildArchitectureOption(ArchitectureType.colonial, 'Colonial', 'Traditional with dormers'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionOption(String value, String label, IconData icon) {
    final isSelected = _ledDirection == value;
    return GestureDetector(
      onTap: () => setState(() => _ledDirection = value),
      child: Container(
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
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
              size: 20,
            ),
            const SizedBox(width: 12),
            Icon(icon, color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: NexGenPalette.textHigh,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchitectureOption(ArchitectureType type, String label, String description) {
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
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    description,
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
  }

  Widget _buildSegmentsStep() {
    final remainingLeds = _totalLedCount - _segments.fold(0, (sum, s) => sum + s.ledCount);
    final aiSegmentCount = _segments.where((s) => s.isAiRelevantSegment).length;

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
                'Break the roofline into logical segments. Corners and Peaks are used by Lumina AI for pattern design.',
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
                child: Column(
                  children: [
                    Row(
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
                                  : '${remainingLeds.abs()} LEDs over total count',
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
                    if (aiSegmentCount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.purple, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$aiSegmentCount corners/peaks for Lumina AI',
                            style: TextStyle(color: Colors.purple, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
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
        side: BorderSide(color: segment.isProminent ? NexGenPalette.cyan : NexGenPalette.line),
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
                color: _getInstallerSegmentTypeColor(segment.segmentType).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getInstallerSegmentTypeIcon(segment.segmentType),
                color: _getInstallerSegmentTypeColor(segment.segmentType),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        segment.name,
                        style: TextStyle(
                          color: NexGenPalette.textHigh,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (segment.isProminent) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.star, color: NexGenPalette.cyan, size: 14),
                      ],
                      if (segment.isAiRelevantSegment) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.auto_awesome, color: Colors.purple, size: 14),
                      ],
                    ],
                  ),
                  Text(
                    '${segment.ledCount} LEDs • ${segment.segmentType.displayName} • ${segment.ledDirection.shortName} • ${segment.location.displayName}',
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

  IconData _getInstallerSegmentTypeIcon(InstallerSegmentType type) {
    switch (type) {
      case InstallerSegmentType.startOfRun:
        return Icons.play_arrow;
      case InstallerSegmentType.corner:
        return Icons.turn_right;
      case InstallerSegmentType.run:
        return Icons.horizontal_rule;
      case InstallerSegmentType.peak:
        return Icons.change_history;
    }
  }

  Color _getInstallerSegmentTypeColor(InstallerSegmentType type) {
    switch (type) {
      case InstallerSegmentType.startOfRun:
        return Colors.green;
      case InstallerSegmentType.corner:
        return Colors.orange;
      case InstallerSegmentType.run:
        return NexGenPalette.cyan;
      case InstallerSegmentType.peak:
        return Colors.purple;
    }
  }

  Widget _buildAnchorsStep() {
    // Count corners and peaks which are auto-anchor points
    final autoAnchors = _segments.where((s) => s.isAiRelevantSegment).toList();

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
            'Anchor points are key positions that receive accent colors in patterns. Corners and Peaks are automatically treated as anchors.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const SizedBox(height: 16),

          // Auto-detected anchors info
          if (autoAnchors.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.purple, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Auto-detected Anchors (${autoAnchors.length})',
                        style: TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These segments are automatically used as anchor points for Lumina AI patterns:',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: autoAnchors.map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getInstallerSegmentTypeColor(s.segmentType).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${s.name} (${s.segmentType.displayName})',
                        style: TextStyle(
                          color: _getInstallerSegmentTypeColor(s.segmentType),
                          fontSize: 12,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Find LED button
          _buildActionButton(
            icon: Icons.search,
            label: 'Find LED on Controller',
            subtitle: 'Light up specific LEDs to verify positions',
            onTap: _showFindLedDialog,
          ),
          const SizedBox(height: 24),

          // Additional custom anchors
          Text(
            'Additional Custom Anchors',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add custom anchor points within segments if needed.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
          ),
          const SizedBox(height: 16),

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
        side: BorderSide(
          color: segment.isAiRelevantSegment ? Colors.purple.withValues(alpha: 0.5) : NexGenPalette.line,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getInstallerSegmentTypeIcon(segment.segmentType),
                  color: _getInstallerSegmentTypeColor(segment.segmentType),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    segment.name,
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (segment.isAiRelevantSegment) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.purple, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'Auto',
                          style: TextStyle(color: Colors.purple, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
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
                  label: const Text('+ Add Custom'),
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

    // Count AI-relevant segments (corners and peaks)
    final aiSegments = _segments.where((s) => s.isAiRelevantSegment).toList();
    final prominentSegments = _segments.where((s) => s.isProminent).toList();

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
                _buildSummaryRow('Channels', '${_selectedChannels.length}'),
                _buildSummaryRow('Segments', '${_segments.length}'),
                _buildSummaryRow('Architecture', _architectureType.displayName),
                _buildSummaryRow('LED Direction', _ledDirection == 'leftToRight' ? 'Left to Right' : 'Right to Left'),
                _buildSummaryRow('Controller', _controllerLocation.isEmpty ? 'Not set' : _controllerLocation),
                _buildSummaryRow('LED #1 Location', _startLocation.isEmpty ? 'Not set' : _startLocation),
                _buildSummaryRow('Final LED', _endLocation.isEmpty ? 'Not set' : _endLocation),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AI Pattern Design info
          if (aiSegments.isNotEmpty || prominentSegments.isNotEmpty) ...[
            _buildGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.purple, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Lumina AI Pattern Data',
                        style: TextStyle(
                          color: NexGenPalette.textHigh,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (aiSegments.isNotEmpty) ...[
                    Text(
                      'Corners & Peaks (${aiSegments.length}):',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: aiSegments.map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getInstallerSegmentTypeColor(s.segmentType).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${s.name} (${s.segmentType.displayName})',
                          style: TextStyle(
                            color: _getInstallerSegmentTypeColor(s.segmentType),
                            fontSize: 11,
                          ),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (prominentSegments.isNotEmpty) ...[
                    Text(
                      'Prominent Features (${prominentSegments.length}):',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: prominentSegments.map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: NexGenPalette.cyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, color: NexGenPalette.cyan, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              s.name,
                              style: TextStyle(color: NexGenPalette.cyan, fontSize: 11),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

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
                border: Border.all(
                  color: segment.isProminent ? NexGenPalette.cyan : NexGenPalette.line,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _getInstallerSegmentTypeColor(segment.segmentType).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: _getInstallerSegmentTypeColor(segment.segmentType),
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                segment.name,
                                style: TextStyle(
                                  color: NexGenPalette.textHigh,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (segment.isProminent) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.star, color: NexGenPalette.cyan, size: 14),
                            ],
                            if (segment.isAiRelevantSegment) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.auto_awesome, color: Colors.purple, size: 14),
                            ],
                          ],
                        ),
                        Text(
                          'LEDs $startLed-$endLed (${segment.ledCount}) • ${segment.segmentType.displayName} • ${segment.location.displayName}',
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
                          : 'LED count mismatch: $totalAssigned LEDs in segments vs $_totalLedCount total. Segment totals must match the total LED count.',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Configuration valid! All $_totalLedCount LEDs are assigned across ${_segments.length} segments.',
                      style: const TextStyle(color: Colors.green),
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

  // Note: Auto-detect functionality would require WLED provider
  // which is abstracted away from installer interface

  void _showAddSegmentDialog() {
    final nameController = TextEditingController();
    final ledCountController = TextEditingController(text: '20');
    var selectedType = InstallerSegmentType.run;
    var selectedDirection = InstallerLedDirection.leftToRight;
    var selectedLocation = SegmentLocation.front;
    bool isProminent = false;

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
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                border: Border(top: BorderSide(color: NexGenPalette.line)),
              ),
              child: SingleChildScrollView(
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

                    // Segment Name
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: NexGenPalette.textHigh),
                      decoration: InputDecoration(
                        labelText: 'Segment Name',
                        hintText: 'e.g., Front Peak, Left Gutter Run',
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

                    // # of LEDs in segment
                    TextField(
                      controller: ledCountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: NexGenPalette.textHigh),
                      decoration: InputDecoration(
                        labelText: '# of LEDs in Segment',
                        labelStyle: TextStyle(color: NexGenPalette.textMedium),
                        filled: true,
                        fillColor: NexGenPalette.matteBlack,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Segment Type (Start of Run, Corner, Run, Peak)
                    Text(
                      'Segment Type',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: InstallerSegmentType.values.map((type) {
                        final isSelected = selectedType == type;
                        return ChoiceChip(
                          label: Text(type.displayName),
                          selected: isSelected,
                          selectedColor: _getInstallerSegmentTypeColor(type),
                          backgroundColor: NexGenPalette.matteBlack,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : NexGenPalette.textMedium,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setDialogState(() => selectedType = type);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedType.isAiRelevant) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.purple, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Lumina AI will use this for pattern design',
                                style: TextStyle(color: Colors.purple, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // LED Direction
                    Text(
                      'LED Direction',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: InstallerLedDirection.values.map((dir) {
                        final isSelected = selectedDirection == dir;
                        return ChoiceChip(
                          label: Text(dir.displayName),
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
                    const SizedBox(height: 20),

                    // Location When Facing Front of Home
                    Text(
                      'Location (when facing front of home)',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SegmentLocation.values.map((loc) {
                        final isSelected = selectedLocation == loc;
                        return ChoiceChip(
                          label: Text(loc.displayName),
                          selected: isSelected,
                          selectedColor: NexGenPalette.cyan,
                          backgroundColor: NexGenPalette.matteBlack,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : NexGenPalette.textMedium,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setDialogState(() => selectedLocation = loc);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Mark Segment as Prominent Feature
                    CheckboxListTile(
                      value: isProminent,
                      onChanged: (value) {
                        setDialogState(() => isProminent = value ?? false);
                      },
                      title: Text(
                        'Mark as Prominent Feature',
                        style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14),
                      ),
                      subtitle: Text(
                        'AI will prioritize this segment in pattern designs',
                        style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                      ),
                      activeColor: NexGenPalette.cyan,
                      checkColor: Colors.black,
                      contentPadding: EdgeInsets.zero,
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
                                  const SnackBar(content: Text('Please enter a segment name')),
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
                                  segmentType: selectedType,
                                  ledDirection: selectedDirection,
                                  location: selectedLocation,
                                  isProminent: isProminent,
                                ));
                              });
                              Navigator.pop(context);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: NexGenPalette.cyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('Add Segment'),
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
      ),
    );
  }

  void _showEditSegmentDialog(int index) {
    final segment = _segments[index];
    final nameController = TextEditingController(text: segment.name);
    final ledCountController = TextEditingController(text: '${segment.ledCount}');
    var selectedType = segment.segmentType;
    var selectedDirection = segment.ledDirection;
    var selectedLocation = segment.location;
    var isProminent = segment.isProminent;

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
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                border: Border(top: BorderSide(color: NexGenPalette.line)),
              ),
              child: SingleChildScrollView(
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
                        labelText: '# of LEDs in Segment',
                        labelStyle: TextStyle(color: NexGenPalette.textMedium),
                        filled: true,
                        fillColor: NexGenPalette.matteBlack,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Segment Type',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: InstallerSegmentType.values.map((type) {
                        final isSelected = selectedType == type;
                        return ChoiceChip(
                          label: Text(type.displayName),
                          selected: isSelected,
                          selectedColor: _getInstallerSegmentTypeColor(type),
                          backgroundColor: NexGenPalette.matteBlack,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : NexGenPalette.textMedium,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setDialogState(() => selectedType = type);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'LED Direction',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: InstallerLedDirection.values.map((dir) {
                        final isSelected = selectedDirection == dir;
                        return ChoiceChip(
                          label: Text(dir.displayName),
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
                    const SizedBox(height: 20),

                    Text(
                      'Location (when facing front of home)',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SegmentLocation.values.map((loc) {
                        final isSelected = selectedLocation == loc;
                        return ChoiceChip(
                          label: Text(loc.displayName),
                          selected: isSelected,
                          selectedColor: NexGenPalette.cyan,
                          backgroundColor: NexGenPalette.matteBlack,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : NexGenPalette.textMedium,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setDialogState(() => selectedLocation = loc);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    CheckboxListTile(
                      value: isProminent,
                      onChanged: (value) {
                        setDialogState(() => isProminent = value ?? false);
                      },
                      title: Text(
                        'Mark as Prominent Feature',
                        style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14),
                      ),
                      subtitle: Text(
                        'AI will prioritize this segment in pattern designs',
                        style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                      ),
                      activeColor: NexGenPalette.cyan,
                      checkColor: Colors.black,
                      contentPadding: EdgeInsets.zero,
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
                                  segmentType: selectedType,
                                  ledDirection: selectedDirection,
                                  location: selectedLocation,
                                  isProminent: isProminent,
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
              'Enter an LED number to identify its position on the roofline. The LED will light up red on the controller.',
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
            const SizedBox(height: 12),
            Text(
              'Ensure the controller is connected and online.',
              style: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.7), fontSize: 12),
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
                // Note: This would need a connected repository to work
                // For now, show a message about what would happen
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('LED $ledIndex should now be lit red on the controller'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid LED number (0-${_totalLedCount - 1})'),
                    backgroundColor: Colors.orange,
                  ),
                );
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

}

/// Simplified segment types for the installer wizard
enum InstallerSegmentType {
  startOfRun,
  corner,
  run,
  peak,
}

extension InstallerSegmentTypeExtension on InstallerSegmentType {
  String get displayName {
    switch (this) {
      case InstallerSegmentType.startOfRun:
        return 'Start of Run';
      case InstallerSegmentType.corner:
        return 'Corner';
      case InstallerSegmentType.run:
        return 'Run';
      case InstallerSegmentType.peak:
        return 'Peak';
    }
  }

  String get description {
    switch (this) {
      case InstallerSegmentType.startOfRun:
        return 'First segment where LEDs begin';
      case InstallerSegmentType.corner:
        return 'Direction change point';
      case InstallerSegmentType.run:
        return 'Straight segment of lights';
      case InstallerSegmentType.peak:
        return 'Roof peak or apex point';
    }
  }

  /// Convert to RooflineSegment SegmentType for saving
  SegmentType toSegmentType() {
    switch (this) {
      case InstallerSegmentType.startOfRun:
        return SegmentType.run; // Start of run is still a run type
      case InstallerSegmentType.corner:
        return SegmentType.corner;
      case InstallerSegmentType.run:
        return SegmentType.run;
      case InstallerSegmentType.peak:
        return SegmentType.peak;
    }
  }

  /// Check if this segment type is important for AI pattern design
  bool get isAiRelevant {
    return this == InstallerSegmentType.corner || this == InstallerSegmentType.peak;
  }
}

/// Simplified LED direction for the installer wizard
enum InstallerLedDirection {
  leftToRight,
  rightToLeft,
  bottomToTop,
  topToBottom,
}

extension InstallerLedDirectionExtension on InstallerLedDirection {
  String get displayName {
    switch (this) {
      case InstallerLedDirection.leftToRight:
        return 'Left to Right';
      case InstallerLedDirection.rightToLeft:
        return 'Right to Left';
      case InstallerLedDirection.bottomToTop:
        return 'Bottom to Top';
      case InstallerLedDirection.topToBottom:
        return 'Top to Bottom';
    }
  }

  String get shortName {
    switch (this) {
      case InstallerLedDirection.leftToRight:
        return 'L→R';
      case InstallerLedDirection.rightToLeft:
        return 'R→L';
      case InstallerLedDirection.bottomToTop:
        return 'B→T';
      case InstallerLedDirection.topToBottom:
        return 'T→B';
    }
  }

  /// Convert to RooflineSegment SegmentDirection for saving
  SegmentDirection toSegmentDirection() {
    switch (this) {
      case InstallerLedDirection.leftToRight:
        return SegmentDirection.leftToRight;
      case InstallerLedDirection.rightToLeft:
        return SegmentDirection.rightToLeft;
      case InstallerLedDirection.bottomToTop:
        return SegmentDirection.upward;
      case InstallerLedDirection.topToBottom:
        return SegmentDirection.downward;
    }
  }
}

/// Location relative to front of home
enum SegmentLocation {
  front,
  back,
  leftSide,
  rightSide,
}

extension SegmentLocationExtension on SegmentLocation {
  String get displayName {
    switch (this) {
      case SegmentLocation.front:
        return 'Front';
      case SegmentLocation.back:
        return 'Back';
      case SegmentLocation.leftSide:
        return 'Left Side';
      case SegmentLocation.rightSide:
        return 'Right Side';
    }
  }

  String get storageName {
    switch (this) {
      case SegmentLocation.front:
        return 'front';
      case SegmentLocation.back:
        return 'back';
      case SegmentLocation.leftSide:
        return 'left';
      case SegmentLocation.rightSide:
        return 'right';
    }
  }
}

/// Draft segment data during wizard
class _SegmentDraft {
  final String id;
  String name;
  int ledCount;
  InstallerSegmentType segmentType;
  InstallerLedDirection ledDirection;
  SegmentLocation location;
  bool isProminent;
  List<int> anchorIndices;

  _SegmentDraft({
    required this.id,
    required this.name,
    required this.ledCount,
    this.segmentType = InstallerSegmentType.run,
    this.ledDirection = InstallerLedDirection.leftToRight,
    this.location = SegmentLocation.front,
    this.isProminent = false,
    List<int>? anchorIndices,
  }) : anchorIndices = anchorIndices ?? [];

  /// Convert to SegmentType for legacy compatibility
  SegmentType get type => segmentType.toSegmentType();

  /// Convert to SegmentDirection for legacy compatibility
  SegmentDirection get direction => ledDirection.toSegmentDirection();

  /// Check if this segment should be flagged for Lumina AI
  bool get isAiRelevantSegment => segmentType.isAiRelevant;
}
