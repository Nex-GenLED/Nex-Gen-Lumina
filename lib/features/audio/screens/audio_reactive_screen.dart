import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/audio/models/audio_reactive_capability.dart';
import 'package:nexgen_command/features/audio/services/audio_capability_detector.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

class AudioReactiveScreen extends ConsumerStatefulWidget {
  const AudioReactiveScreen({super.key});

  @override
  ConsumerState<AudioReactiveScreen> createState() => _AudioReactiveScreenState();
}

class _AudioReactiveScreenState extends ConsumerState<AudioReactiveScreen> {
  double _sensitivity = 128;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSensitivityChanged(double value) {
    setState(() => _sensitivity = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final repo = ref.read(wledRepositoryProvider);
      repo?.applyJson({
        'seg': [
          {'id': 0, 'si': value.round()}
        ]
      });
    });
  }

  Future<void> _applyEffect(int effectId, String effectName) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;

    final payload = <String, dynamic>{
      'on': true,
      'seg': [
        {
          'id': 0,
          'fx': effectId,
          'sx': 128,
          'ix': 128,
        }
      ]
    };

    final success = await repo.applyJson(payload);
    if (success && mounted) {
      ref.read(wledStateProvider.notifier).applyLocalPreview(
        colors: [NexGenPalette.cyan],
        effectId: effectId,
        effectName: effectName,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied: $effectName'), backgroundColor: Colors.green.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ip = ref.watch(selectedDeviceIpProvider);

    if (ip == null) {
      return Scaffold(
        appBar: const GlassAppBar(title: Text('Audio Reactive')),
        body: _buildNotSupported(context),
      );
    }

    final capAsync = ref.watch(audioCapabilityProvider(ip));

    return Scaffold(
      appBar: const GlassAppBar(title: Text('Audio Reactive')),
      body: capAsync.when(
        data: (cap) => cap.isSupported
            ? _buildSupported(context, cap)
            : _buildNotSupported(context),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildNotSupported(context),
      ),
    );
  }

  Widget _buildNotSupported(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NexGenPalette.line,
              ),
              child: Icon(Icons.mic_off, size: 48, color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 24),
            Text(
              'Audio Reactivity Not Available',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: NexGenPalette.textHigh,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'This feature requires a Nex-Gen NGL-CTRL-P1 controller '
              'with onboard microphone support.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: NexGenPalette.textMedium,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupported(BuildContext context, AudioReactiveCapability cap) {
    final state = ref.watch(wledStateProvider);
    final ip = ref.watch(selectedDeviceIpProvider)!;
    final currentEffectId = state.effectId;
    final isAudioEffectActive = cap.audioReactiveEffects.contains(currentEffectId);

    final effectNames = ref.watch(wledEffectNamesProvider(ip)).valueOrNull ?? [];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
      children: [
        // Status header
        _buildStatusCard(context, isAudioEffectActive),
        const SizedBox(height: 20),
        // Section label
        Text(
          'Audio Effects'.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: NexGenPalette.textMedium,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        // Effect grid
        _buildEffectGrid(context, cap, effectNames, currentEffectId),
        const SizedBox(height: 24),
        // Sensitivity control
        _buildSensitivitySlider(context),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? NexGenPalette.green : NexGenPalette.textMedium,
              boxShadow: isActive
                  ? [BoxShadow(color: NexGenPalette.green.withValues(alpha: 0.5), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isActive ? 'Mic Active' : 'Mic Inactive',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isActive ? NexGenPalette.green : NexGenPalette.textMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

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
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: cap.audioReactiveEffects.length,
      itemBuilder: (context, index) {
        final effectId = cap.audioReactiveEffects[index];
        // Get display name: strip "* " prefix
        String displayName = 'Effect $effectId';
        if (effectId < effectNames.length) {
          final raw = effectNames[effectId];
          displayName = raw.startsWith('* ') ? raw.substring(2) : raw;
        }
        final isActive = effectId == currentEffectId;

        return _AudioEffectCard(
          name: displayName,
          isActive: isActive,
          onTap: () => _applyEffect(effectId, displayName),
        );
      },
    );
  }

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
              Icon(Icons.mic, size: 18, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Text(
                'Mic Sensitivity',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: NexGenPalette.textHigh,
                ),
              ),
              const Spacer(),
              Text(
                _sensitivity.round().toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: NexGenPalette.cyan,
              inactiveTrackColor: NexGenPalette.line,
              thumbColor: NexGenPalette.cyan,
              overlayColor: NexGenPalette.cyan.withValues(alpha: 0.15),
            ),
            child: Slider(
              min: 0,
              max: 255,
              value: _sensitivity,
              onChanged: _onSensitivityChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Audio Effect Card ────────────────────────────────────────────────────────

class _AudioEffectCard extends StatefulWidget {
  final String name;
  final bool isActive;
  final VoidCallback onTap;

  const _AudioEffectCard({
    required this.name,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_AudioEffectCard> createState() => _AudioEffectCardState();
}

class _AudioEffectCardState extends State<_AudioEffectCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.isActive ? NexGenPalette.cyan : NexGenPalette.line;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? NexGenPalette.cyan.withValues(alpha: 0.1)
                : NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: widget.isActive
                      ? NexGenPalette.cyan
                      : NexGenPalette.textHigh,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // Pulsing bars — simple audio visualizer indicator
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  return Row(
                    children: List.generate(5, (i) {
                      final phase = (i * 0.2 + _pulseCtrl.value) % 1.0;
                      final height = 6.0 + 10.0 * math.sin(phase * math.pi);
                      return Container(
                        width: 4,
                        height: height,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: (widget.isActive
                                  ? NexGenPalette.cyan
                                  : NexGenPalette.textMedium)
                              .withValues(alpha: 0.6),
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
