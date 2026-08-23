import 'package:flutter/material.dart';

class GlowingBusMarker extends StatelessWidget {
  final bool isStale;
  
  const GlowingBusMarker({super.key, this.isStale = false});

  @override
  Widget build(BuildContext context) {
    final glowColor = isStale ? Colors.redAccent : Colors.greenAccent;
    final baseColor = isStale ? const Color(0xFFFF4444) : const Color(0xFFFFD700);
    final highlightColor = isStale ? const Color(0xFFFF8888) : const Color(0xFFFFF7A1);
    final shadowColor = isStale ? const Color(0xFFAA0000) : const Color(0xFFE6B800);
    return Transform.rotate(
      angle: 0.5, // Slight tilt for perspective
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 1. Static Beautiful Green Glow (No Animation = No Lag)
            Container(
              width: 50,
              height: 100,
              decoration: BoxDecoration(
                color: glowColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.6),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
            
            // 2. The Static 3D Realistic Yellow Bus (Or Red if stale)
            Container(
              width: 45,
              height: 110,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  // Core Shadow for 3D depth
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(4, 4),
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    highlightColor,
                    baseColor,
                    shadowColor,
                  ],
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Roof Details
                  Positioned(
                    top: 10,
                    left: 5,
                    right: 5,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  
                  // Front Windshield
                  Positioned(
                    top: 25,
                    left: 4,
                    right: 4,
                    child: Container(
                      height: 15,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B), // Deep Glass Blue/Black
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black87, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.3),
                            blurRadius: 2,
                            offset: const Offset(1, 1), // Glass reflection
                          )
                        ],
                      ),
                    ),
                  ),

                  // Side Windows (Left)
                  Positioned(
                    top: 45,
                    left: 2,
                    bottom: 10,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(4, (index) => _buildWindow()),
                    ),
                  ),

                  // Side Windows (Right)
                  Positioned(
                    top: 45,
                    right: 2,
                    bottom: 10,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(4, (index) => _buildWindow()),
                    ),
                  ),

                  // Wheels
                  Positioned(top: 20, left: -4, child: _buildWheel()),
                  Positioned(top: 20, right: -4, child: _buildWheel()),
                  Positioned(bottom: 20, left: -4, child: _buildWheel()),
                  Positioned(bottom: 20, right: -4, child: _buildWheel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindow() {
    return Container(
      width: 6,
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.black87, width: 1),
      ),
    );
  }

  Widget _buildWheel() {
    return Container(
      width: 8,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 2,
            offset: const Offset(1, 1),
          ),
        ],
      ),
    );
  }
}
