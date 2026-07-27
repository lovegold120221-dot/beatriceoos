import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../data/services/device_control_service.dart';
import '../../viewmodels/auth_viewmodel.dart';

class SpeakerProfile extends StatelessWidget {
  const SpeakerProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final authViewModel = context.watch<AuthViewModel>();
    final user = authViewModel.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speaker Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFF4F46E5),
              child: Text(
                _getInitials(user?.displayName ?? user?.email ?? 'U'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user?.displayName ?? 'User',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user?.email ?? 'No email',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _buildProfileRow('Provider', user?.provider ?? 'N/A'),
            _buildProfileRow('User ID', user?.uid ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

String _getInitials(String? name) {
  if (name == null || name.isEmpty) return 'U';
  final names = name.split(' ');
  if (names.length == 1) return names[0].substring(0, 1).toUpperCase();
  return names[0].substring(0, 1).toUpperCase() +
      names[names.length - 1].substring(0, 1).toUpperCase();
}