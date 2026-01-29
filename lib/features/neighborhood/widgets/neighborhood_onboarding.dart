import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';

/// Engaging onboarding experience for users with no sync groups.
/// Shows what Neighborhood Sync can do and encourages participation.
class NeighborhoodOnboarding extends ConsumerStatefulWidget {
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;
  final VoidCallback onFindNearby;

  const NeighborhoodOnboarding({
    super.key,
    required this.onCreateGroup,
    required this.onJoinGroup,
    required this.onFindNearby,
  });

  @override
  ConsumerState<NeighborhoodOnboarding> createState() =>
      _NeighborhoodOnboardingState();
}

class _NeighborhoodOnboardingState extends ConsumerState<NeighborhoodOnboarding>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _pulseController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black,
            NexGenPalette.midnightBlue.withOpacity(0.8),
            Colors.black,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildSyncModesPage(),
                  _buildUseCasesPage(),
                  _buildGetStartedPage(),
                ],
              ),
            ),

            // Page indicators
            _buildPageIndicators(),

            const SizedBox(height: 16),

            // Action buttons
            _buildActionButtons(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Animated hero visual
          _buildAnimatedHero(),

          const SizedBox(height: 32),

          // Title with gradient
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                NexGenPalette.cyan,
                Colors.white,
                NexGenPalette.violet,
              ],
            ).createShader(bounds),
            child: const Text(
              'Neighborhood Sync',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'The Street Comes Alive',
            style: TextStyle(
              fontSize: 18,
              color: NexGenPalette.cyan.withOpacity(0.9),
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Imagine your entire street lighting up in perfect harmony. '
            'Colors flowing from home to home like a wave. '
            'Synchronized celebrations that turn heads and bring neighbors together.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade300,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 32),

          // Feature highlights
          _buildFeatureChip(
            Icons.bolt,
            'Real-Time Sync',
            'Lights move together instantly',
          ),
          const SizedBox(height: 12),
          _buildFeatureChip(
            Icons.calendar_month,
            'Scheduled Shows',
            'Plan epic displays for any occasion',
          ),
          const SizedBox(height: 12),
          _buildFeatureChip(
            Icons.palette,
            'Complementary Colors',
            'Each home shows a unique part of the theme',
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedHero() {
    return SizedBox(
      height: 180,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _waveController]),
        builder: (context, child) {
          return CustomPaint(
            size: const Size(double.infinity, 180),
            painter: _NeighborhoodHeroPainter(
              pulseValue: _pulseController.value,
              waveValue: _waveController.value,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: NexGenPalette.cyan.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: NexGenPalette.cyan, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncModesPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),

          Center(
            child: Icon(
              Icons.tune,
              size: 48,
              color: NexGenPalette.cyan.withOpacity(0.8),
            ),
          ),

          const SizedBox(height: 16),

          const Center(
            child: Text(
              'Four Ways to Sync',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Center(
            child: Text(
              'Choose your light show style',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade400,
              ),
            ),
          ),

          const SizedBox(height: 28),

          _buildSyncModeCard(
            'The Wave',
            'Sequential Flow',
            'Colors roll down the street like a wave, flowing from one home to the next. Perfect for creating that "wow" effect.',
            Icons.waves,
            [NexGenPalette.cyan, Colors.blue],
          ),

          const SizedBox(height: 16),

          _buildSyncModeCard(
            'The Pulse',
            'Simultaneous',
            'All homes light up together in perfect unison. Every color change happens at exactly the same moment.',
            Icons.favorite,
            [Colors.red, Colors.pink],
          ),

          const SizedBox(height: 16),

          _buildSyncModeCard(
            'The Match',
            'Pattern Match',
            'Everyone runs the same pattern independently. Great for when you want a unified look without precise timing.',
            Icons.sync_alt,
            [Colors.green, Colors.teal],
          ),

          const SizedBox(height: 16),

          _buildSyncModeCard(
            'The Complement',
            'Color Harmony',
            'Each home displays a different color from the theme. Together, you create a living rainbow.',
            Icons.palette,
            [Colors.purple, NexGenPalette.violet],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSyncModeCard(
    String nickname,
    String title,
    String description,
    IconData icon,
    List<Color> gradientColors,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gradientColors[0].withOpacity(0.15),
            gradientColors[1].withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: gradientColors[0].withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradientColors),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      nickname,
                      style: TextStyle(
                        color: gradientColors[0],
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUseCasesPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),

          const Text(
            'Perfect For...',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 28),

          _buildUseCaseCard(
            'Holiday Magic',
            'Christmas, Halloween, 4th of July - create neighborhood-wide displays that make everyone stop and stare.',
            '🎄',
            NexGenPalette.cyan,
          ),

          const SizedBox(height: 16),

          _buildUseCaseCard(
            'Game Day Glory',
            'Rep your team colors with the whole block. When they score, the street celebrates together.',
            '🏈',
            Colors.orange,
          ),

          const SizedBox(height: 16),

          _buildUseCaseCard(
            'Celebrations',
            'Birthdays, graduations, new babies - turn ordinary moments into unforgettable light shows.',
            '🎉',
            Colors.pink,
          ),

          const SizedBox(height: 16),

          _buildUseCaseCard(
            'Community Events',
            'Block parties, neighborhood nights, charity events - bring everyone together with light.',
            '🏘️',
            Colors.green,
          ),

          const SizedBox(height: 16),

          _buildUseCaseCard(
            'Just Because',
            'Sometimes you just want to make your street the coolest one in town. No occasion needed.',
            '✨',
            NexGenPalette.violet,
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildUseCaseCard(
    String title,
    String description,
    String emoji,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGetStartedPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // Animated glow circle
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      NexGenPalette.cyan.withOpacity(0.3 + _pulseController.value * 0.2),
                      NexGenPalette.cyan.withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: NexGenPalette.cyan.withOpacity(0.3 + _pulseController.value * 0.2),
                      blurRadius: 30 + _pulseController.value * 10,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.celebration,
                  size: 56,
                  color: Colors.white,
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          const Text(
            'Ready to Light Up\nYour Street?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'Getting started is easy. Create a new group or join one that\'s already syncing nearby.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 40),

          // Quick setup steps
          _buildSetupStep(
            1,
            'Create or Join',
            'Start a new sync group or enter an invite code',
          ),
          const SizedBox(height: 16),
          _buildSetupStep(
            2,
            'Configure Your Home',
            'Set your LED count and position on the street',
          ),
          const SizedBox(height: 16),
          _buildSetupStep(
            3,
            'Sync & Celebrate',
            'Pick a pattern and watch the magic happen',
          ),

          const SizedBox(height: 40),

          // Tips callout
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NexGenPalette.cyan.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: NexGenPalette.cyan,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pro tip: Share your invite code via text or social media to grow your group quickly!',
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSetupStep(int number, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [NexGenPalette.cyan, NexGenPalette.blue],
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? NexGenPalette.cyan : Colors.grey.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildActionButtons() {
    final isLastPage = _currentPage == 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Primary CTA - changes based on page
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isLastPage ? widget.onCreateGroup : _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 8,
                shadowColor: NexGenPalette.cyan.withOpacity(0.4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isLastPage ? Icons.add_circle_outline : Icons.arrow_forward,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isLastPage ? 'Start a Block Party' : 'Next',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Secondary action - only show on last page
          if (isLastPage) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onJoinGroup,
                icon: const Icon(Icons.login),
                label: const Text('Join the Party'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexGenPalette.cyan,
                  side: const BorderSide(color: NexGenPalette.cyan),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            TextButton.icon(
              onPressed: widget.onFindNearby,
              icon: Icon(Icons.explore, color: Colors.grey.shade400, size: 18),
              label: Text(
                'Discover Nearby Groups',
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ] else ...[
            // Skip button for intro pages
            TextButton(
              onPressed: () => _pageController.animateToPage(
                3,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
              child: Text(
                'Skip to Get Started',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
}

/// Custom painter for the animated hero visualization
class _NeighborhoodHeroPainter extends CustomPainter {
  final double pulseValue;
  final double waveValue;

  _NeighborhoodHeroPainter({
    required this.pulseValue,
    required this.waveValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final housePaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    // Draw 5 houses with animated lights
    final houseWidth = size.width / 7;
    final houseSpacing = houseWidth * 1.4;
    final startX = (size.width - (houseSpacing * 4 + houseWidth)) / 2;

    for (int i = 0; i < 5; i++) {
      final x = startX + i * houseSpacing;
      final y = size.height * 0.6;

      // Calculate color based on wave position
      final waveOffset = (waveValue + i * 0.2) % 1.0;
      final hue = (waveOffset * 360) % 360;
      final lightColor = HSVColor.fromAHSV(1, hue, 0.8, 1).toColor();

      // Glow behind house
      final glowOpacity = 0.3 + pulseValue * 0.2;
      glowPaint.color = lightColor.withOpacity(glowOpacity);
      canvas.drawCircle(
        Offset(x + houseWidth / 2, y - 10),
        houseWidth * 0.8,
        glowPaint,
      );

      // House body
      housePaint.color = const Color(0xFF2A2A2A);
      final houseRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, houseWidth, houseWidth * 0.8),
        const Radius.circular(4),
      );
      canvas.drawRRect(houseRect, housePaint);

      // Roof
      final roofPath = Path()
        ..moveTo(x - 4, y)
        ..lineTo(x + houseWidth / 2, y - houseWidth * 0.5)
        ..lineTo(x + houseWidth + 4, y)
        ..close();
      housePaint.color = const Color(0xFF3A3A3A);
      canvas.drawPath(roofPath, housePaint);

      // Roofline lights
      housePaint.color = lightColor;
      const lightRadius = 3.0;
      const numLights = 8;
      for (int l = 0; l < numLights; l++) {
        final t = l / (numLights - 1);
        final lx = x - 2 + t * (houseWidth + 4);
        // Calculate Y position along the roofline
        final roofY = y - (1 - (2 * t - 1).abs()) * houseWidth * 0.5;
        canvas.drawCircle(Offset(lx, roofY + 2), lightRadius, housePaint);
      }

      // Window
      housePaint.color = const Color(0xFF1A1A1A);
      canvas.drawRect(
        Rect.fromLTWH(
          x + houseWidth * 0.3,
          y + houseWidth * 0.2,
          houseWidth * 0.4,
          houseWidth * 0.35,
        ),
        housePaint,
      );
    }

    // Draw wave line connecting houses
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = LinearGradient(
        colors: [
          NexGenPalette.cyan,
          NexGenPalette.violet,
          NexGenPalette.cyan,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final wavePath = Path();
    for (int x = 0; x < size.width.toInt(); x++) {
      final normalizedX = x / size.width;
      final waveY = size.height * 0.35 +
          math.sin((normalizedX * 4 + waveValue * 2) * math.pi) * 15;

      if (x == 0) {
        wavePath.moveTo(x.toDouble(), waveY);
      } else {
        wavePath.lineTo(x.toDouble(), waveY);
      }
    }
    canvas.drawPath(wavePath, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _NeighborhoodHeroPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.waveValue != waveValue;
  }
}

/// Compact error state widget with helpful messaging
class NeighborhoodErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onCreateGroup;
  final String? errorMessage;

  const NeighborhoodErrorState({
    super.key,
    required this.onRetry,
    required this.onCreateGroup,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: Colors.orange.shade300,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Having Trouble Connecting',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              errorMessage ??
                  'We couldn\'t load your sync groups right now. This might be a temporary network issue.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: onCreateGroup,
              child: Text(
                'Or start fresh with a new group',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
