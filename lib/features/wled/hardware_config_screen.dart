import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

class HardwareConfigScreen extends ConsumerStatefulWidget {
  const HardwareConfigScreen({super.key});

  @override
  ConsumerState<HardwareConfigScreen> createState() => _HardwareConfigScreenState();
}

class _HardwareConfigScreenState extends ConsumerState<HardwareConfigScreen> {
  static const int _portCount = 8;

  // QuinLED Dig-Octa GPIO pin map (actual pins from device config)
  static const List<int> _digOctaPins = [0, 1, 2, 3, 4, 5, 12, 13];

  late List<bool> _enabled;
  late List<TextEditingController> _countCtrls;
  late List<FocusNode> _countFocus;

  double _maxCurrentA = 30; // 0-60A
  bool _saving = false;

  // LED type: 30 = SK6812 RGBW (default for this installation)
  int _ledType = 30;

  @override
  void initState() {
    super.initState();
    // Default: only port 1 enabled, ports 2-8 disabled
    _enabled = List.generate(_portCount, (i) => i == 0);
    _countCtrls = List.generate(_portCount, (i) => TextEditingController(text: i == 0 ? '30' : '0'));
    _countFocus = List.generate(_portCount, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _countCtrls) {
      c.dispose();
    }
    for (final f in _countFocus) {
      f.dispose();
    }
    super.dispose();
  }

  int _parseCount(int idx) {
    try {
      final v = int.tryParse(_countCtrls[idx].text.trim()) ?? 0;
      return v.clamp(0, 5000); // reasonably high upper bound
    } catch (_) {
      return 0;
    }
  }

  int get _totalLeds {
    int total = 0;
    for (var i = 0; i < _portCount; i++) {
      if (_enabled[i]) total += _parseCount(i);
    }
    return total;
  }

  // Computes 1-based inclusive LED range for UI; returns null if disabled or count==0
  ({int start, int end})? _uiRangeForPort(int index) {
    if (!_enabled[index]) return null;
    final count = _parseCount(index);
    if (count <= 0) return null;
    int start0 = 0;
    for (var i = 0; i < index; i++) {
      if (_enabled[i]) start0 += _parseCount(i);
    }
    final start1 = start0 + 1; // convert to 1-based for display
    final end1 = start0 + count;
    return (start: start1, end: end1);
  }

  List<Map<String, dynamic>> _buildDigOctaSegmentsForCfg() {
    // Build Dig-Octa LED bus objects for /json/cfg hw.led.ins
    // Using minimal required fields to avoid 400 errors from unsupported fields
    final List<Map<String, dynamic>> segs = [];
    int startAddress = 0; // zero-based LED index across all enabled ports
    for (var i = 0; i < _portCount; i++) {
      if (!_enabled[i]) continue;
      final count = _parseCount(i);
      if (count <= 0) continue;
      final pin = _digOctaPins[i];
      segs.add({
        'start': startAddress,
        'len': count,
        'pin': [pin],       // WLED expects pin as array
        'order': 1,         // Color order: 1 = GRB (correct for SK6812)
        'rev': false,
        'skip': 0,
        'type': _ledType,   // SK6812 RGBW = 30
      });
      startAddress += count;
    }
    return segs;
  }

  Future<void> _saveAndReboot() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No WLED device selected.')));
      }
      return;
    }

    try {
      // Build /json/cfg payload with correct WLED structure: hw.led.ins
      final total = _totalLeds;
      final ledBuses = _buildDigOctaSegmentsForCfg();

      // WLED /json/cfg expects: { hw: { led: { total, ins: [...] } } }
      // Using minimal fields to ensure compatibility
      final cfgPayload = {
        'hw': {
          'led': {
            'total': total,
            'maxpwr': (_maxCurrentA * 1000).round(),
            'ins': ledBuses,
          },
        },
      };

      debugPrint('📤 Hardware config payload: $cfgPayload');

      final okCfg = await repo.applyConfig(cfgPayload);
      if (!okCfg) {
        debugPrint('applyConfig (cfg with pins) failed - may need manual configuration');
        // Show guidance dialog for manual configuration
        if (mounted) {
          await _showManualConfigDialog(context, total, ledBuses);
        }
        return;
      }

      // Reboot controller so the new pixel counts take effect
      final okRb = await repo.applyJson({'rb': true});
      if (!okRb) debugPrint('reboot command failed');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuration saved. Rebooting controller...')));
      }
    } catch (e) {
      debugPrint('Save & Reboot error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Configuration failed. Please use WLED web interface.')));
        await _showManualConfigDialog(context, _totalLeds, _buildDigOctaSegmentsForCfg());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showManualConfigDialog(BuildContext context, int totalLeds, List<Map<String, dynamic>> ledBuses) async {
    final ip = ref.read(selectedDeviceIpProvider);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Configuration Required'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The WLED device requires manual LED configuration via its web interface.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Text('Open: http://$ip in a browser'),
              const SizedBox(height: 8),
              const Text('Go to: Config → LED Preferences'),
              const SizedBox(height: 16),
              const Text('Configure these settings:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('• Total LEDs: $totalLeds'),
              Text('• LED Type: SK6812 RGBW'),
              Text('• Color Order: GRB (important!)'),
              const SizedBox(height: 8),
              const Text('Per-port configuration:', style: TextStyle(fontWeight: FontWeight.w600)),
              ...ledBuses.map((bus) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text('• GPIO ${(bus['pin'] as List).first}: ${bus['len']} LEDs (start: ${bus['start']})'),
              )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Setting Color Order to GRB fixes color accuracy issues (green/red swap).',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Hardware Configuration')),
      floatingActionButton: _buildFab(context),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Channel Configuration', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Assign lights to the 8 output channels on your controller.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            ...List.generate(_portCount, (i) => _PortCard(
                  index: i,
                  enabled: _enabled[i],
                  controller: _countCtrls[i],
                  focusNode: _countFocus[i],
                  range: _uiRangeForPort(i),
                  onToggle: (val) => setState(() => _enabled[i] = val),
                  onChanged: (val) => setState(() {}),
                )),
            const SizedBox(height: 16),
            _AdvancedPowerSettings(
              maxCurrentA: _maxCurrentA,
              onCurrentChanged: (v) => setState(() => _maxCurrentA = v),
            ),
            const SizedBox(height: 90), // space for FAB
          ],
        ),
      ),
    );
  }

  Widget _buildFab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      onPressed: _saving ? null : _saveAndReboot,
      backgroundColor: scheme.error,
      foregroundColor: scheme.onError,
      icon: _saving
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onError))
          : const Icon(Icons.restart_alt),
      label: Text(_saving ? 'Saving…' : 'Save & Reboot Board'),
    );
  }
}

class _PortCard extends StatelessWidget {
  const _PortCard({
    required this.index,
    required this.enabled,
    required this.controller,
    required this.focusNode,
    required this.range,
    required this.onToggle,
    required this.onChanged,
  });

  final int index;
  final bool enabled;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ({int start, int end})? range;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: 1,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Channel ${index + 1}', style: titleStyle)),
              Switch(value: enabled, onChanged: onToggle),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Number of Lights',
                helperText: 'Count the bulbs on this strand.',
                prefixIcon: Icon(Icons.light_mode),
              ),
            ),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final text = range == null ? 'Disabled' : 'Controls LEDs #${range!.start} to #${range!.end}';
              return Text(text, style: Theme.of(context).textTheme.bodySmall);
            }),
          ]),
        ),
      ),
    );
  }
}

class _AdvancedPowerSettings extends StatelessWidget {
  const _AdvancedPowerSettings({required this.maxCurrentA, required this.onCurrentChanged});

  final double maxCurrentA;
  final ValueChanged<double> onCurrentChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Row(children: [
              const Icon(Icons.power_settings_new, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(child: Text('Advanced Power Settings', style: Theme.of(context).textTheme.titleMedium)),
            ]),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Power Supply Limit', style: Theme.of(context).textTheme.labelLarge),
                      Slider(
                        value: maxCurrentA.clamp(0, 60),
                        min: 0,
                        max: 60,
                        divisions: 60,
                        label: '${maxCurrentA.round()}A',
                        onChanged: onCurrentChanged,
                      ),
                      Text('${maxCurrentA.round()}A max. Applies to entire controller.', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // LED type info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.memory, color: NexGenPalette.cyan),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LED Driver: SK6812 RGBW',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NexGenPalette.cyan),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Type 30 - GRB+W Color Order',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
