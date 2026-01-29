import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/openai/openai_config.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/wled/ddp_service.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/theme.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// A sleek chat bar that sits at the bottom of the screen to control WLED using AI.
class LuminaChatBar extends ConsumerStatefulWidget {
  const LuminaChatBar({super.key});

  @override
  ConsumerState<LuminaChatBar> createState() => _LuminaChatBarState();
}

class _LuminaChatBarState extends ConsumerState<LuminaChatBar> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _error;
  late final stt.SpeechToText _speech;
  bool _listening = false;
  DdpStreamController? _ddp;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _speech.stop();
    _stopDdp();
    super.dispose();
  }

  Future<void> _onSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // If DDP streaming is active, stop it before issuing an HTTP command.
    if (ref.read(ddpStreamingProvider)) {
      _stopDdp();
    }
    final service = ref.read(wledRepositoryProvider);
    if (service == null) {
      setState(() => _error = 'No device connected');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await LuminaBrain.generateWledJson(ref, text);
      // Ask for confirmation before applying
      final shouldApply = await _showRunSetupSheet(context, payload);
      if (shouldApply == true) {
        final ok = await service.applyJson(payload);
        if (!ok) throw Exception('Device rejected payload');
        if (mounted) {
          // Update the active preset label so home screen reflects the change
          ref.read(activePresetLabelProvider.notifier).state = 'Lumina Pattern';
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pattern applied to your lights')));
        }
      }
      _controller.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      setState(() => _error = 'Lumina error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _showRunSetupSheet(BuildContext context, Map<String, dynamic> wled) async {
    String summary;
    try {
      final isOn = wled['on'];
      final bri = wled['bri'];
      int? fx;
      final seg = wled['seg'];
      if (seg is List && seg.isNotEmpty && seg.first is Map) {
        fx = (seg.first as Map)['fx'] as int?;
      }
      final parts = <String>[];
      if (isOn is bool) parts.add(isOn ? 'Power on' : 'Power off');
      if (bri is int) parts.add('Brightness ${(bri / 255 * 100).round()}%');
      if (fx != null) parts.add('Effect #$fx');
      summary = parts.isEmpty ? 'Apply the suggested lighting pattern now?' : parts.join(' • ');
    } catch (_) {
      summary = 'Apply the suggested lighting pattern now?';
    }

    return showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: NexGenPalette.gunmetal90,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Run setup?', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: NexGenPalette.textHigh)),
              ]),
              const SizedBox(height: 10),
              Text(summary, style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textMedium)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    icon: const Icon(Icons.bolt_rounded, color: Colors.black),
                    label: const Text('Apply to Lights', style: TextStyle(color: Colors.black)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    icon: const Icon(Icons.visibility_rounded, color: NexGenPalette.textHigh),
                    label: const Text('Preview only'),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Not now'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      // Stop DDP streaming when voice mode ends
      _stopDdp();
      return;
    }
    try {
      final available = await _speech.initialize(onStatus: (s) {}, onError: (e) {
        debugPrint('Speech error: $e');
        setState(() => _error = e.errorMsg);
      });
      if (!available) {
        setState(() => _error = 'Microphone not available');
        return;
      }
      setState(() => _listening = true);
      // Start DDP streaming for realtime AI effects at 60 FPS
      _startDdpStream();
      await _speech.listen(
        onResult: (res) {
          if (!mounted) return;
          final recognized = res.recognizedWords;
          if (recognized.isNotEmpty) {
            _controller.text = recognized;
            _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
          }
          if (res.finalResult) {
            setState(() => _listening = false);
            _stopDdp();
          }
        },
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
      );
    } catch (e) {
      setState(() => _error = 'Voice init failed: $e');
    }
  }

  Future<void> _startDdpStream() async {
    final ip = ref.read(selectedDeviceIpProvider);
    final repo = ref.read(wledRepositoryProvider);
    if (ip == null) {
      setState(() => _error = 'No device connected');
      return;
    }
    try {
      // Determine RGBW support and LED count
      final rgbw = await (repo?.supportsRgbw() ?? Future.value(false));
      final service = ref.read(ddpServiceProvider);
      if (service == null) return;
      final ledCount = await service.getLedCount() ?? 150;

      // Try to infer palette via AI once from current text (non-blocking fallback)
      List<List<int>> palette = [
        [0, 255, 255], // cyan
        [160, 32, 240], // purple
      ];
      try {
        final text = _controller.text.trim();
        if (text.isNotEmpty) {
          final payload = await LuminaBrain.generateWledJson(ref, text);
          final extracted = _extractPalette(payload, rgbw: rgbw);
          if (extracted.isNotEmpty) palette = extracted;
        }
      } catch (e) {
        debugPrint('Lumina palette fallback: $e');
      }

      // Configure device to receive UDP sync when possible (best-effort)
      unawaited(repo?.configureSyncReceiver());

      final gen = PaletteFlowGenerator(palette: palette, pixelCount: ledCount, rgbw: rgbw, speed: 0.25, spread: 0.06);
      _ddp = DdpStreamController(service);
      await _ddp!.start(gen, rgbw: rgbw);
      ref.read(ddpStreamingProvider.notifier).state = true;
    } catch (e) {
      debugPrint('Start DDP stream failed: $e');
      setState(() => _error = 'DDP start failed: $e');
    }
  }

  void _stopDdp() {
    try {
      _ddp?.stop();
      _ddp = null;
      ref.read(ddpStreamingProvider.notifier).state = false;
    } catch (_) {}
  }

  List<List<int>> _extractPalette(Map<String, dynamic> payload, {required bool rgbw}) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first as Map;
        final col = first['col'];
        if (col is List) {
          final out = <List<int>>[];
          for (final c in col) {
            if (c is List && c.length >= 3) {
              final r = (c[0] as num).toInt();
              final g = (c[1] as num).toInt();
              final b = (c[2] as num).toInt();
              if (rgbw && c.length >= 4) {
                final w = (c[3] as num).toInt();
                out.add([r, g, b, w]);
              } else {
                out.add([r, g, b]);
              }
            }
          }
          return out;
        }
      }
    } catch (e) {
      debugPrint('extractPalette error: $e');
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: NexGenPalette.cyan.withValues(alpha: _focus.hasFocus ? 0.6 : 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          IconButton(
            tooltip: _listening ? 'Stop voice' : 'Voice input',
            onPressed: _loading ? null : _toggleVoice,
            icon: Icon(_listening ? Icons.mic : Icons.mic_none),
            color: NexGenPalette.violet,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              minLines: 1,
              maxLines: 3,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Ask Lumina e.g. "Candy cane" or "Spooky lightning"',
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          _loading
              ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan))
              : IconButton(
                  tooltip: 'Send',
                  onPressed: _onSend,
                  icon: const Icon(Icons.send_rounded),
                  color: NexGenPalette.cyan,
                ),
        ]),
      ),
    );
  }
}
