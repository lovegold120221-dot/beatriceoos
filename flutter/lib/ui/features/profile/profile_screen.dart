import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme.dart';
import '../../viewmodels/auth_viewmodel.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _avatarBase64;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/beatrice_avatar.txt');
      if (await file.exists()) {
        final data = await file.readAsString();
        if (!mounted) return;
        setState(() => _avatarBase64 = data);
      }
    } catch (e, s) {
      // Swallow — avatar is non-critical. Logged elsewhere if needed.
      debugPrint('Avatar load failed: $e\n$s');
    }
  }

  Future<void> _pickAndSaveAvatar() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Avatar upload coming soon — add image_picker package'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _removeAvatar() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/beatrice_avatar.txt');
      if (await file.exists()) {
        await file.delete();
      }
      if (!mounted) return;
      setState(() => _avatarBase64 = null);
    } catch (e, s) {
      debugPrint('Avatar remove failed: $e\n$s');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final user = authViewModel.user;
    final avatarImage = _decodeAvatar(_avatarBase64);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('My Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Avatar with camera overlay
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: AppTheme.primary,
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? Text(
                                  _getInitials(
                                      user?.displayName ?? user?.email ?? 'U'),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickAndSaveAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 18, color: Colors.black),
                            ),
                          ),
                        ),
                        if (_avatarBase64 != null)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _removeAvatar,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.displayName ?? 'User',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? 'No email',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Provider: ${user?.provider ?? 'N/A'}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 24),

                    // Account Details
                    _buildSection('Account Details', [
                      _buildDetailRow('User ID', user?.uid ?? 'N/A'),
                      _buildDetailRow('Authentication Status', 'Verified'),
                    ]),
                    const SizedBox(height: 16),

                    // Usage Stats
                    _buildSection('Usage', [
                      _buildStatRow('Sessions', '--'),
                      _buildStatRow('Messages', '--'),
                      _buildStatRow('Minutes', '--'),
                    ]),
                  ],
                ),
              ),
            ),

            // Sign Out Button - Pinned to Bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await authViewModel.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushReplacementNamed('/');
                    }
                  },
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.red.withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFFFCA5A5),
                    side: BorderSide(color: AppTheme.red.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Decode a stored base64 avatar into a [MemoryImage], returning null if the
/// data is missing or corrupt (instead of crashing the build).
MemoryImage? _decodeAvatar(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  try {
    return MemoryImage(base64Decode(base64));
  } catch (e, s) {
    debugPrint('Avatar base64 decode failed: $e\n$s');
    return null;
  }
}

String _getInitials(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'U';
  final names = trimmed.split(RegExp(r'\s+')).where((n) => n.isNotEmpty).toList();
  if (names.isEmpty) return 'U';
  if (names.length == 1) {
    return names[0].substring(0, 1).toUpperCase();
  }
  return names[0].substring(0, 1).toUpperCase() +
      names[names.length - 1].substring(0, 1).toUpperCase();
}
