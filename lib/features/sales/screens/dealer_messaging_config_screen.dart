import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/dealer_messaging_config.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/services/dealer_messaging_config_service.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DealerMessagingConfigScreen
//
// Settings screen lives inside the dealer dashboard's "Messaging" tab.
// Reads the dealer's config via the streaming dealerMessagingConfigProvider
// (which emits DealerMessagingConfig.defaults() when no doc exists yet),
// hydrates form controllers from the first emission, and keeps the
// controllers as local state thereafter so a stream rebuild can't wipe
// in-progress edits.
//
// Save flow: build a fresh DealerMessagingConfig from the controllers
// + toggle state, hand it to DealerMessagingConfigService.saveConfig
// (which sets updatedAt server-side), show a green snackbar on success.
// ─────────────────────────────────────────────────────────────────────────────

class DealerMessagingConfigScreen extends ConsumerStatefulWidget {
  final String dealerCode;
  const DealerMessagingConfigScreen({super.key, required this.dealerCode});

  @override
  ConsumerState<DealerMessagingConfigScreen> createState() =>
      _DealerMessagingConfigScreenState();
}

class _DealerMessagingConfigScreenState
    extends ConsumerState<DealerMessagingConfigScreen> {
  final _senderNameCtrl = TextEditingController();
  final _replyPhoneCtrl = TextEditingController();
  final _supportEmailCtrl = TextEditingController();
  final _customSignOffCtrl = TextEditingController();

  bool _smsOptInDefault = true;
  bool _sendDay1Reminder = true;
  bool _sendDay2Reminder = true;
  bool _sendEstimateSignedEmail = true;
  bool _sendInstallCompleteEmail = true;

  /// Set to true after the first stream emission has hydrated the
  /// controllers. Subsequent emissions are ignored — the user's
  /// in-progress edits take precedence over re-fetched server state.
  bool _hydrated = false;

  bool _isSaving = false;

  static const int _customSignOffMaxLen = 30;

  @override
  void dispose() {
    _senderNameCtrl.dispose();
    _replyPhoneCtrl.dispose();
    _supportEmailCtrl.dispose();
    _customSignOffCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromConfig(DealerMessagingConfig cfg) {
    if (_hydrated) return;
    _senderNameCtrl.text = cfg.senderName;
    _replyPhoneCtrl.text = cfg.replyPhone;
    _supportEmailCtrl.text = cfg.supportEmail;
    _customSignOffCtrl.text = cfg.customSmsSignOff ?? '';
    _smsOptInDefault = cfg.smsOptInDefault;
    _sendDay1Reminder = cfg.sendDay1Reminder;
    _sendDay2Reminder = cfg.sendDay2Reminder;
    _sendEstimateSignedEmail = cfg.sendEstimateSignedEmail;
    _sendInstallCompleteEmail = cfg.sendInstallCompleteEmail;
    _hydrated = true;
  }

  /// Build a DealerMessagingConfig from the current form state.
  DealerMessagingConfig _buildConfigFromForm() {
    final customSignOffRaw = _customSignOffCtrl.text.trim();
    return DealerMessagingConfig(
      dealerCode: widget.dealerCode,
      senderName: _senderNameCtrl.text.trim(),
      replyPhone: _replyPhoneCtrl.text.trim(),
      supportEmail: _supportEmailCtrl.text.trim(),
      smsOptInDefault: _smsOptInDefault,
      sendDay1Reminder: _sendDay1Reminder,
      sendDay2Reminder: _sendDay2Reminder,
      sendEstimateSignedEmail: _sendEstimateSignedEmail,
      sendInstallCompleteEmail: _sendInstallCompleteEmail,
      customSmsSignOff: customSignOffRaw.isEmpty ? null : customSignOffRaw,
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final cfg = _buildConfigFromForm();
    if (cfg.senderName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sender name is required')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref
          .read(dealerMessagingConfigServiceProvider)
          .saveConfig(cfg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Messaging settings saved'),
          backgroundColor: NexGenPalette.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync =
        ref.watch(dealerMessagingConfigProvider(widget.dealerCode));

    return configAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load messaging config: $err',
            style: TextStyle(color: Colors.red.withValues(alpha: 0.7)),
          ),
        ),
      ),
      data: (cfg) {
        _hydrateFromConfig(cfg);
        return _buildBody();
      },
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section1Identity(),
                const SizedBox(height: 28),
                _section2Toggles(),
                const SizedBox(height: 28),
                _section3CustomSignOff(),
                const SizedBox(height: 28),
                _section4LivePreview(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        _bottomSaveBar(),
      ],
    );
  }

  // ── Section 1: sender identity ────────────────────────────────────────────

  Widget _section1Identity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          number: 1,
          title: 'SENDER IDENTITY',
        ),
        const SizedBox(height: 14),
        _ConfigField(
          controller: _senderNameCtrl,
          label: 'Sender Name',
          helperText:
              'Appears at the end of every text message we send your customers.',
          icon: Icons.business_outlined,
        ),
        const SizedBox(height: 14),
        _ConfigField(
          controller: _replyPhoneCtrl,
          label: 'Reply Phone',
          helperText:
              'US phone number shown in emails so customers can reach you.',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 14),
        _ConfigField(
          controller: _supportEmailCtrl,
          label: 'Support Email',
          helperText:
              'Shown in booking confirmation and completion emails.',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
        ),
      ],
    );
  }

  // ── Section 2: toggles ────────────────────────────────────────────────────

  Widget _section2Toggles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          number: 2,
          title: 'MESSAGE TOGGLES',
        ),
        const SizedBox(height: 12),
        _toggleCard([
          _ConfigToggle(
            title: 'Booking Confirmation Email',
            subtitle: 'Sent immediately when a customer signs their estimate',
            value: _sendEstimateSignedEmail,
            onChanged: (v) => setState(() => _sendEstimateSignedEmail = v),
          ),
          _divider(),
          _ConfigToggle(
            title: 'Day 1 Reminder SMS',
            subtitle: 'Sent the evening before the wiring prep visit',
            value: _sendDay1Reminder,
            onChanged: (v) => setState(() => _sendDay1Reminder = v),
          ),
          _divider(),
          _ConfigToggle(
            title: 'Day 2 Reminder SMS',
            subtitle: 'Sent the evening before the light installation',
            value: _sendDay2Reminder,
            onChanged: (v) => setState(() => _sendDay2Reminder = v),
          ),
          _divider(),
          _ConfigToggle(
            title: 'Install Complete Email',
            subtitle:
                'Sent when the job is marked complete with Lumina download links',
            value: _sendInstallCompleteEmail,
            onChanged: (v) => setState(() => _sendInstallCompleteEmail = v),
          ),
          _divider(),
          _ConfigToggle(
            title: 'Default SMS Opt-In',
            subtitle:
                'New prospects are opted in to text messages by default',
            value: _smsOptInDefault,
            onChanged: (v) => setState(() => _smsOptInDefault = v),
          ),
        ]),
      ],
    );
  }

  Widget _toggleCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: NexGenPalette.line,
      );

  // ── Section 3: custom SMS sign-off ────────────────────────────────────────

  Widget _section3CustomSignOff() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          number: 3,
          title: 'CUSTOM SMS SIGN-OFF',
        ),
        const SizedBox(height: 6),
        Text(
          'Customizes the sign-off on all SMS messages.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _customSignOffCtrl,
          maxLength: _customSignOffMaxLen,
          inputFormatters: [
            LengthLimitingTextInputFormatter(_customSignOffMaxLen),
          ],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Leave blank to use 'Nex-Gen LED'",
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
            ),
            counterStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
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
              borderSide: const BorderSide(color: NexGenPalette.cyan),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ── Section 4: live preview ───────────────────────────────────────────────

  Widget _section4LivePreview() {
    final signOff = _resolveLivePreviewSignOff();
    final preview =
        "Hi Sarah! 👋 Just a reminder — tomorrow is your $signOff prep "
        "day. Our technician will be there at your home to run all "
        "wiring. Please make sure we have access to: your electrical "
        "panel, garage or utility area, and exterior eaves. No lights "
        "go up tomorrow — that's Day 2! See you then. — $signOff";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          number: 4,
          title: 'LIVE PREVIEW',
        ),
        const SizedBox(height: 6),
        Text(
          'Day 1 reminder SMS as your customers will receive it.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: NexGenPalette.cyan.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.sms_outlined,
                    color: NexGenPalette.cyan,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SMS',
                    style: TextStyle(
                      color: NexGenPalette.cyan.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Resolves the SMS sign-off the same way the model's
  /// effectiveSmsSignOff getter and the Cloud Function helper do —
  /// custom sign-off when set + non-empty, otherwise the sender name,
  /// otherwise the hardcoded fallback string.
  String _resolveLivePreviewSignOff() {
    final custom = _customSignOffCtrl.text.trim();
    if (custom.isNotEmpty) return custom;
    final sender = _senderNameCtrl.text.trim();
    if (sender.isNotEmpty) return sender;
    return 'Nex-Gen LED';
  }

  // ── Sticky bottom save bar ────────────────────────────────────────────────

  Widget _bottomSaveBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: NexGenPalette.cyan,
            disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Text(
                  'Save messaging settings',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final int number;
  final String title;
  const _SectionHeader({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: NexGenPalette.cyan.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: NexGenPalette.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: NexGenPalette.cyan,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String helperText;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  const _ConfigField({
    required this.controller,
    required this.label,
    required this.helperText,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.words,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: NexGenPalette.textMedium),
        helperText: helperText,
        helperStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 11,
        ),
        helperMaxLines: 2,
        prefixIcon: Icon(icon, color: NexGenPalette.textMedium),
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
          borderSide: const BorderSide(color: NexGenPalette.cyan),
        ),
      ),
    );
  }
}

class _ConfigToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ConfigToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      activeThumbColor: NexGenPalette.cyan,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
