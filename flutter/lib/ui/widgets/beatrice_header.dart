import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Header matching the web app: settings gear on the left, centered
/// "Beatrice / Eburon AI" title, avatar on the right.
class BeatriceHeader extends StatelessWidget {
  final String? avatarInitials;
  final String? avatarImageUrl;
  final VoidCallback onSettingsTap;
  final VoidCallback onAvatarTap;

  const BeatriceHeader({
    super.key,
    this.avatarInitials,
    this.avatarImageUrl,
    required this.onSettingsTap,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Settings gear
          _IconButton(
            icon: Icons.settings,
            onTap: onSettingsTap,
          ),
          // Centered title
          Column(
            children: const [
              Text(
                'Beatrice',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'EBURON AI',
                style: TextStyle(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          // Avatar
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a1a),
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarImageUrl != null
                  ? Image.network(avatarImageUrl!, fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        avatarInitials ?? 'U',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFFdddddd),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 26, color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}