import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/models/commercial/commercial_event.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';
import 'package:nexgen_command/services/commercial/event_lumina_service.dart';

/// Multi-step Event creation screen.
///
/// Steps:
///   1. Event Info — name, type, date range
///   2. Design Vision — description + AI suggestions OR skip
///   3. Automation — auto-activate / auto-revert toggles
///   4. Review & Save — summary + Save button
///
/// On save:
///   • Writes a [CommercialEvent] doc to
///     /users/{uid}/commercial_events/{eventId} (auto id).
///   • If autoActivate: creates a [ScheduleItem] (sunset, day-of-week
///     codes covering the event window) via SchedulesNotifier.add()
///     and stamps its id onto the event doc.
///   • If autoRevert: creates a second ScheduleItem (sunrise, just the
///     day after endDate) and stamps its id too.
///
/// Note on schedule recurrence: ScheduleItem is day-of-week based, so
/// a schedule for an event window will recur weekly until the event
/// is deleted (which cleans up the schedule via events_screen.dart).
/// This is intentional given the existing schedule infrastructure —
/// rebuilding it as date-specific would expand scope beyond Part 6.
class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() =>
      _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _pageController = PageController();
  int _step = 0;
  bool _isSaving = false;

  // Step 1
  final _nameCtrl = TextEditingController();
  EventType _type = EventType.sale;
  DateTime? _startDate;
  DateTime? _endDate;

  // Step 2
  final _descriptionCtrl = TextEditingController();
  bool _isGeneratingSuggestions = false;
  String? _aiError;
  List<EventDesignSuggestion> _suggestions = const [];
  EventDesignSuggestion? _selectedSuggestion;
  bool _skipDesign = false;

  // Step 3
  bool _autoActivate = true;
  bool _autoRevert = true;
  String _revertTo = 'brand_default'; // 'brand_default' or 'off'

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  // ─── Navigation ──────────────────────────────────────────────────────────

  void _goTo(int step) {
    if (step < 0 || step > 3) return;
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _nextStep() {
    final error = _validateStep(_step);
    if (error != null) {
      _showError(error);
      return;
    }
    if (_step < 3) _goTo(_step + 1);
  }

  void _prevStep() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      _goTo(_step - 1);
    }
  }

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_nameCtrl.text.trim().isEmpty) return 'Enter an event name.';
        if (_startDate == null) return 'Pick a start date.';
        if (_endDate == null) return 'Pick an end date.';
        final today = _dateOnly(DateTime.now());
        if (_dateOnly(_startDate!).isBefore(today)) {
          return 'Start date must be today or later.';
        }
        if (!_dateOnly(_endDate!).isAfter(_dateOnly(_startDate!)) &&
            !_sameDay(_startDate!, _endDate!)) {
          return 'End date must be on or after start date.';
        }
        return null;
      case 1:
        if (_skipDesign) return null;
        if (_selectedSuggestion == null) {
          return 'Pick a design or skip the design step.';
        }
        return null;
      default:
        return null;
    }
  }

  // ─── AI suggestions ──────────────────────────────────────────────────────

  Future<void> _generateSuggestions() async {
    final brand =
        ref.read(commercialBrandProfileProvider).valueOrNull;
    if (brand == null) {
      setState(() => _aiError =
          'Save your brand profile first — Lumina needs your brand colors '
          'to design suggestions.');
      return;
    }
    if (_descriptionCtrl.text.trim().length < 8) {
      setState(() =>
          _aiError = 'Describe your event so Lumina has something to work with.');
      return;
    }

    setState(() {
      _isGeneratingSuggestions = true;
      _aiError = null;
      _suggestions = const [];
      _selectedSuggestion = null;
    });

    try {
      final service = ref.read(eventLuminaServiceProvider);
      final results = await service.generateEventDesigns(
        eventDescription: _descriptionCtrl.text.trim(),
        eventType: _type,
        brand: brand,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isGeneratingSuggestions = false;
      });
    } on EventLuminaException catch (e) {
      if (!mounted) return;
      setState(() {
        _aiError = e.message;
        _isGeneratingSuggestions = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('CreateEvent: AI generation failed — $e');
      setState(() {
        _aiError = 'Lumina design generation failed. Try again, or skip '
            'the design step and add one later.';
        _isGeneratingSuggestions = false;
      });
    }
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('You must be signed in to create an event.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Allocate doc id up-front so we can reference it from
      //    schedule actionLabels if helpful.
      final eventCol = firestore
          .collection('users')
          .doc(user.uid)
          .collection('commercial_events');
      final eventRef = eventCol.doc();

      // 2. Build the event base.
      final designPayload = _selectedSuggestion?.wledPayload;
      final designName = _selectedSuggestion?.name;
      final aiGenerated = _selectedSuggestion != null;

      var event = CommercialEvent(
        eventId: eventRef.id,
        name: _nameCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        startDate: _dateOnly(_startDate!),
        endDate: _endOfDay(_endDate!),
        type: _type,
        designPayload: designPayload,
        designName: designName,
        revertDesignPayload:
            _autoRevert && _revertTo == 'off' ? const {'on': false} : null,
        scheduleItemId: null,
        revertScheduleItemId: null,
        createdBy: user.uid,
        createdAt: DateTime.now(),
        aiGenerated: aiGenerated,
      );

      // 3. Create activate / revert ScheduleItems if requested.
      String? activateId;
      String? revertId;

      if (_autoActivate && designPayload != null) {
        final repeatDays = _repeatDaysFor(event.startDate, event.endDate);
        final activateItem = ScheduleItem(
          id: 'evt_${eventRef.id}_on',
          timeLabel: 'Sunset',
          offTimeLabel: 'Sunrise',
          repeatDays: repeatDays,
          actionLabel: 'Event: ${event.name}',
          enabled: true,
          wledPayload: designPayload,
        );
        try {
          await ref.read(schedulesProvider.notifier).add(activateItem);
          activateId = activateItem.id;
        } catch (e) {
          debugPrint('CreateEvent: activate-schedule create failed — $e');
        }
      }

      if (_autoRevert) {
        final dayAfter =
            event.endDate.add(const Duration(days: 1));
        final repeatDays = [_dayCode(dayAfter)];
        final revertPayload = event.revertDesignPayload ??
            (_revertTo == 'off'
                ? const {'on': false}
                : null); // brand_default: schedule with no payload (no-op)

        final revertItem = ScheduleItem(
          id: 'evt_${eventRef.id}_off',
          timeLabel: 'Sunrise',
          offTimeLabel: null,
          repeatDays: repeatDays,
          actionLabel: 'Event ended: ${event.name}',
          enabled: true,
          wledPayload: revertPayload,
        );
        try {
          await ref.read(schedulesProvider.notifier).add(revertItem);
          revertId = revertItem.id;
        } catch (e) {
          debugPrint('CreateEvent: revert-schedule create failed — $e');
        }
      }

      // 4. Stamp schedule ids onto the event and write it.
      event = event.copyWith(
        scheduleItemId: activateId,
        revertScheduleItemId: revertId,
      );
      await eventRef.set(event.toJson());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_autoActivate
              ? 'Event saved — lights will activate automatically on '
                  '${_formatShort(event.startDate)}.'
              : 'Event saved.'),
          backgroundColor: NexGenPalette.cyan,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('New Event'),
        iconTheme: const IconThemeData(color: NexGenPalette.textHigh),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _prevStep,
        ),
      ),
      body: Column(
        children: [
          _StepProgress(currentStep: _step),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1Info(),
                _buildStep2Design(),
                _buildStep3Automation(),
                _buildStep4Review(),
              ],
            ),
          ),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: NexGenPalette.gunmetal90,
          border: Border(top: BorderSide(color: NexGenPalette.line)),
        ),
        child: Row(
          children: [
            if (_step > 0)
              TextButton(
                onPressed: _prevStep,
                child: const Text('Back',
                    style: TextStyle(color: NexGenPalette.textMedium)),
              ),
            const Spacer(),
            if (_step < 3)
              ElevatedButton(
                onPressed: _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Next'),
              )
            else
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Save Event'),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Step 1: Event Info ──────────────────────────────────────────────────

  Widget _buildStep1Info() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text("What's the event?",
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: NexGenPalette.textHigh),
          decoration: _decoration(
            label: 'Event name',
            hint: 'Black Friday Sale, Grand Opening, …',
          ),
        ),
        const SizedBox(height: 16),
        Text('Event Type',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: EventType.values.map((t) {
            final selected = _type == t;
            return ChoiceChip(
              label: Text(t.displayName),
              selected: selected,
              selectedColor: NexGenPalette.cyan.withValues(alpha: 0.2),
              backgroundColor: NexGenPalette.gunmetal,
              labelStyle: TextStyle(
                color: selected
                    ? NexGenPalette.cyan
                    : NexGenPalette.textMedium,
              ),
              side: BorderSide(
                color: selected ? NexGenPalette.cyan : NexGenPalette.line,
              ),
              onSelected: (_) => setState(() => _type = t),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _DatePickerField(
                label: 'Start Date',
                value: _startDate,
                firstDate: _dateOnly(DateTime.now()),
                onChanged: (d) {
                  setState(() {
                    _startDate = d;
                    if (_endDate != null && _endDate!.isBefore(d)) {
                      _endDate = d;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DatePickerField(
                label: 'End Date',
                value: _endDate,
                firstDate: _startDate ?? _dateOnly(DateTime.now()),
                onChanged: (d) => setState(() => _endDate = d),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Step 2: Design Vision ───────────────────────────────────────────────

  Widget _buildStep2Design() {
    final brandAsync = ref.watch(commercialBrandProfileProvider);
    final brand = brandAsync.valueOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text('Describe Your Vision',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Tell Lumina what you want to achieve with your lighting for '
          'this event. Lumina will suggest three brand-aligned designs.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descriptionCtrl,
          style: const TextStyle(color: NexGenPalette.textHigh),
          maxLines: 5,
          minLines: 3,
          decoration: _decoration(
            hint:
                'Example: "Summer clearance sale this weekend — bright, '
                'energetic, draws attention from the street."',
          ),
        ),
        const SizedBox(height: 12),
        if (brand == null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NexGenPalette.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: NexGenPalette.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_outlined,
                    color: NexGenPalette.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Save your brand profile before generating designs '
                    '— Lumina needs your brand colors as input.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NexGenPalette.textHigh),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_isGeneratingSuggestions)
          Column(
            children: [
              const SizedBox(height: 8),
              const CircularProgressIndicator(color: NexGenPalette.cyan),
              const SizedBox(height: 12),
              Text('Lumina is designing your event lighting…',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          )
        else if (_suggestions.isNotEmpty)
          ..._buildSuggestionList()
        else if (_aiError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Text(_aiError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.redAccent)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generateSuggestions,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try Again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NexGenPalette.cyan,
                    side: const BorderSide(color: NexGenPalette.cyan),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _skipDesign = true),
                  child: const Text('Skip Design',
                      style: TextStyle(color: NexGenPalette.textMedium)),
                ),
              ),
            ],
          ),
        ] else ...[
          ElevatedButton.icon(
            onPressed:
                brand == null ? null : _generateSuggestions,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Generate Design Ideas'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              disabledBackgroundColor:
                  NexGenPalette.cyan.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _skipDesign = true),
              child: const Text('Skip — add a design later',
                  style: TextStyle(color: NexGenPalette.textMedium)),
            ),
          ),
        ],
        if (_skipDesign) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: NexGenPalette.cyan, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Design step skipped — auto-activation will be '
                    'disabled. You can attach a design later.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _skipDesign = false),
                  child: const Text('Undo',
                      style: TextStyle(color: NexGenPalette.cyan)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildSuggestionList() {
    return [
      Text('Design Suggestions',
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text('Tap to select a design for your event.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      for (final s in _suggestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SuggestionCard(
            suggestion: s,
            selected: identical(_selectedSuggestion, s),
            onTap: () => setState(() => _selectedSuggestion = s),
          ),
        ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: _generateSuggestions,
        child: const Text('Generate More Ideas',
            style: TextStyle(color: NexGenPalette.cyan)),
      ),
    ];
  }

  // ─── Step 3: Automation ──────────────────────────────────────────────────

  Widget _buildStep3Automation() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text('Automation',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Lumina can automatically activate your event lighting and '
          'revert when the event ends.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: Text('Auto-activate on start date',
              style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _startDate == null
                ? 'Lights activate at sunset on the start date'
                : 'Lights activate at sunset on '
                    '${_formatShort(_startDate!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: _autoActivate && _selectedSuggestion != null,
          onChanged: _selectedSuggestion == null
              ? null
              : (v) => setState(() => _autoActivate = v),
          activeThumbColor: NexGenPalette.cyan,
          tileColor: NexGenPalette.gunmetal90,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        if (_selectedSuggestion == null) ...[
          const SizedBox(height: 6),
          Text(
            'Pick a design in the previous step to enable auto-activate.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: NexGenPalette.amber),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text('Auto-revert after event ends',
              style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            _endDate == null
                ? 'Lights revert the day after the event ends'
                : 'Lights revert at sunrise on '
                    '${_formatShort(_endDate!.add(const Duration(days: 1)))}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: _autoRevert,
          onChanged: (v) => setState(() => _autoRevert = v),
          activeThumbColor: NexGenPalette.cyan,
          tileColor: NexGenPalette.gunmetal90,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        if (_autoRevert) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: _revertTo,
              dropdownColor: NexGenPalette.gunmetal,
              style: const TextStyle(color: NexGenPalette.textHigh),
              decoration: _decoration(label: 'Revert to'),
              items: const [
                DropdownMenuItem(
                    value: 'brand_default',
                    child: Text('Brand Default Design')),
                DropdownMenuItem(
                    value: 'off', child: Text('Lights Off')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _revertTo = v);
              },
            ),
          ),
        ],
      ],
    );
  }

  // ─── Step 4: Review ──────────────────────────────────────────────────────

  Widget _buildStep4Review() {
    final designLabel = _selectedSuggestion?.name ??
        (_skipDesign ? 'Skipped (add later)' : 'None');
    final autoLabel =
        (_autoActivate && _selectedSuggestion != null) ? 'Yes' : 'No';
    final revertLabel = _autoRevert
        ? (_revertTo == 'off'
            ? 'Yes — lights off the day after'
            : 'Yes — brand default the day after')
        : 'No';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text('Review & Save',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _ReviewRow(label: 'Event', value: _nameCtrl.text.trim()),
        _ReviewRow(label: 'Type', value: _type.displayName),
        _ReviewRow(
            label: 'Dates',
            value: _startDate == null || _endDate == null
                ? '—'
                : '${_formatShort(_startDate!)} – '
                    '${_formatShort(_endDate!)}'),
        _ReviewRow(label: 'Design', value: designLabel),
        _ReviewRow(label: 'Auto-activate', value: autoLabel),
        _ReviewRow(label: 'Auto-revert', value: revertLabel),
      ],
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  InputDecoration _decoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: NexGenPalette.textMedium),
      hintStyle: const TextStyle(color: NexGenPalette.textMedium),
      filled: true,
      fillColor: NexGenPalette.gunmetal,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: NexGenPalette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: NexGenPalette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: NexGenPalette.cyan, width: 1.5),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: NexGenPalette.amber,
      ),
    );
  }

  /// Day-of-week codes ("Mon", "Tue", …) covering the inclusive range
  /// [start, end]. If the range spans 7+ days, returns ["daily"].
  List<String> _repeatDaysFor(DateTime start, DateTime end) {
    final days = end.difference(start).inDays.abs() + 1;
    if (days >= 7) return const ['daily'];
    final codes = <String>{};
    for (var d = _dateOnly(start);
        !d.isAfter(_dateOnly(end));
        d = d.add(const Duration(days: 1))) {
      codes.add(_dayCode(d));
    }
    return codes.toList(growable: false);
  }

  String _dayCode(DateTime d) {
    const codes = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return codes[d.weekday % 7];
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatShort(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

// ─── Step progress bar ─────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal90,
        border: Border(bottom: BorderSide(color: NexGenPalette.line)),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(4, (i) {
              final isComplete = i < currentStep;
              final isCurrent = i == currentStep;
              return Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isComplete
                        ? NexGenPalette.cyan
                        : isCurrent
                            ? NexGenPalette.cyan.withValues(alpha: 0.5)
                            : NexGenPalette.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            'Step ${currentStep + 1} of 4',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: NexGenPalette.textMedium),
          ),
        ],
      ),
    );
  }
}

// ─── Date picker field ─────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final DateTime firstDate;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? firstDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: NexGenPalette.cyan,
              onPrimary: Colors.black,
              surface: NexGenPalette.gunmetal,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: NexGenPalette.textMedium)),
            const SizedBox(height: 4),
            Text(
              v == null
                  ? 'Pick a date'
                  : '${_monthAbbr(v.month)} ${v.day}, ${v.year}',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: NexGenPalette.textHigh),
            ),
          ],
        ),
      ),
    );
  }

  String _monthAbbr(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[m - 1];
  }
}

// ─── Suggestion card ───────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.selected,
    required this.onTap,
  });
  final EventDesignSuggestion suggestion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? NexGenPalette.cyan : NexGenPalette.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPreviewStrip(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(suggestion.name,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  if (suggestion.mood.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        suggestion.mood,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: NexGenPalette.cyan),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(suggestion.description,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewStrip() {
    final colors = _extractColors(suggestion.wledPayload);
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(2),
      child: colors.isEmpty
          ? const SizedBox.shrink()
          : Row(
              children: [
                for (final c in colors)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  /// Pull RGBW colors out of a `seg[0].col` array for the preview strip.
  List<Color> _extractColors(Map<String, dynamic> payload) {
    final seg = payload['seg'];
    if (seg is! List || seg.isEmpty) return const [];
    final first = seg.first;
    if (first is! Map) return const [];
    final col = first['col'];
    if (col is! List) return const [];
    final out = <Color>[];
    for (final c in col) {
      if (c is! List || c.length < 3) continue;
      final r = (c[0] as num).toInt().clamp(0, 255);
      final g = (c[1] as num).toInt().clamp(0, 255);
      final b = (c[2] as num).toInt().clamp(0, 255);
      out.add(Color.fromARGB(255, r, g, b));
    }
    return out;
  }
}

// ─── Review row ────────────────────────────────────────────────────────────

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: NexGenPalette.textMedium)),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
