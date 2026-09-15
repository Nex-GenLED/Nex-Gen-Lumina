import 'package:flutter/material.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';
import 'package:nexgen_command/theme.dart';

/// #114: which path the MOST RECENT routed controller command took.
///
/// Driven by [RoutingDiagnostics.currentPath], which is set only when a
/// command actually leaves the app — never by the connectivity check's
/// opinion. Hidden until the first routed command of the session. Tap for
/// the recent records and the inputs of the latest network check.
class RoutePathBadge extends StatelessWidget {
  const RoutePathBadge({super.key, this.diagnostics});

  /// Injected in tests; defaults to [RoutingDiagnostics.instance].
  final RoutingDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final diag = diagnostics ?? RoutingDiagnostics.instance;
    return ValueListenableBuilder<RoutePath?>(
      valueListenable: diag.currentPath,
      builder: (context, path, _) {
        if (path == null) return const SizedBox.shrink();
        final direct = path == RoutePath.direct;
        final color = direct ? Colors.greenAccent : NexGenPalette.cyan;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: direct
                ? 'Last command went directly to your controller'
                : 'Last command went through the bridge',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showRoutingDecisionsSheet(context, diag),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      direct ? Icons.home_rounded : Icons.cloud_rounded,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      direct ? 'Direct' : 'Via Bridge',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _yesNo(bool? value) => value == null ? '—' : (value ? 'yes' : 'no');

String _two(int n) => n.toString().padLeft(2, '0');

String _clock(DateTime t) {
  final local = t.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

/// One line describing what a connectivity check saw and decided.
String describeConnectivityCheck(ConnectivityCheckSnapshot check) =>
    'Wi-Fi reported: ${_yesNo(check.wifiReported)} · '
    'Name readable: ${_yesNo(check.ssidReadable)} · '
    'Matched home: ${_yesNo(check.ssidMatched)} → '
    '${check.outcome} (${check.reason})';

Future<void> showRoutingDecisionsSheet(
  BuildContext context,
  RoutingDiagnostics diag,
) {
  final records = diag.recent.take(20).toList();
  final check = diag.lastCheck;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: NexGenPalette.gunmetal90,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Command routing',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              check == null
                  ? 'No network check recorded yet.'
                  : 'Latest network check (${_clock(check.checkedAt)}): '
                      '${describeConnectivityCheck(check)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in records)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_clock(r.at)}  '
                            '${r.path == RoutePath.direct ? 'Direct' : 'Via Bridge'}'
                            '  ${r.command}',
                            style: TextStyle(
                              color: r.path == RoutePath.direct
                                  ? Colors.greenAccent
                                  : NexGenPalette.cyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (r.check != null)
                            Text(
                              describeConnectivityCheck(r.check!),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
