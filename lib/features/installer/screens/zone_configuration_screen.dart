import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Step 3: Zone Configuration screen for the installer wizard
/// Handles both Residential (linked controllers) and Commercial (zones) modes
class ZoneConfigurationScreen extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ZoneConfigurationScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  ConsumerState<ZoneConfigurationScreen> createState() => _ZoneConfigurationScreenState();
}

class _ZoneConfigurationScreenState extends ConsumerState<ZoneConfigurationScreen> {
  String? _validationError;

  void _saveAndContinue() {
    final siteMode = ref.read(installerSiteModeProvider);

    if (siteMode == SiteMode.residential) {
      final linkedControllers = ref.read(installerLinkedControllersProvider);
      if (linkedControllers.isEmpty) {
        setState(() {
          _validationError = 'Please link at least one controller.';
        });
        return;
      }
    } else {
      final zones = ref.read(installerZonesProvider);
      if (zones.isEmpty) {
        setState(() {
          _validationError = 'Please create at least one zone.';
        });
        return;
      }

      // Check each zone has a primary controller
      for (final zone in zones) {
        if (zone.primaryIp == null || zone.primaryIp!.isEmpty) {
          setState(() {
            _validationError = 'Zone "${zone.name}" needs a primary controller.';
          });
          return;
        }
      }
    }

    ref.read(installerModeActiveProvider.notifier).recordActivity();
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final siteMode = ref.watch(installerSiteModeProvider);
    final selectedControllerIds = ref.watch(installerSelectedControllersProvider);
    final controllersAsync = ref.watch(controllersStreamProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            siteMode == SiteMode.residential
                ? 'Link Controllers'
                : 'Configure Zones',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            siteMode == SiteMode.residential
                ? 'Link controllers together so they operate as a unified system. '
                    'All linked controllers will respond to commands together.'
                : 'Create zones and assign controllers to each zone. '
                    'Each zone operates independently with its own primary controller.',
            style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
          const SizedBox(height: 16),

          // Site mode toggle
          _buildSiteModeToggle(siteMode),
          const SizedBox(height: 24),

          // Main content based on mode
          controllersAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: NexGenPalette.cyan),
              ),
            ),
            error: (e, _) => _buildErrorCard('Failed to load controllers: $e'),
            data: (allControllers) {
              // Filter to only selected controllers
              final controllers = allControllers
                  .where((c) => selectedControllerIds.contains(c.id))
                  .toList();

              if (controllers.isEmpty) {
                return _buildEmptyState();
              }

              if (siteMode == SiteMode.residential) {
                return _buildResidentialMode(controllers);
              } else {
                return _buildCommercialMode(controllers);
              }
            },
          ),

          // Validation error
          if (_validationError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _validationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Navigation buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: NexGenPalette.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSiteModeToggle(SiteMode currentMode) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeButton(
              label: 'Residential',
              icon: Icons.home_outlined,
              isSelected: currentMode == SiteMode.residential,
              onTap: () {
                ref.read(installerSiteModeProvider.notifier).state = SiteMode.residential;
                setState(() => _validationError = null);
              },
            ),
          ),
          Expanded(
            child: _buildModeButton(
              label: 'Commercial',
              icon: Icons.business_outlined,
              isSelected: currentMode == SiteMode.commercial,
              onTap: () {
                ref.read(installerSiteModeProvider.notifier).state = SiteMode.commercial;
                setState(() => _validationError = null);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? NexGenPalette.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.black : NexGenPalette.textMedium,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : NexGenPalette.textMedium,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResidentialMode(List<ControllerInfo> controllers) {
    final linkedControllers = ref.watch(installerLinkedControllersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: NexGenPalette.cyan, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Linked controllers sync their brightness and effects. '
                  'Turn one on, they all turn on.',
                  style: TextStyle(color: NexGenPalette.cyan, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Select all toggle
        InkWell(
          onTap: () {
            final allIds = controllers.map((c) => c.id).toSet();
            if (linkedControllers.containsAll(allIds)) {
              ref.read(installerLinkedControllersProvider.notifier).state = {};
            } else {
              ref.read(installerLinkedControllersProvider.notifier).state = allIds;
            }
            setState(() => _validationError = null);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  linkedControllers.length == controllers.length
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: NexGenPalette.cyan,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Link All Controllers',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Controller list
        ...controllers.map((controller) {
          final isLinked = linkedControllers.contains(controller.id);
          return _buildResidentialControllerCard(controller, isLinked);
        }),
      ],
    );
  }

  Widget _buildResidentialControllerCard(ControllerInfo controller, bool isLinked) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLinked ? NexGenPalette.cyan : NexGenPalette.line,
          width: isLinked ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          final current = ref.read(installerLinkedControllersProvider);
          final newSet = Set<String>.from(current);
          if (isLinked) {
            newSet.remove(controller.id);
          } else {
            newSet.add(controller.id);
          }
          ref.read(installerLinkedControllersProvider.notifier).state = newSet;
          setState(() => _validationError = null);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Link toggle
              Switch(
                value: isLinked,
                onChanged: (value) {
                  final current = ref.read(installerLinkedControllersProvider);
                  final newSet = Set<String>.from(current);
                  if (value) {
                    newSet.add(controller.id);
                  } else {
                    newSet.remove(controller.id);
                  }
                  ref.read(installerLinkedControllersProvider.notifier).state = newSet;
                  setState(() => _validationError = null);
                },
                activeColor: NexGenPalette.cyan,
              ),
              const SizedBox(width: 12),

              // Controller info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.name ?? 'Unnamed Controller',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.ip,
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Link icon
              Icon(
                isLinked ? Icons.link : Icons.link_off,
                color: isLinked ? NexGenPalette.cyan : NexGenPalette.textMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommercialMode(List<ControllerInfo> controllers) {
    final zones = ref.watch(installerZonesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: NexGenPalette.cyan, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Create zones for different areas. Each zone can have a primary '
                  'controller and additional secondary controllers for larger areas.',
                  style: TextStyle(color: NexGenPalette.cyan, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Zone list
        if (zones.isEmpty)
          _buildNoZonesState()
        else
          ...zones.map((zone) => _buildZoneCard(zone, controllers)),

        const SizedBox(height: 16),

        // Add zone button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showAddZoneDialog(controllers),
            icon: const Icon(Icons.add, color: NexGenPalette.cyan),
            label: const Text(
              'Add Zone',
              style: TextStyle(color: NexGenPalette.cyan),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: NexGenPalette.cyan),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoZonesState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          Icon(
            Icons.grid_view_outlined,
            size: 48,
            color: NexGenPalette.textMedium.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Zones Created',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create zones to organize controllers by area.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneCard(ZoneModel zone, List<ControllerInfo> controllers) {
    // Get the controllers that are in this zone
    final zoneControllers = controllers.where((c) => zone.members.contains(c.ip)).toList();
    // Get available controllers not in any zone
    final allZones = ref.read(installerZonesProvider);
    final usedIps = allZones.expand((z) => z.members).toSet();
    final availableControllers = controllers.where((c) => !usedIps.contains(c.ip) || zone.members.contains(c.ip)).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.all(16),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            const Icon(Icons.grid_view, color: NexGenPalette.cyan, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zone.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${zone.members.length} controller${zone.members.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () {
            ref.read(installerZonesProvider.notifier).removeZone(zone.name);
            setState(() => _validationError = null);
          },
        ),
        children: [
          // Primary controller dropdown
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Primary Controller',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: zone.primaryIp,
            dropdownColor: NexGenPalette.matteBlack,
            decoration: InputDecoration(
              filled: true,
              fillColor: NexGenPalette.matteBlack,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            hint: const Text('Select primary', style: TextStyle(color: NexGenPalette.textMedium)),
            items: availableControllers.map((c) {
              return DropdownMenuItem(
                value: c.ip,
                child: Text(
                  c.name ?? c.ip,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }).toList(),
            onChanged: (ip) {
              if (ip != null) {
                ref.read(installerZonesProvider.notifier).setPrimary(zone.name, ip);
                setState(() => _validationError = null);
              }
            },
          ),
          const SizedBox(height: 16),

          // Secondary controllers
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Secondary Controllers',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...zoneControllers
                  .where((c) => c.ip != zone.primaryIp)
                  .map((c) => Chip(
                        label: Text(c.name ?? c.ip),
                        labelStyle: const TextStyle(color: Colors.white),
                        backgroundColor: NexGenPalette.matteBlack,
                        deleteIcon: const Icon(Icons.close, size: 18),
                        deleteIconColor: NexGenPalette.textMedium,
                        onDeleted: () {
                          ref.read(installerZonesProvider.notifier).removeMember(zone.name, c.ip);
                        },
                      )),
              // Add button
              ActionChip(
                avatar: const Icon(Icons.add, size: 18, color: NexGenPalette.cyan),
                label: const Text('Add', style: TextStyle(color: NexGenPalette.cyan)),
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: NexGenPalette.cyan),
                onPressed: () => _showAddSecondaryDialog(zone, controllers),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // DDP sync toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DDP Sync',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sync effects across all controllers in this zone',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: zone.ddpSyncEnabled,
                onChanged: (value) {
                  ref.read(installerZonesProvider.notifier).setDdpEnabled(zone.name, value);
                },
                activeColor: NexGenPalette.cyan,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddZoneDialog(List<ControllerInfo> controllers) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Create Zone', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Zone Name',
            labelStyle: const TextStyle(color: NexGenPalette.textMedium),
            hintText: 'e.g., Front Building, Parking Lot',
            hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
            filled: true,
            fillColor: NexGenPalette.matteBlack,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                ref.read(installerZonesProvider.notifier).addZone(
                      ZoneModel(
                        name: name,
                        primaryIp: null,
                        members: [],
                      ),
                    );
                Navigator.pop(context);
                setState(() => _validationError = null);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
            child: const Text('Create', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showAddSecondaryDialog(ZoneModel zone, List<ControllerInfo> controllers) {
    // Get controllers not in this zone (excluding primary)
    final available = controllers
        .where((c) => !zone.members.contains(c.ip))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available controllers to add')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Secondary Controller',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ...available.map((c) => ListTile(
                  leading: const Icon(Icons.router, color: NexGenPalette.cyan),
                  title: Text(c.name ?? 'Unnamed', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(c.ip, style: const TextStyle(color: NexGenPalette.textMedium)),
                  onTap: () {
                    ref.read(installerZonesProvider.notifier).addMember(zone.name, c.ip);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: Colors.orange.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Controllers Selected',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Go back to Controller Setup to select controllers first.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
