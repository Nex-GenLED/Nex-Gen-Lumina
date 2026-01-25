import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/analytics/analytics_providers.dart';
import 'package:nexgen_command/models/analytics_models.dart';
import 'package:nexgen_command/widgets/pattern_request_dialog.dart';

/// Screen displaying trending patterns and community requests
class TrendingPatternsScreen extends ConsumerWidget {
  const TrendingPatternsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const GlassAppBar(
          title: Text('Pattern Trends'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Trending', icon: Icon(Icons.trending_up)),
              Tab(text: 'Requested', icon: Icon(Icons.lightbulb_outline)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TrendingTab(),
            _RequestedTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => PatternRequestDialog.show(context),
          icon: const Icon(Icons.add),
          label: const Text('Request Pattern'),
          backgroundColor: NexGenPalette.cyan,
          foregroundColor: Colors.black,
        ),
      ),
    );
  }
}

/// Tab showing trending patterns
class _TrendingTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingPatternsProvider);

    return trendingAsync.when(
      data: (patterns) {
        if (patterns.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.trending_up, size: 48, color: Colors.white38),
                const SizedBox(height: 16),
                Text(
                  'No trending data yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Start using patterns to see trends',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: patterns.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final pattern = patterns[index];
            return _TrendingPatternCard(pattern: pattern, rank: index + 1);
          },
        );
      },
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Failed to load trending patterns',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Card displaying a trending pattern
class _TrendingPatternCard extends StatelessWidget {
  final GlobalPatternStats pattern;
  final int rank;

  const _TrendingPatternCard({required this.pattern, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: rank <= 3
                      ? [NexGenPalette.gold, NexGenPalette.gold.withValues(alpha: 0.6)]
                      : [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.6)],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Pattern info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern.patternName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.people_outline, size: 14, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text(
                        '${pattern.uniqueUsers} users',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.play_circle_outline, size: 14, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text(
                        '${pattern.totalApplications} uses',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                      ),
                    ],
                  ),
                  if (pattern.last30DaysGrowth > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 14,
                          color: Colors.green.shade300,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(pattern.last30DaysGrowth * 100).toStringAsFixed(0)}% growth',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.green.shade300,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // New badge
            if (pattern.isNew)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.cyan),
                ),
                child: Text(
                  'NEW',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: NexGenPalette.cyan,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tab showing most requested patterns
class _RequestedTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(mostRequestedPatternsProvider);

    return requestsAsync.when(
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lightbulb_outline, size: 48, color: Colors.white38),
                const SizedBox(height: 16),
                Text(
                  'No pattern requests yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Be the first to request a pattern!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final request = requests[index];
            return _PatternRequestCard(request: request);
          },
        );
      },
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Failed to load pattern requests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Card displaying a pattern request
class _PatternRequestCard extends ConsumerWidget {
  final PatternRequest request;

  const _PatternRequestCard({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.requestedTheme,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (request.suggestedCategory != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NexGenPalette.line),
                    ),
                    child: Text(
                      request.suggestedCategory!,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            if (request.description != null) ...[
              const SizedBox(height: 8),
              Text(
                request.description!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                // Vote count
                Row(
                  children: [
                    Icon(Icons.thumb_up_outlined, size: 16, color: NexGenPalette.gold),
                    const SizedBox(width: 4),
                    Text(
                      '${request.voteCount} ${request.voteCount == 1 ? 'vote' : 'votes'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NexGenPalette.gold,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const Spacer(),
                // Vote button
                FilledButton.icon(
                  onPressed: () async {
                    final notifier = ref.read(patternRequestNotifierProvider.notifier);
                    await notifier.voteForRequest(request.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vote recorded!')),
                      );
                    }
                  },
                  icon: const Icon(Icons.thumb_up, size: 16),
                  label: const Text('Vote'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                    foregroundColor: NexGenPalette.cyan,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
