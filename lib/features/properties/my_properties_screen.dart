import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/properties/property_models.dart';
import 'package:nexgen_command/features/properties/properties_providers.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';

/// Screen for managing multiple properties (homes, vacation houses, etc.)
class MyPropertiesScreen extends ConsumerWidget {
  const MyPropertiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertiesAsync = ref.watch(userPropertiesProvider);
    final selectedProperty = ref.watch(selectedPropertyProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('My Properties'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Property',
            onPressed: () => _showAddPropertyDialog(context, ref),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              NexGenPalette.midnightBlue,
              NexGenPalette.matteBlack,
            ],
          ),
        ),
        child: SafeArea(
          child: propertiesAsync.when(
            data: (properties) {
              if (properties.isEmpty) {
                return _EmptyState(
                  onAddProperty: () => _showAddPropertyDialog(context, ref),
                );
              }
              return _PropertiesList(
                properties: properties,
                selectedId: selectedProperty?.id,
                onSelect: (property) => _selectProperty(ref, property),
                onEdit: (property) => _showEditPropertyDialog(context, ref, property),
                onDelete: (property) => _confirmDeleteProperty(context, ref, property),
                onSetPrimary: (property) => _setPrimaryProperty(ref, property),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading properties',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(userPropertiesProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPropertyDialog(context, ref),
        backgroundColor: NexGenPalette.cyan,
        icon: const Icon(Icons.add_home),
        label: const Text('Add Property'),
      ),
    );
  }

  void _selectProperty(WidgetRef ref, Property property) {
    ref.read(selectPropertyProvider)(property.id);
  }

  void _setPrimaryProperty(WidgetRef ref, Property property) async {
    final manager = ref.read(propertyManagerProvider);
    await manager.setPrimaryProperty(property.id);
  }

  void _showAddPropertyDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => _PropertyDialog(
        title: 'Add Property',
        onSave: (name, address, iconName) async {
          final manager = ref.read(propertyManagerProvider);
          final property = await manager.createProperty(
            name: name,
            address: address,
            iconName: iconName,
          );
          if (property != null && context.mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created "$name"'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  void _showEditPropertyDialog(BuildContext context, WidgetRef ref, Property property) {
    showDialog(
      context: context,
      builder: (context) => _PropertyDialog(
        title: 'Edit Property',
        initialName: property.name,
        initialAddress: property.address,
        initialIconName: property.iconName,
        onSave: (name, address, iconName) async {
          final manager = ref.read(propertyManagerProvider);
          final success = await manager.updateProperty(
            property.copyWith(
              name: name,
              address: address,
              iconName: iconName,
            ),
          );
          if (success && context.mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Updated "$name"'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  void _confirmDeleteProperty(BuildContext context, WidgetRef ref, Property property) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete Property?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${property.name}"? This will unlink all controllers associated with this property.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final manager = ref.read(propertyManagerProvider);
              final success = await manager.deleteProperty(property.id);
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${property.name}"'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddProperty;

  const _EmptyState({required this.onAddProperty});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.home_work_outlined,
              size: 80,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No Properties Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add your first property to organize your lighting systems across multiple locations.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAddProperty,
              icon: const Icon(Icons.add_home),
              label: const Text('Add Your First Property'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertiesList extends StatelessWidget {
  final List<Property> properties;
  final String? selectedId;
  final Function(Property) onSelect;
  final Function(Property) onEdit;
  final Function(Property) onDelete;
  final Function(Property) onSetPrimary;

  const _PropertiesList({
    required this.properties,
    this.selectedId,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onSetPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: properties.length,
      itemBuilder: (context, index) {
        final property = properties[index];
        final isSelected = property.id == selectedId;

        return _PropertyCard(
          property: property,
          isSelected: isSelected,
          onTap: () => onSelect(property),
          onEdit: () => onEdit(property),
          onDelete: () => onDelete(property),
          onSetPrimary: property.isPrimary ? null : () => onSetPrimary(property),
        );
      },
    );
  }
}

class _PropertyCard extends StatelessWidget {
  final Property property;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSetPrimary;

  const _PropertyCard({
    required this.property,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onSetPrimary,
  });

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'villa':
        return Icons.villa;
      case 'cottage':
        return Icons.cottage;
      case 'apartment':
        return Icons.apartment;
      case 'cabin':
        return Icons.cabin;
      case 'beach_access':
        return Icons.beach_access;
      case 'landscape':
        return Icons.landscape;
      case 'pool':
        return Icons.pool;
      case 'business':
        return Icons.business;
      case 'storefront':
        return Icons.storefront;
      case 'home':
      default:
        return Icons.home;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected
          ? NexGenPalette.cyan.withValues(alpha: 0.15)
          : NexGenPalette.gunmetal90,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: NexGenPalette.cyan, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? NexGenPalette.cyan.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getIcon(property.iconName),
                      color: isSelected ? NexGenPalette.cyan : Colors.white70,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                property.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (property.isPrimary)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: NexGenPalette.cyan.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'PRIMARY',
                                  style: TextStyle(
                                    color: NexGenPalette.cyan,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (property.address != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            property.address!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          '${property.controllerIds.length} controller${property.controllerIds.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Selection indicator
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: NexGenPalette.cyan,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Actions row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onSetPrimary != null)
                    TextButton.icon(
                      onPressed: onSetPrimary,
                      icon: const Icon(Icons.star_outline, size: 18),
                      label: const Text('Set Primary'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.amber,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialAddress;
  final String? initialIconName;
  final Future<void> Function(String name, String? address, String iconName) onSave;

  const _PropertyDialog({
    required this.title,
    this.initialName,
    this.initialAddress,
    this.initialIconName,
    required this.onSave,
  });

  @override
  State<_PropertyDialog> createState() => _PropertyDialogState();
}

class _PropertyDialogState extends State<_PropertyDialog> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late String _selectedIcon;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _addressController = TextEditingController(text: widget.initialAddress ?? '');
    _selectedIcon = widget.initialIconName ?? 'home';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'villa':
        return Icons.villa;
      case 'cottage':
        return Icons.cottage;
      case 'apartment':
        return Icons.apartment;
      case 'cabin':
        return Icons.cabin;
      case 'beach_access':
        return Icons.beach_access;
      case 'landscape':
        return Icons.landscape;
      case 'pool':
        return Icons.pool;
      case 'business':
        return Icons.business;
      case 'storefront':
        return Icons.storefront;
      case 'home':
      default:
        return Icons.home;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name field
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Property Name',
                hintText: 'e.g., Main Home, Lake House',
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.cyan),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            // Address field
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: 'Address (optional)',
                hintText: '123 Main St, City, State',
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.cyan),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            // Icon selection
            Text(
              'Icon',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PropertyIcons.options.map((option) {
                final isSelected = _selectedIcon == option.iconName;
                return InkWell(
                  onTap: () => setState(() => _selectedIcon = option.iconName),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? NexGenPalette.cyan.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: NexGenPalette.cyan, width: 2)
                          : null,
                    ),
                    child: Icon(
                      _getIcon(option.iconName),
                      color: isSelected ? NexGenPalette.cyan : Colors.white70,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving
              ? null
              : () async {
                  if (_nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a property name'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  setState(() => _isSaving = true);
                  await widget.onSave(
                    _nameController.text.trim(),
                    _addressController.text.trim().isEmpty
                        ? null
                        : _addressController.text.trim(),
                    _selectedIcon,
                  );
                  if (mounted) {
                    setState(() => _isSaving = false);
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: NexGenPalette.cyan,
            foregroundColor: Colors.black,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
