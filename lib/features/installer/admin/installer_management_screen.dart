import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/admin/admin_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Screen for managing installers
class InstallerManagementScreen extends ConsumerStatefulWidget {
  const InstallerManagementScreen({super.key});

  @override
  ConsumerState<InstallerManagementScreen> createState() => _InstallerManagementScreenState();
}

class _InstallerManagementScreenState extends ConsumerState<InstallerManagementScreen> {
  bool _showInactive = false;
  String? _selectedDealerCode;

  @override
  Widget build(BuildContext context) {
    final installersAsync = ref.watch(installerListProvider(_selectedDealerCode));
    final dealersAsync = ref.watch(dealerListProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('Manage Installers', style: TextStyle(color: Colors.white)),
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
      body: Column(
        children: [
          // Dealer filter dropdown
          dealersAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (dealers) {
              final activeDealers = dealers.where((d) => d.isActive).toList();
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  border: Border(bottom: BorderSide(color: NexGenPalette.line)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.filter_list, color: NexGenPalette.textMedium, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedDealerCode,
                          hint: Text('All Dealers', style: TextStyle(color: NexGenPalette.textMedium)),
                          dropdownColor: NexGenPalette.gunmetal90,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Dealers', style: TextStyle(color: Colors.white)),
                            ),
                            ...activeDealers.map((dealer) => DropdownMenuItem(
                                  value: dealer.dealerCode,
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: NexGenPalette.violet.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          dealer.dealerCode,
                                          style: const TextStyle(color: NexGenPalette.violet, fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(dealer.companyName, style: const TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                )),
                          ],
                          onChanged: (value) => setState(() => _selectedDealerCode = value),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Installer list
          Expanded(
            child: installersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text('Error loading installers', style: TextStyle(color: NexGenPalette.textMedium)),
                    const SizedBox(height: 8),
                    Text(error.toString(), style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ),
              ),
              data: (installers) {
                final filteredInstallers = _showInactive
                    ? installers
                    : installers.where((i) => i.isActive).toList();

                if (filteredInstallers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.engineering_outlined, size: 64, color: NexGenPalette.textMedium),
                        const SizedBox(height: 16),
                        Text(
                          'No installers yet',
                          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add your first installer to get started',
                          style: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.7), fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredInstallers.length,
                  itemBuilder: (context, index) {
                    final installer = filteredInstallers[index];
                    return _InstallerCard(
                      installer: installer,
                      onEdit: () => _showEditInstallerDialog(installer),
                      onToggleActive: () => _toggleInstallerActive(installer),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddInstallerDialog,
        backgroundColor: NexGenPalette.cyan,
        icon: const Icon(Icons.person_add, color: Colors.black),
        label: const Text('Add Installer', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showAddInstallerDialog() {
    showDialog(
      context: context,
      builder: (context) => _InstallerFormDialog(
        preselectedDealerCode: _selectedDealerCode,
        onSave: (installer) async {
          try {
            await ref.read(adminServiceProvider).addInstaller(installer);
            if (mounted) {
              Navigator.of(context).pop();
              _showSnackBar('Installer added successfully');
            }
          } catch (e) {
            _showSnackBar('Error: $e', isError: true);
          }
        },
      ),
    );
  }

  void _showEditInstallerDialog(InstallerInfo installer) {
    showDialog(
      context: context,
      builder: (context) => _InstallerFormDialog(
        installer: installer,
        onSave: (updated) async {
          try {
            await ref.read(adminServiceProvider).updateInstaller(
              installer.fullPin,
              {
                'name': updated.name,
                'email': updated.email,
                'phone': updated.phone,
              },
            );
            if (mounted) {
              Navigator.of(context).pop();
              _showSnackBar('Installer updated successfully');
            }
          } catch (e) {
            _showSnackBar('Error: $e', isError: true);
          }
        },
      ),
    );
  }

  Future<void> _toggleInstallerActive(InstallerInfo installer) async {
    final newStatus = !installer.isActive;
    final action = newStatus ? 'activate' : 'deactivate';

    // Show confirmation for deactivation
    if (!newStatus) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal90,
          title: const Text('Deactivate Installer?', style: TextStyle(color: Colors.white)),
          content: Text(
            '${installer.name} will no longer be able to log in with PIN ${installer.fullPin}.',
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
      await ref.read(adminServiceProvider).toggleInstallerActive(installer.fullPin, newStatus);
      _showSnackBar('Installer ${action}d successfully');
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    }
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

class _InstallerCard extends StatelessWidget {
  final InstallerInfo installer;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _InstallerCard({
    required this.installer,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: NexGenPalette.gunmetal90,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: installer.isActive ? NexGenPalette.line : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Full PIN badge with visual split
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: installer.isActive ? NexGenPalette.line : Colors.grey.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Dealer code part
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: installer.isActive
                              ? NexGenPalette.violet.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(7),
                            bottomLeft: Radius.circular(7),
                          ),
                        ),
                        child: Text(
                          installer.dealerCode,
                          style: TextStyle(
                            color: installer.isActive ? NexGenPalette.violet : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Installer code part
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: installer.isActive
                              ? NexGenPalette.cyan.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(7),
                            bottomRight: Radius.circular(7),
                          ),
                        ),
                        child: Text(
                          installer.installerCode,
                          style: TextStyle(
                            color: installer.isActive ? NexGenPalette.cyan : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        installer.name,
                        style: TextStyle(
                          color: installer.isActive ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${installer.totalInstallations} installations',
                        style: TextStyle(
                          color: installer.isActive ? NexGenPalette.textMedium : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status indicator
                if (!installer.isActive)
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
            if (installer.email.isNotEmpty || installer.phone.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                children: [
                  if (installer.email.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.email_outlined, size: 14, color: NexGenPalette.textMedium),
                        const SizedBox(width: 4),
                        Text(installer.email, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                      ],
                    ),
                  if (installer.phone.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_outlined, size: 14, color: NexGenPalette.textMedium),
                        const SizedBox(width: 4),
                        Text(installer.phone, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                      ],
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: NexGenPalette.line, height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: NexGenPalette.textMedium,
                  tooltip: 'Edit',
                ),
                IconButton(
                  onPressed: onToggleActive,
                  icon: Icon(
                    installer.isActive ? Icons.block : Icons.check_circle_outline,
                    size: 20,
                  ),
                  color: installer.isActive ? Colors.red : Colors.green,
                  tooltip: installer.isActive ? 'Deactivate' : 'Activate',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallerFormDialog extends ConsumerStatefulWidget {
  final InstallerInfo? installer;
  final String? preselectedDealerCode;
  final Future<void> Function(InstallerInfo) onSave;

  const _InstallerFormDialog({
    this.installer,
    this.preselectedDealerCode,
    required this.onSave,
  });

  @override
  ConsumerState<_InstallerFormDialog> createState() => _InstallerFormDialogState();
}

class _InstallerFormDialogState extends ConsumerState<_InstallerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedDealerCode;
  late TextEditingController _installerCodeController;
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isLoading = false;
  bool _isNewInstaller = false;

  @override
  void initState() {
    super.initState();
    _isNewInstaller = widget.installer == null;
    _selectedDealerCode = widget.installer?.dealerCode ?? widget.preselectedDealerCode;
    _installerCodeController = TextEditingController(text: widget.installer?.installerCode ?? '');
    _nameController = TextEditingController(text: widget.installer?.name ?? '');
    _emailController = TextEditingController(text: widget.installer?.email ?? '');
    _phoneController = TextEditingController(text: widget.installer?.phone ?? '');

    if (_isNewInstaller && _selectedDealerCode != null) {
      _loadNextCode();
    }
  }

  Future<void> _loadNextCode() async {
    if (_selectedDealerCode == null) return;
    try {
      final nextCode = await ref.read(adminServiceProvider).getNextInstallerCode(_selectedDealerCode!);
      if (mounted) {
        _installerCodeController.text = nextCode;
      }
    } catch (e) {
      // Ignore error, user can enter manually
    }
  }

  @override
  void dispose() {
    _installerCodeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dealersAsync = ref.watch(dealerListProvider);

    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: Text(
        _isNewInstaller ? 'Add Installer' : 'Edit Installer',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dealer selection (only for new installers)
              if (_isNewInstaller)
                dealersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Error loading dealers', style: TextStyle(color: Colors.red)),
                  data: (dealers) {
                    final activeDealers = dealers.where((d) => d.isActive).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedDealerCode,
                      decoration: InputDecoration(
                        labelText: 'Dealer *',
                        labelStyle: TextStyle(color: NexGenPalette.textMedium),
                        prefixIcon: Icon(Icons.business, color: NexGenPalette.violet),
                        filled: true,
                        fillColor: NexGenPalette.matteBlack,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: NexGenPalette.line),
                        ),
                      ),
                      dropdownColor: NexGenPalette.gunmetal90,
                      items: activeDealers
                          .map((d) => DropdownMenuItem(
                                value: d.dealerCode,
                                child: Text('${d.dealerCode} - ${d.companyName}',
                                    style: const TextStyle(color: Colors.white)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() => _selectedDealerCode = value);
                        if (value != null) _loadNextCode();
                      },
                      validator: (value) {
                        if (value == null) return 'Please select a dealer';
                        return null;
                      },
                    );
                  },
                )
              else
                // Show dealer info for existing installer (read-only)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NexGenPalette.matteBlack,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: NexGenPalette.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.business, color: NexGenPalette.violet),
                      const SizedBox(width: 12),
                      Text('Dealer: ${widget.installer!.dealerCode}',
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              // Installer code (only editable for new installers)
              TextFormField(
                controller: _installerCodeController,
                enabled: _isNewInstaller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Installer Code (2 digits)',
                  labelStyle: TextStyle(color: NexGenPalette.textMedium),
                  prefixIcon: Icon(Icons.tag, color: NexGenPalette.cyan),
                  helperText: _selectedDealerCode != null
                      ? 'Full PIN: $_selectedDealerCode${_installerCodeController.text.padLeft(2, '0')}'
                      : null,
                  helperStyle: const TextStyle(color: NexGenPalette.cyan),
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
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: NexGenPalette.line.withValues(alpha: 0.5)),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.length != 2) {
                    return 'Enter a 2-digit code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Name
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name *',
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
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
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

    final dealerCode = _selectedDealerCode ?? widget.installer!.dealerCode;
    final installerCode = _installerCodeController.text.padLeft(2, '0');

    final installer = InstallerInfo(
      installerCode: installerCode,
      dealerCode: dealerCode,
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      isActive: widget.installer?.isActive ?? true,
      registeredAt: widget.installer?.registeredAt,
      totalInstallations: widget.installer?.totalInstallations ?? 0,
    );

    await widget.onSave(installer);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
