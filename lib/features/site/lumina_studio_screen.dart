import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class LuminaStudioScreen extends ConsumerStatefulWidget {
  const LuminaStudioScreen({super.key});

  @override
  ConsumerState<LuminaStudioScreen> createState() => _LuminaStudioScreenState();
}

class _LuminaStudioScreenState extends ConsumerState<LuminaStudioScreen> {
  int _step = 0;
  String? _area; // Landscape, Patio, Deck, Pool
  XFile? _image;
  Uint8List? _imageBytes;
  final _picker = ImagePicker();
  final List<_Fixture> _fixtures = [];
  bool _submitting = false;

  Future<void> _pickImage(ImageSource src) async {
    try {
      final file = await _picker.pickImage(source: src, imageQuality: 85);
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _image = file;
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Image pick failed: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to get photo: $e')));
    }
  }

  void _addFixture(_FixtureType type) {
    setState(() => _fixtures.add(_Fixture(type: type, dx: 0.5, dy: 0.5)));
  }

  Future<void> _requestQuote() async {
    final user = ref.read(authStateProvider).asData?.value;
    final profile = ref.read(currentUserProfileProvider).maybeWhen(data: (u) => u, orElse: () => null);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }
    if (_area == null || _fixtures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an area and add at least one fixture')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final counts = <String, int>{};
      for (final f in _fixtures) {
        counts.update(f.type.label, (v) => v + 1, ifAbsent: () => 1);
      }
      final payload = {
        'user_id': user.uid,
        'user_email': user.email,
        'user_name': user.displayName,
        'dealer_email': profile?.dealerEmail,
        'area': _area,
        'fixtures': counts,
        'created_at': FieldValue.serverTimestamp(),
        'has_photo': _imageBytes != null,
      };
      final doc = await FirebaseFirestore.instance.collection('studio_requests').add(payload);

      final to = (profile?.dealerEmail?.isNotEmpty == true) ? profile!.dealerEmail! : 'support@nex-gen.io';
      final subject = Uri.encodeComponent('Lumina Studio Quote Request');
      final body = Uri.encodeComponent('Hello,\n\nI would like a quote for adding lighting to my $_area.\n\nFixtures:\n${counts.entries.map((e)=>'• ${e.key}: ${e.value}').join('\n')}\n\nRequest ID: ${doc.id}\n(Note: Photo is available in the app records.)\n\nThank you!');
      final uri = Uri.parse('mailto:$to?subject=$subject&body=$body');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request recorded. Opening email…')));
        context.pop();
      }
    } catch (e) {
      debugPrint('Studio request failed: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: const Text('Lumina Studio'),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _buildStepHeader(context),
        const SizedBox(height: 12),
        if (_step == 0) _buildStepArea(context),
        if (_step == 1) _buildStepPhoto(context),
        if (_step == 2) _buildStepAR(context),
        if (_step == 3) _buildStepSummary(context),
        const SizedBox(height: 20),
        Row(children: [
          OutlinedButton(onPressed: _step == 0 ? null : () => setState(() => _step -= 1), child: const Text('Back')),
          const Spacer(),
          if (_step < 3)
            FilledButton(onPressed: _canContinue() ? () => setState(() => _step += 1) : null, child: const Text('Continue'))
          else
            FilledButton.icon(onPressed: _submitting ? null : _requestQuote, icon: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: const Text('Request Quote')),
        ])
      ]),
    );
  }

  bool _canContinue() {
    switch (_step) {
      case 0:
        return _area != null;
      case 1:
        return _imageBytes != null;
      case 2:
        return _fixtures.isNotEmpty;
      default:
        return true;
    }
  }

  Widget _buildStepHeader(BuildContext context) {
    const labels = ['Choose Area', 'Add a Photo', 'Place Fixtures', 'Review & Send'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          for (int i = 0; i < 4; i++) ...[
            _StepDot(index: i + 1, label: labels[i], active: i == _step, done: i < _step),
            if (i < 3)
              Expanded(child: Container(height: 2, color: i < _step ? NexGenPalette.cyan : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)))
          ]
        ]),
      ),
    );
  }

  Widget _buildStepArea(BuildContext context) {
    final options = const ['Landscape', 'Patio', 'Deck', 'Pool'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.add_business, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('Where do you want to add light?', style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in options)
              ChoiceChip(
                label: Text(o),
                selected: _area == o,
                onSelected: (_) => setState(() => _area = o),
              )
          ])
        ]),
      ),
    );
  }

  Widget _buildStepPhoto(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.photo_camera_back_outlined, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('Open Camera/Upload Photo', style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('Take Photo')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.upload), label: const Text('Upload Photo')),
          ]),
          if (_imageBytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, height: 220, fit: BoxFit.cover))
          ]
        ]),
      ),
    );
  }

  Widget _buildStepAR(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome_motion, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('Drag Virtual Fixtures onto your photo', style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 12),
          if (_imageBytes == null)
            Text('Add a photo first', style: Theme.of(context).textTheme.bodyMedium)
          else
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = 280.0;
              return Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, width: width, height: height, fit: BoxFit.cover)),
                ..._fixtures.asMap().entries.map((entry) {
                  final i = entry.key; final f = entry.value;
                  final left = f.dx * (width - 40);
                  final top = f.dy * (height - 40);
                  return Positioned(left: left, top: top, child: Draggable<_Fixture>(
                    data: f,
                    feedback: _FixtureDot(type: f.type),
                    childWhenDragging: const SizedBox.shrink(),
                    onDragEnd: (d) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final local = box.globalToLocal(d.offset);
                      setState(() {
                        f.dx = (local.dx / width).clamp(0.0, 1.0);
                        f.dy = (local.dy / height).clamp(0.0, 1.0);
                      });
                    },
                    child: GestureDetector(
                      onLongPress: () => setState(() => _fixtures.removeAt(i)),
                      child: _FixtureDot(type: f.type),
                    ),
                  ));
                })
              ]);
            }),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _addFixture(_FixtureType.path), icon: const Icon(Icons.brightness_low), label: const Text('Path Light')),
            OutlinedButton.icon(onPressed: () => _addFixture(_FixtureType.flood), icon: const Icon(Icons.flash_on), label: const Text('Flood')),
            OutlinedButton.icon(onPressed: () => _addFixture(_FixtureType.bistro), icon: const Icon(Icons.emoji_objects), label: const Text('Bistros')),
          ])
        ]),
      ),
    );
  }

  Widget _buildStepSummary(BuildContext context) {
    final counts = <String, int>{};
    for (final f in _fixtures) {
      counts.update(f.type.label, (v) => v + 1, ifAbsent: () => 1);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.request_quote, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('Request Quote', style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 12),
          Text('Area: ${_area ?? '-'}'),
          const SizedBox(height: 8),
          if (counts.isEmpty) Text('No fixtures placed') else ...[
            for (final e in counts.entries) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Expanded(child: Text(e.key)), Text('x${e.value}')]))
          ],
          const SizedBox(height: 12),
          Text('We will open your email client to send details to your dealer. A copy of your request is also stored in the app.', style: Theme.of(context).textTheme.bodySmall)
        ]),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index; final String label; final bool active; final bool done;
  const _StepDot({required this.index, required this.label, required this.active, required this.done});
  @override
  Widget build(BuildContext context) {
    final bg = done ? NexGenPalette.cyan : (active ? Theme.of(context).colorScheme.surfaceTint : Theme.of(context).colorScheme.surfaceContainerHighest);
    final fg = active || done ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(children: [
      CircleAvatar(radius: 14, backgroundColor: bg, child: Text('$index', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg))),
      const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(width: 8),
    ]);
  }
}

enum _FixtureType { path, flood, bistro }

extension on _FixtureType {
  String get label {
    switch (this) {
      case _FixtureType.path:
        return 'Path Light';
      case _FixtureType.flood:
        return 'Flood';
      case _FixtureType.bistro:
        return 'Bistros';
    }
  }
}

class _Fixture {
  final _FixtureType type;
  double dx; // 0..1 relative
  double dy; // 0..1 relative
  _Fixture({required this.type, required this.dx, required this.dy});
}

class _FixtureDot extends StatelessWidget {
  final _FixtureType type;
  const _FixtureDot({required this.type});
  @override
  Widget build(BuildContext context) {
    Color c;
    IconData icon;
    switch (type) {
      case _FixtureType.path:
        c = NexGenPalette.cyan; icon = Icons.brightness_low;
        break;
      case _FixtureType.flood:
        c = Colors.orangeAccent; icon = Icons.flash_on;
        break;
      case _FixtureType.bistro:
        c = NexGenPalette.violet; icon = Icons.emoji_objects;
        break;
    }
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999), border: Border.all(color: c)),
      child: Icon(icon, color: c),
    );
  }
}
