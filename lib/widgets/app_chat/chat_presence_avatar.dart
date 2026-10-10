import 'package:flutter/material.dart';

import '../user_profile_avatar.dart';

/// Avatar compatto con pallino online (verde) / offline (grigio).
class ChatPresenceAvatar extends StatelessWidget {
  const ChatPresenceAvatar({
    super.key,
    required this.initial,
    required this.online,
    this.fotoPath,
    this.radius = 14,
  });

  final String initial;
  final bool online;
  final String? fotoPath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dotSize = (radius * 0.55).clamp(7.0, 11.0);
    return SizedBox(
      width: radius * 2 + 2,
      height: radius * 2 + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          UserProfileAvatar(
            radius: radius,
            initial: initial,
            fotoPath: fotoPath,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0B1020)
                      : Colors.white,
                  width: 1.6,
                ),
                boxShadow: online
                    ? [
                        BoxShadow(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.55),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
