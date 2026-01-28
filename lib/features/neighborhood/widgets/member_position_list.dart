import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';

/// A drag-and-drop reorderable list for positioning homes in a neighborhood.
///
/// Members can be dragged to change their position in the animation sequence.
/// The visual representation shows homes in left-to-right order as they
/// would appear on a street.
class MemberPositionList extends ConsumerStatefulWidget {
  final List<NeighborhoodMember> members;
  final Function(List<String> orderedIds)? onReorder;
  final Function(NeighborhoodMember member)? onMemberTap;

  const MemberPositionList({
    super.key,
    required this.members,
    this.onReorder,
    this.onMemberTap,
  });

  @override
  ConsumerState<MemberPositionList> createState() => _MemberPositionListState();
}

class _MemberPositionListState extends ConsumerState<MemberPositionList> {
  late List<NeighborhoodMember> _orderedMembers;

  @override
  void initState() {
    super.initState();
    _orderedMembers = List.from(widget.members)
      ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));
  }

  @override
  void didUpdateWidget(MemberPositionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.members != oldWidget.members) {
      _orderedMembers = List.from(widget.members)
        ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _orderedMembers.removeAt(oldIndex);
      _orderedMembers.insert(newIndex, item);
    });

    // Notify parent of new order
    widget.onReorder?.call(_orderedMembers.map((m) => m.oderId).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Street visualization header
        _buildStreetVisualization(),
        const SizedBox(height: 16),

        // Reorderable member list
        _buildMemberList(),
      ],
    );
  }

  Widget _buildStreetVisualization() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Stack(
        children: [
          // Street line
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Direction arrow
          Positioned(
            left: 24,
            bottom: 24,
            child: Row(
              children: [
                Icon(
                  Icons.arrow_forward,
                  color: Colors.cyan.withOpacity(0.7),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'Animation flow',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // House icons positioned along the street
          Positioned(
            left: 20,
            right: 20,
            top: 8,
            bottom: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _orderedMembers.asMap().entries.map((entry) {
                final index = entry.key;
                final member = entry.value;
                final isOnline = member.isOnline;

                return Tooltip(
                  message: member.displayName,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? Colors.cyan.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isOnline ? Colors.cyan : Colors.grey,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.home,
                          size: 18,
                          color: isOnline ? Colors.cyan : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isOnline ? Colors.cyan : Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberList() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _orderedMembers.length,
      onReorder: _onReorder,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final double elevation = Tween<double>(begin: 0, end: 8)
                .animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOut,
                ))
                .value;
            return Material(
              elevation: elevation,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final member = _orderedMembers[index];
        return _MemberTile(
          key: ValueKey(member.oderId),
          member: member,
          position: index + 1,
          onTap: () => widget.onMemberTap?.call(member),
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  final NeighborhoodMember member;
  final int position;
  final VoidCallback? onTap;

  const _MemberTile({
    super.key,
    required this.member,
    required this.position,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Show participation status if not active, otherwise show online/offline
    final showParticipationStatus = member.participationStatus != MemberParticipationStatus.active;
    final syncStatus = member.isOnline
        ? MemberSyncStatus.online
        : MemberSyncStatus.offline;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Row(
              children: [
                // Drag handle
                ReorderableDragStartListener(
                  index: position - 1,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_handle,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),

                // Position number
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$position',
                      style: const TextStyle(
                        color: Colors.cyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Member info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _InfoChip(
                            icon: Icons.lightbulb_outline,
                            label: '${member.ledCount} LEDs',
                          ),
                          const SizedBox(width: 8),
                          _InfoChip(
                            icon: member.rooflineDirection.icon,
                            label: member.rooflineDirection.shortName,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Status indicator (participation or online status)
                if (showParticipationStatus)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: member.participationStatus.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          member.participationStatus == MemberParticipationStatus.paused
                              ? Icons.pause_circle_outline
                              : Icons.do_not_disturb,
                          size: 14,
                          color: member.participationStatus.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          member.participationStatus.displayName,
                          style: TextStyle(
                            color: member.participationStatus.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: syncStatus.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          syncStatus.icon,
                          size: 14,
                          color: syncStatus.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          syncStatus.displayName,
                          style: TextStyle(
                            color: syncStatus.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Colors.grey.shade500,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Dialog to edit member configuration (LED count, roofline length, display name).
class MemberConfigDialog extends ConsumerStatefulWidget {
  final NeighborhoodMember member;

  const MemberConfigDialog({
    super.key,
    required this.member,
  });

  @override
  ConsumerState<MemberConfigDialog> createState() => _MemberConfigDialogState();
}

class _MemberConfigDialogState extends ConsumerState<MemberConfigDialog> {
  late TextEditingController _nameController;
  late TextEditingController _ledCountController;
  late TextEditingController _rooflineController;
  late RooflineDirection _rooflineDirection;
  late MemberParticipationStatus _participationStatus;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member.displayName);
    _ledCountController = TextEditingController(text: '${widget.member.ledCount}');
    _rooflineController = TextEditingController(
      text: widget.member.rooflineMeters.toStringAsFixed(1),
    );
    _rooflineDirection = widget.member.rooflineDirection;
    _participationStatus = widget.member.participationStatus;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ledCountController.dispose();
    _rooflineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Edit Home Configuration',
        style: TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Display Name',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyan),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ledCountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'LED Count',
                hintText: 'e.g., 300',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                hintStyle: TextStyle(color: Colors.grey.shade700),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyan),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _rooflineController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Roofline Length (meters)',
                hintText: 'e.g., 15.0',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                hintStyle: TextStyle(color: Colors.grey.shade700),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyan),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Roofline Direction
            Text(
              'Roofline Direction',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'How do your LEDs run along your roofline?',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: RooflineDirection.values.map((direction) {
                  final isSelected = _rooflineDirection == direction;
                  return InkWell(
                    onTap: () => setState(() => _rooflineDirection = direction),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.cyan.withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            direction.icon,
                            color: isSelected ? Colors.cyan : Colors.grey.shade500,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  direction.displayName,
                                  style: TextStyle(
                                    color: isSelected ? Colors.cyan : Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _getDirectionDescription(direction),
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.cyan, size: 20),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Participation Status
            Text(
              'Sync Participation',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildStatusButton(MemberParticipationStatus.active),
                  _buildStatusButton(MemberParticipationStatus.paused),
                ],
              ),
            ),
            if (_participationStatus == MemberParticipationStatus.paused) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade300, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your home will skip group animations and run its own pattern.',
                        style: TextStyle(
                          color: Colors.orange.shade300,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyan,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildStatusButton(MemberParticipationStatus status) {
    final isSelected = _participationStatus == status;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _participationStatus = status),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? status.color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                status == MemberParticipationStatus.active
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
                color: isSelected ? status.color : Colors.grey.shade500,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                status.displayName,
                style: TextStyle(
                  color: isSelected ? status.color : Colors.grey.shade500,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDirectionDescription(RooflineDirection direction) {
    switch (direction) {
      case RooflineDirection.leftToRight:
        return 'First LED is on the left side';
      case RooflineDirection.rightToLeft:
        return 'First LED is on the right side';
      case RooflineDirection.centerOut:
        return 'First LEDs are in the center, expanding outward';
    }
  }

  void _save() {
    final updatedMember = widget.member.copyWith(
      displayName: _nameController.text.trim(),
      ledCount: int.tryParse(_ledCountController.text) ?? widget.member.ledCount,
      rooflineMeters: double.tryParse(_rooflineController.text) ?? widget.member.rooflineMeters,
      rooflineDirection: _rooflineDirection,
      participationStatus: _participationStatus,
    );

    ref.read(neighborhoodNotifierProvider.notifier).updateMember(updatedMember);
    Navigator.pop(context);
  }
}
