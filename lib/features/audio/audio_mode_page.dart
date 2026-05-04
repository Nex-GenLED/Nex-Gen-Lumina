import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/audio/models/audio_reactive_capability.dart';
import 'package:nexgen_command/features/audio/services/audio_capability_detector.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

class AudioModePage extends ConsumerStatefulWidget {
  const AudioModePage({super.key});

  @override
  ConsumerState<AudioModePage> createState() => _AudioModePageState();
}

class _AudioModePageState extends ConsumerState<AudioModePage>
    with SingleTickerProviderStateMixin {
  double _sensitivity = 128;
  Timer? _sensitivityDebounce;
  Timer? _brightnessDebounce;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sensitivityDebounce?.cancel();
    _brightnessDebounce?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onSensitivityChanged(double value) {
    setState(() => _sensitivity = value);
    _sensitivityDebounce?.cancel();
    _sensitivityDebounce = Timer(const Duration(milliseconds: 300), () {
      final repo = ref.read(wledRepositoryProvider);
      repo?.applyJson({
        'seg': [
          {'id': 0, 'si': value.round()}
        ]
      });
    });
  }

  void _onBrightnessChanged(double value) {
    ref.read(wledStateProvider.notifier).setBrightness(value.round());
    _brightnessDebounce?.cancel();
    _brightnessDebounce = Timer(const Duration(milliseconds: 300), () {
      final repo = ref.read(wledRepositoryProvider);
      repo?.applyJson({'bri': value.round()});
    });
  }

  Future<void> _applyEffect(int effectId, String effectName) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;

    final success = await repo.applyJson({
      'on': true,
      'seg': [
        {
          'id': 0,
          'fx': effectId,
          'sx': 128,
          'ix': 128,
        }
      ]
    });

    if (success && mounted) {
      ref.read(wledStateProvider.notifier).applyLocalPreview(
        colors: [NexGenPalette.cyan],
        effectId: effectId,
        effectName: effectName,
      );
    }
  }

  Future<void> _stopAudioMode() async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;

    final success = await repo.applyJson({
      'on': true,
      'seg': [
        {
          'id': 0,
          'fx': 0,
          'col': [
            [255, 255, 255, 180]
          ],
        }
      ]
    });

    if (success && mounted) {
      ref.read(wledStateProvider.notifier).applyLocalPreview(
        colors: [const Color(0xFFFFF4E5)],
        effectId: 0,
        effectName: 'Solid',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ip = ref.watch(selectedDeviceIpProvider);

    if (ip == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF07091A),
        appBar: GlassAppBar(
          title: const Text('Audio Mode'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _buildNotSupported(context),
      );
    }

    final capAsync = ref.watch(audioCapabilityProvider(ip));

    return Scaffold(
      backgroundColor: const Color(0xFF07091A),
      appBar: GlassAppBar(
        title: const Text('Audio Mode'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: capAsync.when(
        data: (cap) => cap.hasAudioReactiveUsermod
            ? _buildSupported(context, cap, ip)
            : _buildNotSupported(context),
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
        ),
        error: (_, __) => _buildNotSupported(context),
      ),
    );
  }

  // ── Not Supported State ──────────────────────────────────────────────────

  Widget _buildNotSupported(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF111527),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: const Icon(Icons.mic_off_rounded, size: 48, color: Color(0xFFB0B0B0)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Audio Mode Not Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDCF0FF),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'This controller doesn\'t have AudioReactive firmware installed. '
              'Audio Mode requires a WLED build with the AudioReactive usermod '
              'and a microphone (onboard or I2S).',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFFB0B0B0),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111527),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: NexGenPalette.cyan),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'The Nex-Gen NGL-CTRL-P1 comes with AudioReactive firmware and onboard mic pre-installed.',
                      style: TextStyle(
                                fontSize: 12,
                        color: Color(0xFFB0B0B0),
                        height: 1.4,
                      ),
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

  // ── Supported State ──────────────────────────────────────────────────────

  Widget _buildSupported(BuildContext context, AudioReactiveCapability cap, String ip) {
    final state = ref.watch(wledStateProvider);
    final currentEffectId = state.effectId;
    final isAudioActive = cap.audioReactiveEffects.contains(currentEffectId);
    final effectNames = ref.watch(wledEffectNamesProvider(ip)).valueOrNull ?? [];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
      children: [
        _buildHeader(context, isAudioActive),
        const SizedBox(height: 20),
        _buildSensitivitySlider(context),
        const SizedBox(height: 20),
        _buildSectionLabel(context, 'Audio Effects', '${cap.audioReactiveEffects.length}'),
        const SizedBox(height: 12),
        _buildEffectGrid(context, cap, effectNames, currentEffectId),
        const SizedBox(height: 20),
        _buildBrightnessSlider(context, state),
        const SizedBox(height: 20),
        _buildStopButton(context, isAudioActive),
      ],
    );
  }

  // ── Header with live pulse indicator ─────────────────────────────────────

  Widget _buildHeader(BuildContext context, bool isActive) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF111527).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF00D4FF).withValues(alpha: 0.4)
                  : NexGenPalette.line,
            ),
            boxShadow: isActive
                ? [BoxShadow(color: const Color(0xFF00D4FF).withValues(alpha: 0.08), blurRadius: 24)]
                : null,
          ),
          child: Row(
            children: [
              // Mic icon with pulse
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  final glow = isActive ? _pulseCtrl.value * 0.4 : 0.0;
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? const Color(0xFF00D4FF).withValues(alpha: 0.12 + glow * 0.15)
                          : const Color(0xFF111527),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF00D4FF).withValues(alpha: 0.5 + glow * 0.3)
                            : NexGenPalette.line,
                      ),
                      boxShadow: isActive
                          ? [BoxShadow(color: const Color(0xFF00D4FF).withValues(alpha: glow * 0.3), blurRadius: 12)]
                          : null,
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      size: 22,
                      color: isActive ? const Color(0xFF00D4FF) : const Color(0xFFB0B0B0),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'Listening' : 'Standby',
                      style: TextStyle(
                                fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isActive ? const Color(0xFF00D4FF) : const Color(0xFFDCF0FF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'LEDs are reacting to sound'
                          : 'Select an audio effect to begin',
                      style: const TextStyle(
                                fontSize: 13,
                        color: Color(0xFFB0B0B0),
                      ),
                    ),
                  ],
                ),
              ),
              // Pulsing bars visualizer
              if (isActive)
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, _) {
                    return Row(
                      children: List.generate(4, (i) {
                        final phase = (i * 0.25 + _pulseCtrl.value) % 1.0;
                        final height = 8.0 + 16.0 * math.sin(phase * math.pi);
                        return Container(
                          width: 3,
                          height: height,
                          margin: const EdgeInsets.only(left: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(1.5),
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.7),
                          ),
                        );
                      }),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section Label ────────────────────────────────────────────────────────

  Widget _buildSectionLabel(BuildContext context, String title, String count) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFFB0B0B0),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            count,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF00D4FF),
            ),
          ),
        ),
      ],
    );
  }

  // ── Sensitivity Slider ───────────────────────────────────────────────────

  Widget _buildSensitivitySlider(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic_rounded, size: 18, color: Color(0xFF00D4FF)),
              const SizedBox(width: 8),
              const Text(
                'Mic Sensitivity',
                style: TextStyle(
                    fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFDCF0FF),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF111527),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Text(
                  _sensitivity.round().toString(),
                  style: const TextStyle(
                        fontSize: 12,
                    color: Color(0xFFB0B0B0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF00D4FF),
              inactiveTrackColor: NexGenPalette.line,
              thumbColor: const Color(0xFF00D4FF),
              overlayColor: const Color(0xFF00D4FF).withValues(alpha: 0.15),
              trackHeight: 4,
            ),
            child: Slider(
              min: 0,
              max: 255,
              value: _sensitivity,
              onChanged: _onSensitivityChanged,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Quiet', style: TextStyle(fontSize: 10, color: Color(0xFFB0B0B0))),
                Text('Loud', style: TextStyle(fontSize: 10, color: Color(0xFFB0B0B0))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Effect Grid ──────────────────────────────────────────────────────────

  Widget _buildEffectGrid(
    BuildContext context,
    AudioReactiveCapability cap,
    List<String> effectNames,
    int currentEffectId,
  ) {
    if (cap.audioReactiveEffects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No audio-reactive effects found on this controller.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textMedium),
          textAlign: TextAlign.center,
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.1,
      ),
      itemCount: cap.audioReactiveEffects.length,
      itemBuilder: (context, index) {
        final effectId = cap.audioReactiveEffects[index];
        String displayName = 'Effect $effectId';
        if (effectId < effectNames.length) {
          final raw = effectNames[effectId];
          displayName = raw.startsWith('* ') ? raw.substring(2) : raw;
        }
        final isActive = effectId == currentEffectId;

        return _AudioEffectCard(
          name: displayName,
          isActive: isActive,
          pulseController: _pulseCtrl,
          onTap: () => _applyEffect(effectId, displayName),
        );
      },
    );
  }

  // ── Brightness Slider ────────────────────────────────────────────────────

  Widget _buildBrightnessSlider(BuildContext context, WledStateModel state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_rounded, size: 18, color: Color(0xFF00D4FF)),
              const SizedBox(width: 8),
              const Text(
                'Brightness',
                style: TextStyle(
                    fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFDCF0FF),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF111527),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Text(
                  state.brightness.toString(),
                  style: const TextStyle(
                        fontSize: 12,
                    color: Color(0xFFB0B0B0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF00D4FF),
              inactiveTrackColor: NexGenPalette.line,
              thumbColor: const Color(0xFF00D4FF),
              overlayColor: const Color(0xFF00D4FF).withValues(alpha: 0.15),
              trackHeight: 4,
            ),
            child: Slider(
              min: 0,
              max: 255,
              value: state.brightness.toDouble(),
              onChanged: _onBrightnessChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ── Stop Button ──────────────────────────────────────────────────────────

  Widget _buildStopButton(BuildContext context, bool isActive) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isActive ? _stopAudioMode : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.red.withValues(alpha: 0.12)
                  : const Color(0xFF111527).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? Colors.red.withValues(alpha: 0.4)
                    : NexGenPalette.line,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.stop_rounded,
                  size: 20,
                  color: isActive ? Colors.red.shade300 : const Color(0xFFB0B0B0).withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                Text(
                  'Stop Audio Mode',
                  style: TextStyle(
                        fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.red.shade300 : const Color(0xFFB0B0B0).withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Audio Effect Card ──────────────────────────────────────────────────────

class _AudioEffectCard extends StatelessWidget {
  final String name;
  final bool isActive;
  final VoidCallback onTap;
  final AnimationController pulseController;

  const _AudioEffectCard({
    required this.name,
    required this.isActive,
    required this.onTap,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF00D4FF).withValues(alpha: 0.1)
                : NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? const Color(0xFF00D4FF) : NexGenPalette.line,
              width: isActive ? 1.5 : 1,
            ),
            boxShadow: isActive
                ? [BoxShadow(color: const Color(0xFF00D4FF).withValues(alpha: 0.1), blurRadius: 8)]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: TextStyle(
                    fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? const Color(0xFF00D4FF) : const Color(0xFFDCF0FF),
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // Pulsing bars visualizer
              AnimatedBuilder(
                animation: pulseController,
                builder: (context, _) {
                  return Row(
                    children: List.generate(5, (i) {
                      final phase = (i * 0.2 + pulseController.value) % 1.0;
                      final height = 4.0 + 8.0 * math.sin(phase * math.pi);
                      return Container(
                        width: 3,
                        height: height,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1.5),
                          color: (isActive
                                  ? const Color(0xFF00D4FF)
                                  : const Color(0xFFB0B0B0))
                              .withValues(alpha: isActive ? 0.7 : 0.3),
                        ),
                      );
                    }),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
