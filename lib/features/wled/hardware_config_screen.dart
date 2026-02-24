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

  // QuinLED Dig-Octa GPIO pin map (default pins)
  static const List<int> _defaultPins = [0, 1, 2, 3, 4, 5, 12, 13];

  late List<bool> _enabled;
  late List<TextEditingController> _countCtrls;
  late List<FocusNode> _countFocus;
  late List<int> _pins; // actual GPIO pins per port (from device or defaults)

  double _maxCurrentA = 30; // 0-60A
  bool _saving = false;
  bool _loading = true;

  // LED type: 30 = SK6812 RGBW (default for this installation)
  int _ledType = 30;

  // Original config from device — used to determine what changed for save strategy
  WledHardwareConfig? _originalConfig;
  int _originalBusCount = 0;

  @override
  void initState() {
    super.initState();
    _enabled = List.generate(_portCount, (i) => false);
    _countCtrls = List.generate(_portCount, (_) => TextEditingController(text: '0'));
    _countFocus = List.generate(_portCount, (_) => FocusNode());
    _pins = List.of(_defaultPins);

    // Fetch real config from device after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceConfig());
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

  /// 3-tier config resolution:
  /// 1. getConfig() → full hardware bus data
  /// 2. fetchSegments() + getTotalLedCount() → segment-based fallback
  /// 3. Hardcoded defaults
  Future<void> _loadDeviceConfig() async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Tier 1: Try full hardware config (GET /json/cfg)
      final hwConfig = await repo.getConfig();
      if (hwConfig != null && hwConfig.buses.isNotEmpty) {
        _applyHardwareConfig(hwConfig);
        return;
      }

      // Tier 2: Fallback to segments + total LED count
      final segments = await repo.fetchSegments();
      final totalLeds = await repo.getTotalLedCount();
      if (segments.isNotEmpty) {
        _applySegmentFallback(segments, totalLeds);
        return;
      }

      // Tier 3: Keep hardcoded defaults (port 1 = 30 LEDs)
      _applyDefaults();
    } catch (e) {
      debugPrint('Error loading device config: $e');
      _applyDefaults();
    }
  }

  void _applyHardwareConfig(WledHardwareConfig config) {
    _originalConfig = config;
    _originalBusCount = config.buses.length;

    for (var i = 0; i < _portCount; i++) {
      if (i < config.buses.length) {
        final bus = config.buses[i];
        _enabled[i] = true;
        _countCtrls[i].text = bus.len.toString();
        if (bus.pin.isNotEmpty) _pins[i] = bus.pin.first;
        if (i == 0) _ledType = bus.type;
      } else {
        _enabled[i] = false;
        _countCtrls[i].text = '0';
      }
    }

    // maxpwr is in milliwatts; convert to amps (assume 5V)
    _maxCurrentA = (config.maxPowerMw / 1000).clamp(0, 60).toDouble();

    if (mounted) setState(() => _loading = false);
  }

  void _applySegmentFallback(List<WledSegment> segments, int? totalLeds) {
    _originalBusCount = segments.length;

    for (var i = 0; i < _portCount; i++) {
      if (i < segments.length) {
        _enabled[i] = true;
        _countCtrls[i].text = segments[i].ledCount.toString();
      } else {
        _enabled[i] = false;
        _countCtrls[i].text = '0';
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _applyDefaults() {
    _enabled[0] = true;
    _countCtrls[0].text = '30';
    _originalBusCount = 1;

    if (mounted) setState(() => _loading = false);
  }

  int _parseCount(int idx) {
    try {
      final v = int.tryParse(_countCtrls[idx].text.trim()) ?? 0;
      return v.clamp(0, 5000);
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

  /// True if the number of enabled buses changed (structural change requiring reboot)
  bool get _isStructuralChange {
    final enabledCount = _enabled.where((e) => e).length;
    return enabledCount != _originalBusCount;
  }

  ({int start, int end})? _uiRangeForPort(int index) {
    if (!_enabled[index]) return null;
    final count = _parseCount(index);
    if (count <= 0) return null;
    int start0 = 0;
    for (var i = 0; i < index; i++) {
      if (_enabled[i]) start0 += _parseCount(i);
    }
    final start1 = start0 + 1;
    final end1 = start0 + count;
    return (start: start1, end: end1);
  }

  List<Map<String, dynamic>> _buildBusesForCfg() {
    final List<Map<String, dynamic>> segs = [];
    int startAddress = 0;
    for (var i = 0; i < _portCount; i++) {
      if (!_enabled[i]) continue;
      final count = _parseCount(i);
      if (count <= 0) continue;
      segs.add({
        'start': startAddress,
        'len': count,
        'pin': [_pins[i]],
        'order': 1,
        'rev': false,
        'skip': 0,
        'type': _ledType,
      });
      startAddress += count;
    }
    return segs;
  }

  Future<void> _save() async {
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
      if (_isStructuralChange) {
        await _saveStructural(repo);
      } else {
        await _saveSegmentCounts(repo);
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Tier 1: Only LED counts changed — update hardware config (total + bus lengths)
  /// then sync segment boundaries. No reboot needed since bus count/pins are unchanged.
  Future<void> _saveSegmentCounts(WledRepository repo) async {
    final total = _totalLeds;
    final ledBuses = _buildBusesForCfg();

    // Step 1: Update hardware config with new total and bus lengths.
    // WLED clips segment stop values at hw.led.total, so this MUST be updated
    // before adjusting segments — otherwise increased counts get silently clipped.
    final cfgPayload = {
      'hw': {
        'led': {
          'total': total,
          'maxpwr': (_maxCurrentA * 1000).round(),
          'ins': ledBuses,
        },
      },
    };

    debugPrint('Hardware config payload (count update): $cfgPayload');

    final okCfg = await repo.applyConfig(cfgPayload);
    if (!okCfg) {
      debugPrint('applyConfig failed for count update — showing manual config dialog');
      if (mounted) {
        await _showManualConfigDialog(context, total, ledBuses);
      }
      return;
    }

    // Step 2: Update segment boundaries to match the new counts.
    // This preserves segment names and per-segment settings.
    int segIdx = 0;
    int startAddress = 0;
    bool allOk = true;

    for (var i = 0; i < _portCount; i++) {
      if (!_enabled[i]) continue;
      final count = _parseCount(i);
      if (count <= 0) continue;

      final ok = await repo.updateSegmentConfig(
        segmentId: segIdx,
        start: startAddress,
        stop: startAddress + count,
      );
      if (!ok) allOk = false;

      startAddress += count;
      segIdx++;
    }

    // Step 3: Update local baseline so subsequent saves use the correct reference.
    _originalBusCount = _enabled.where((e) => e).length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(allOk ? 'LED counts updated.' : 'Some updates failed. Check your WLED device.'),
      ));
    }
  }

  /// Tier 2: Structural change (bus count/pins) — full hardware config POST + reboot
  Future<void> _saveStructural(WledRepository repo) async {
    final total = _totalLeds;
    final ledBuses = _buildBusesForCfg();

    final cfgPayload = {
      'hw': {
        'led': {
          'total': total,
          'maxpwr': (_maxCurrentA * 1000).round(),
          'ins': ledBuses,
        },
      },
    };

    debugPrint('Hardware config payload: $cfgPayload');

    final okCfg = await repo.applyConfig(cfgPayload);
    if (!okCfg) {
      debugPrint('applyConfig failed — showing manual config dialog');
      if (mounted) {
        await _showManualConfigDialog(context, total, ledBuses);
      }
      return;
    }

    // Reboot controller so the new bus config takes effect
    final okRb = await repo.applyJson({'rb': true});
    if (!okRb) debugPrint('reboot command failed');

    // Update local baseline so subsequent saves use the correct reference.
    _originalBusCount = _enabled.where((e) => e).length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved. Rebooting controller...')),
      );
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
              const Text('Go to: Config \u2192 LED Preferences'),
              const SizedBox(height: 16),
              const Text('Configure these settings:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('\u2022 Total LEDs: $totalLeds'),
              const Text('\u2022 LED Type: SK6812 RGBW'),
              const Text('\u2022 Color Order: GRB (important!)'),
              const SizedBox(height: 8),
              const Text('Per-port configuration:', style: TextStyle(fontWeight: FontWeight.w600)),
              ...ledBuses.map((bus) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text('\u2022 GPIO ${(bus['pin'] as List).first}: ${bus['len']} LEDs (start: ${bus['start']})'),
              )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
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
      floatingActionButton: _loading ? null : _buildFab(context),
      body: _loading
          ? const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Reading device configuration...'),
              ],
            ))
          : AbsorbPointer(
              absorbing: _saving,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Channel Configuration', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    'Assign lights to the output channels on your controller.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_originalConfig != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: NexGenPalette.cyan.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_outline, color: NexGenPalette.cyan, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Loaded ${_originalConfig!.buses.length} channel(s) from device',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.cyan),
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ...List.generate(_portCount, (i) => _PortCard(
                        index: i,
                        enabled: _enabled[i],
                        controller: _countCtrls[i],
                        focusNode: _countFocus[i],
                        range: _uiRangeForPort(i),
                        gpioPin: _pins[i],
                        onToggle: (val) => setState(() => _enabled[i] = val),
                        onChanged: (val) => setState(() {}),
                      )),
                  const SizedBox(height: 16),
                  _AdvancedPowerSettings(
                    maxCurrentA: _maxCurrentA,
                    ledType: _ledType,
                    onCurrentChanged: (v) => setState(() => _maxCurrentA = v),
                  ),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }

  Widget _buildFab(BuildContext context) {
    final structural = _isStructuralChange;
    final scheme = Theme.of(context).colorScheme;

    return FloatingActionButton.extended(
      onPressed: _saving ? null : _save,
      backgroundColor: structural ? scheme.error : NexGenPalette.cyan,
      foregroundColor: structural ? scheme.onError : Colors.black,
      icon: _saving
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: structural ? scheme.onError : Colors.black,
              ),
            )
          : Icon(structural ? Icons.restart_alt : Icons.save),
      label: Text(_saving
          ? 'Saving\u2026'
          : structural
              ? 'Save & Reboot Board'
              : 'Save Changes'),
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
    required this.gpioPin,
    required this.onToggle,
    required this.onChanged,
  });

  final int index;
  final bool enabled;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ({int start, int end})? range;
  final int gpioPin;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Channel ${index + 1}', style: titleStyle),
                    Text('GPIO $gpioPin', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    )),
                  ],
                ),
              ),
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
  const _AdvancedPowerSettings({
    required this.maxCurrentA,
    required this.ledType,
    required this.onCurrentChanged,
  });

  final double maxCurrentA;
  final int ledType;
  final ValueChanged<double> onCurrentChanged;

  String get _ledTypeName {
    switch (ledType) {
      case 22: return 'WS2812B RGB';
      case 30: return 'SK6812 RGBW';
      case 31: return 'TM1814 RGBW';
      default: return 'Type $ledType';
    }
  }

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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
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
                            'LED Driver: $_ledTypeName',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NexGenPalette.cyan),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Type $ledType - GRB+W Color Order',
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
