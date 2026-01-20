import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Enhanced connection quality states
enum ConnectionQuality {
  /// Fully connected with fast response times
  excellent,

  /// Connected but experiencing some latency
  good,

  /// Connected but slow response times
  slow,

  /// Actively trying to reconnect
  reconnecting,

  /// No connection to the device
  offline,

  /// Using cloud relay (remote mode)
  remote,
}

/// Provider for connection quality assessment
final connectionQualityProvider = Provider<ConnectionQuality>((ref) {
  final wledState = ref.watch(wledStateProvider);
  final isRemote = ref.watch(isRemoteModeProvider);
  final latency = ref.watch(connectionLatencyProvider);

  // If using remote/cloud mode
  if (isRemote) {
    return ConnectionQuality.remote;
  }

  // If not connected
  if (!wledState.connected) {
    // Simple heuristic: if we were recently connected, we're reconnecting
    return ConnectionQuality.reconnecting;
  }

  // Assess quality based on latency
  if (latency == null) {
    return ConnectionQuality.good; // Unknown latency, assume good
  }

  if (latency < 100) {
    return ConnectionQuality.excellent;
  } else if (latency < 300) {
    return ConnectionQuality.good;
  } else {
    return ConnectionQuality.slow;
  }
});

/// Provider to track connection latency (response time in ms)
final connectionLatencyProvider = StateProvider<int?>((ref) => null);

/// Compact connection status indicator for the app bar
class ConnectionStatusIndicator extends ConsumerStatefulWidget {
  final bool showLabel;
  final bool compact;

  const ConnectionStatusIndicator({
    super.key,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  ConsumerState<ConnectionStatusIndicator> createState() => _ConnectionStatusIndicatorState();
}

class _ConnectionStatusIndicatorState extends ConsumerState<ConnectionStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quality = ref.watch(connectionQualityProvider);
    final wledState = ref.watch(wledStateProvider);

    // Manage animation based on state
    if (quality == ConnectionQuality.reconnecting) {
      _pulseController.repeat(reverse: true);
    } else if (quality == ConnectionQuality.excellent || quality == ConnectionQuality.good) {
      // Subtle pulse for connected state
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }

    final config = _getStatusConfig(quality, wledState.connected);

    if (widget.compact) {
      return _buildCompactIndicator(config);
    }

    return _buildFullIndicator(config, quality);
  }

  Widget _buildCompactIndicator(_StatusConfig config) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: config.color.withValues(alpha: _pulseAnimation.value),
            boxShadow: [
              BoxShadow(
                color: config.color.withValues(alpha: 0.4 * _pulseAnimation.value),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFullIndicator(_StatusConfig config, ConnectionQuality quality) {
    return GestureDetector(
      onTap: () => _showConnectionDetails(context, quality),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: config.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: config.color.withValues(alpha: 0.3 * _pulseAnimation.value),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: config.color.withValues(alpha: _pulseAnimation.value),
                    boxShadow: [
                      BoxShadow(
                        color: config.color.withValues(alpha: 0.5 * _pulseAnimation.value),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),

                if (widget.showLabel) ...[
                  const SizedBox(width: 8),

                  // Status icon
                  Icon(
                    config.icon,
                    color: config.color,
                    size: 14,
                  ),
                  const SizedBox(width: 4),

                  // Status text
                  Text(
                    config.label,
                    style: TextStyle(
                      color: config.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],

                // Loading spinner for reconnecting
                if (quality == ConnectionQuality.reconnecting) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(config.color),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showConnectionDetails(BuildContext context, ConnectionQuality quality) {
    final latency = ref.read(connectionLatencyProvider);
    final isRemote = ref.read(isRemoteModeProvider);
    final wledState = ref.read(wledStateProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConnectionDetailsSheet(
        quality: quality,
        latency: latency,
        isRemote: isRemote,
        isConnected: wledState.connected,
        onRetry: () {
          Navigator.pop(ctx);
          // Force refresh by invalidating the provider
          ref.invalidate(wledStateProvider);
        },
      ),
    );
  }

  _StatusConfig _getStatusConfig(ConnectionQuality quality, bool isConnected) {
    switch (quality) {
      case ConnectionQuality.excellent:
        return _StatusConfig(
          color: const Color(0xFF00E676), // Bright green
          icon: Icons.wifi,
          label: 'Connected',
        );
      case ConnectionQuality.good:
        return _StatusConfig(
          color: NexGenPalette.cyan,
          icon: Icons.wifi,
          label: 'Connected',
        );
      case ConnectionQuality.slow:
        return _StatusConfig(
          color: const Color(0xFFFFB74D), // Amber
          icon: Icons.wifi_2_bar,
          label: 'Slow',
        );
      case ConnectionQuality.reconnecting:
        return _StatusConfig(
          color: const Color(0xFFFFB74D), // Amber
          icon: Icons.sync,
          label: 'Reconnecting',
        );
      case ConnectionQuality.offline:
        return _StatusConfig(
          color: const Color(0xFFEF5350), // Red
          icon: Icons.wifi_off,
          label: 'Offline',
        );
      case ConnectionQuality.remote:
        return _StatusConfig(
          color: NexGenPalette.violet,
          icon: Icons.cloud,
          label: 'Remote',
        );
    }
  }
}

class _StatusConfig {
  final Color color;
  final IconData icon;
  final String label;

  _StatusConfig({
    required this.color,
    required this.icon,
    required this.label,
  });
}

/// Bottom sheet showing detailed connection information
class _ConnectionDetailsSheet extends StatelessWidget {
  final ConnectionQuality quality;
  final int? latency;
  final bool isRemote;
  final bool isConnected;
  final VoidCallback onRetry;

  const _ConnectionDetailsSheet({
    required this.quality,
    required this.latency,
    required this.isRemote,
    required this.isConnected,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Row(
                children: [
                  Icon(
                    _getQualityIcon(),
                    color: _getQualityColor(),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connection Status',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getQualityDescription(),
                        style: TextStyle(
                          color: _getQualityColor(),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Details
              _buildDetailRow(
                'Mode',
                isRemote ? 'Cloud Relay' : 'Direct (Local)',
                isRemote ? Icons.cloud : Icons.wifi,
              ),

              if (latency != null)
                _buildDetailRow(
                  'Response Time',
                  '${latency}ms',
                  Icons.speed,
                ),

              _buildDetailRow(
                'System State',
                isConnected ? 'Responsive' : 'Not Responding',
                isConnected ? Icons.check_circle : Icons.error,
              ),

              const SizedBox(height: 24),

              // Help text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getHelpText(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Retry button for offline state
              if (!isConnected) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Connection'),
                    style: FilledButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getQualityIcon() {
    switch (quality) {
      case ConnectionQuality.excellent:
      case ConnectionQuality.good:
        return Icons.wifi;
      case ConnectionQuality.slow:
        return Icons.wifi_2_bar;
      case ConnectionQuality.reconnecting:
        return Icons.sync;
      case ConnectionQuality.offline:
        return Icons.wifi_off;
      case ConnectionQuality.remote:
        return Icons.cloud;
    }
  }

  Color _getQualityColor() {
    switch (quality) {
      case ConnectionQuality.excellent:
        return const Color(0xFF00E676);
      case ConnectionQuality.good:
        return NexGenPalette.cyan;
      case ConnectionQuality.slow:
      case ConnectionQuality.reconnecting:
        return const Color(0xFFFFB74D);
      case ConnectionQuality.offline:
        return const Color(0xFFEF5350);
      case ConnectionQuality.remote:
        return NexGenPalette.violet;
    }
  }

  String _getQualityDescription() {
    switch (quality) {
      case ConnectionQuality.excellent:
        return 'Excellent Connection';
      case ConnectionQuality.good:
        return 'Good Connection';
      case ConnectionQuality.slow:
        return 'Slow Connection';
      case ConnectionQuality.reconnecting:
        return 'Reconnecting...';
      case ConnectionQuality.offline:
        return 'System Offline';
      case ConnectionQuality.remote:
        return 'Connected via Cloud';
    }
  }

  String _getHelpText() {
    switch (quality) {
      case ConnectionQuality.excellent:
      case ConnectionQuality.good:
        return 'Your lighting system is responding normally. Commands will be applied instantly.';
      case ConnectionQuality.slow:
        return 'Connection is slower than usual. Commands may take a moment to apply. Check your WiFi signal strength.';
      case ConnectionQuality.reconnecting:
        return 'Temporarily lost connection to your lighting system. Attempting to reconnect automatically.';
      case ConnectionQuality.offline:
        return 'Cannot reach your lighting system. Check that your controller is powered on and connected to WiFi.';
      case ConnectionQuality.remote:
        return 'You\'re connected via cloud relay. Commands are sent securely through the internet.';
    }
  }
}

/// Simple status badge for inline use (e.g., in pattern display)
class ConnectionStatusBadge extends ConsumerWidget {
  const ConnectionStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = ref.watch(connectionQualityProvider);

    if (quality == ConnectionQuality.excellent || quality == ConnectionQuality.good) {
      return const SizedBox.shrink(); // Hide when connected normally
    }

    Color color;
    String text;
    IconData icon;

    switch (quality) {
      case ConnectionQuality.slow:
        color = const Color(0xFFFFB74D);
        text = 'Slow Connection';
        icon = Icons.wifi_2_bar;
        break;
      case ConnectionQuality.reconnecting:
        color = const Color(0xFFFFB74D);
        text = 'Reconnecting...';
        icon = Icons.sync;
        break;
      case ConnectionQuality.offline:
        color = const Color(0xFFEF5350);
        text = 'System Offline';
        icon = Icons.wifi_off;
        break;
      case ConnectionQuality.remote:
        color = NexGenPalette.violet;
        text = 'Remote Mode';
        icon = Icons.cloud;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
