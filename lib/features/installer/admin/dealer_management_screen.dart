import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/admin/admin_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Screen for managing dealers
class DealerManagementScreen extends ConsumerStatefulWidget {
  const DealerManagementScreen({super.key});

  @override
  ConsumerState<DealerManagementScreen> createState() => _DealerManagementScreenState();
}

class _DealerManagementScreenState extends ConsumerState<DealerManagementScreen> {
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final dealersAsync = ref.watch(dealerListProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('Manage Dealers', style: TextStyle(color: Colors.white)),
        actions: [
          // Toggle inactive visibility
          IconButton(
            icon: Icon(
              _showInactive ? Icons.visibility : Icons.visibility_off,
              color: _showInactive ? NexGenPalette.cyan : NexGenPalette.textMedium,
            ),
            tooltip: _showInactive ? 'Hide inactive' : 'Show inactive',
            onPressed: () => setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      body: dealersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Error loading dealers', style: TextStyle(color: NexGenPalette.textMedium)),
              const SizedBox(height: 8),
              Text(error.toString(), style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
        ),
        data: (dealers) {
          final filteredDealers = _showInactive
              ? dealers
              : dealers.where((d) => d.isActive).toList();

          if (filteredDealers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.business_outlined, size: 64, color: NexGenPalette.textMedium),
                  const SizedBox(height: 16),
                  Text(
                    'No dealers yet',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your first dealer to get started',
                    style: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.7), fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredDealers.length,
            itemBuilder: (context, index) {
              final dealer = filteredDealers[index];
              return _DealerCard(
                dealer: dealer,
                onEdit: () => _showEditDealerDialog(dealer),
                onToggleActive: () => _toggleDealerActive(dealer),
                onViewInstallers: () => _viewInstallers(dealer),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDealerDialog,
        backgroundColor: NexGenPalette.cyan,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text('Add Dealer', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showAddDealerDialog() {
    showDialog(
      context: context,
      builder: (context) => _DealerFormDialog(
        onSave: (dealer) async {
          try {
            await ref.read(adminServiceProvider).addDealer(dealer);
            if (mounted) {
              Navigator.of(context).pop();
              _showSnackBar('Dealer added successfully');
            }
          } catch (e) {
            _showSnackBar('Error: $e', isError: true);
          }
        },
      ),
    );
  }

  void _showEditDealerDialog(DealerInfo dealer) {
    showDialog(
      context: context,
      builder: (context) => _DealerFormDialog(
        dealer: dealer,
        onSave: (updated) async {
          try {
            await ref.read(adminServiceProvider).updateDealer(
              dealer.dealerCode,
              {
                'name': updated.name,
                'companyName': updated.companyName,
                'email': updated.email,
                'phone': updated.phone,
              },
            );
            if (mounted) {
              Navigator.of(context).pop();
              _showSnackBar('Dealer updated successfully');
            }
          } catch (e) {
            _showSnackBar('Error: $e', isError: true);
          }
        },
      ),
    );
  }

  Future<void> _toggleDealerActive(DealerInfo dealer) async {
    final newStatus = !dealer.isActive;
    final action = newStatus ? 'activate' : 'deactivate';

    // Show confirmation for deactivation
    if (!newStatus) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal90,
          title: const Text('Deactivate Dealer?', style: TextStyle(color: Colors.white)),
          content: Text(
            'This will also deactivate all installers under ${dealer.companyName}. They will no longer be able to log in.',
            style: TextStyle(color: NexGenPalette.textMedium),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Deactivate', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    try {
      await ref.read(adminServiceProvider).toggleDealerActive(dealer.dealerCode, newStatus);
      _showSnackBar('Dealer ${action}d successfully');
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    }
  }

  void _viewInstallers(DealerInfo dealer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _InstallerListForDealer(dealer: dealer),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : NexGenPalette.cyan,
      ),
    );
  }
}

class _DealerCard extends StatelessWidget {
  final DealerInfo dealer;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onViewInstallers;

  const _DealerCard({
    required this.dealer,
    required this.onEdit,
    required this.onToggleActive,
    required this.onViewInstallers,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: NexGenPalette.gunmetal90,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: dealer.isActive ? NexGenPalette.line : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Dealer code badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: dealer.isActive
                        ? NexGenPalette.violet.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: dealer.isActive
                          ? NexGenPalette.violet.withValues(alpha: 0.5)
                          : Colors.grey.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    dealer.dealerCode,
                    style: TextStyle(
                      color: dealer.isActive ? NexGenPalette.violet : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dealer.companyName,
                        style: TextStyle(
                          color: dealer.isActive ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      if (dealer.name.isNotEmpty)
                        Text(
                          dealer.name,
                          style: TextStyle(
                            color: dealer.isActive ? NexGenPalette.textMedium : Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                // Status indicator
                if (!dealer.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'INACTIVE',
                      style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            if (dealer.email.isNotEmpty || dealer.phone.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                children: [
                  if (dealer.email.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.email_outlined, size: 14, color: NexGenPalette.textMedium),
                        const SizedBox(width: 4),
                        Text(dealer.email, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                      ],
                    ),
                  if (dealer.phone.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_outlined, size: 14, color: NexGenPalette.textMedium),
                        const SizedBox(width: 4),
                        Text(dealer.phone, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                      ],
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: NexGenPalette.line, height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onViewInstallers,
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: const Text('Installers'),
                  style: TextButton.styleFrom(foregroundColor: NexGenPalette.cyan),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: NexGenPalette.textMedium,
                  tooltip: 'Edit',
                ),
                IconButton(
                  onPressed: onToggleActive,
                  icon: Icon(
                    dealer.isActive ? Icons.block : Icons.check_circle_outline,
                    size: 20,
                  ),
                  color: dealer.isActive ? Colors.red : Colors.green,
                  tooltip: dealer.isActive ? 'Deactivate' : 'Activate',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DealerFormDialog extends ConsumerStatefulWidget {
  final DealerInfo? dealer;
  final Future<void> Function(DealerInfo) onSave;

  const _DealerFormDialog({this.dealer, required this.onSave});

  @override
  ConsumerState<_DealerFormDialog> createState() => _DealerFormDialogState();
}

class _DealerFormDialogState extends ConsumerState<_DealerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _companyController;
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isLoading = false;
  bool _isNewDealer = false;

  @override
  void initState() {
    super.initState();
    _isNewDealer = widget.dealer == null;
    _codeController = TextEditingController(text: widget.dealer?.dealerCode ?? '');
    _companyController = TextEditingController(text: widget.dealer?.companyName ?? '');
    _nameController = TextEditingController(text: widget.dealer?.name ?? '');
    _emailController = TextEditingController(text: widget.dealer?.email ?? '');
    _phoneController = TextEditingController(text: widget.dealer?.phone ?? '');

    if (_isNewDealer) {
      _loadNextCode();
    }
  }

  Future<void> _loadNextCode() async {
    try {
      final nextCode = await ref.read(adminServiceProvider).getNextDealerCode();
      if (mounted) {
        _codeController.text = nextCode;
      }
    } catch (e) {
      // Ignore error, user can enter manually
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _companyController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: Text(
        _isNewDealer ? 'Add Dealer' : 'Edit Dealer',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dealer code (only editable for new dealers)
              TextFormField(
                controller: _codeController,
                enabled: _isNewDealer,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Dealer Code (2 digits)',
                  labelStyle: TextStyle(color: NexGenPalette.textMedium),
                  prefixIcon: Icon(Icons.tag, color: NexGenPalette.violet),
                  filled: true,
                  fillColor: NexGenPalette.matteBlack,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: NexGenPalette.violet),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: NexGenPalette.line.withValues(alpha: 0.5)),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length != 2) {
                    return 'Enter a 2-digit code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Company name
              TextFormField(
                controller: _companyController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Company Name *',
                  labelStyle: TextStyle(color: NexGenPalette.textMedium),
                  prefixIcon: Icon(Icons.business, color: NexGenPalette.textMedium),
                  filled: true,
                  fillColor: NexGenPalette.matteBlack,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Company name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Contact name
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Contact Name',
                  labelStyle: TextStyle(color: NexGenPalette.textMedium),
                  prefixIcon: Icon(Icons.person_outline, color: NexGenPalette.textMedium),
                  filled: true,
                  fillColor: NexGenPalette.matteBlack,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Email
              TextFormField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: NexGenPalette.textMedium),
                  prefixIcon: Icon(Icons.email_outlined, color: NexGenPalette.textMedium),
                  filled: true,
                  fillColor: NexGenPalette.matteBlack,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Phone
              TextFormField(
                controller: _phoneController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  labelStyle: TextStyle(color: NexGenPalette.textMedium),
                  prefixIcon: Icon(Icons.phone_outlined, color: NexGenPalette.textMedium),
                  filled: true,
                  fillColor: NexGenPalette.matteBlack,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Text('Save', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final dealer = DealerInfo(
      dealerCode: _codeController.text.padLeft(2, '0'),
      companyName: _companyController.text.trim(),
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      isActive: widget.dealer?.isActive ?? true,
      registeredAt: widget.dealer?.registeredAt,
    );

    await widget.onSave(dealer);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

/// Shows installers under a specific dealer
class _InstallerListForDealer extends ConsumerWidget {
  final DealerInfo dealer;

  const _InstallerListForDealer({required this.dealer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installersAsync = ref.watch(installerListProvider(dealer.dealerCode));

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Installers', style: const TextStyle(color: Colors.white, fontSize: 18)),
            Text(
              dealer.companyName,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ],
        ),
      ),
      body: installersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (error, stack) => Center(
          child: Text('Error: $error', style: const TextStyle(color: Colors.red)),
        ),
        data: (installers) {
          if (installers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_off_outlined, size: 64, color: NexGenPalette.textMedium),
                  const SizedBox(height: 16),
                  Text(
                    'No installers for this dealer',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: installers.length,
            itemBuilder: (context, index) {
              final installer = installers[index];
              return Card(
                color: NexGenPalette.gunmetal90,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: installer.isActive
                          ? NexGenPalette.cyan.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      installer.fullPin,
                      style: TextStyle(
                        color: installer.isActive ? NexGenPalette.cyan : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    installer.name,
                    style: TextStyle(color: installer.isActive ? Colors.white : Colors.grey),
                  ),
                  subtitle: Text(
                    '${installer.totalInstallations} installations',
                    style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                  ),
                  trailing: installer.isActive
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                      : const Icon(Icons.block, color: Colors.red, size: 20),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
