import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/network/connectivity_controller.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/chat_viewmodel.dart';
import '../../widgets/beatrice_orb.dart';
import '../../widgets/beatrice_status_bar.dart';
import '../../widgets/beatrice_header.dart';
import '../../widgets/beatrice_bottom_nav.dart';
import '../../widgets/chat_drawer.dart';

/// Beatrice home screen — the orb-centric layout matching the web app.
///
/// Structure: StatusBar → Header → Orb (centred) → BottomNav (mic + chat).
/// Chat is a slide-up bottom-sheet drawer. The orb reacts to connection
/// state and audio volume.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  ChatViewModel? _chatViewModel;
  bool _isChatOpen = false;
  int _lastTurnCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<ChatViewModel>();
      _chatViewModel = vm;
      vm.addListener(_onVmChanged);
      _lastTurnCount = vm.turns.length;
      vm.connect();
    });
  }

  void _onVmChanged() {
    final vm = _chatViewModel;
    if (vm == null) return;
    if (vm.turns.length != _lastTurnCount) {
      _lastTurnCount = vm.turns.length;
      _scheduleScrollToBottom();
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleSend(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();
    _chatViewModel?.sendMessage(trimmed);
  }

  void _handleMicTap() {
    final vm = _chatViewModel;
    if (vm == null) return;
    if (vm.isConnected) {
      vm.disconnect();
    } else {
      vm.connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatViewModel = context.watch<ChatViewModel>();
    final connectivity = context.watch<ConnectivityController>();
    final authViewModel = context.watch<AuthViewModel>();

    final user = authViewModel.user;
    final initials = _getInitials(user?.displayName ?? user?.email);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // ── Main column: StatusBar → Header → Orb ──
            Column(
              children: [
                BeatriceStatusBar(
                  mobileUseConnected: chatViewModel.isConnected,
                ),
                BeatriceHeader(
                  avatarInitials: initials,
                  avatarImageUrl: user?.photoURL,
                  onSettingsTap: () =>
                      Navigator.of(context).pushNamed('/settings'),
                  onAvatarTap: () =>
                      Navigator.of(context).pushNamed('/profile'),
                ),
                // Offline banner
                if (!connectivity.isOnline)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_off,
                            size: 16, color: Colors.orangeAccent),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'You are offline. Reconnect when back online.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orangeAccent)),
                        ),
                      ],
                    ),
                  ),
                // Error banner
                if (chatViewModel.errorMessage != null &&
                    !chatViewModel.isConnected)
                  Container(
                    width: double.infinity,
                    color: Colors.red.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: AppTheme.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            chatViewModel.errorMessage!,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.red),
                          ),
                        ),
                        TextButton(
                          onPressed: () => chatViewModel.connect(),
                          child: const Text('Reconnect',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                // Orb centred
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 100),
                      child: BeatriceOrb(
                        connected: chatViewModel.isConnected,
                        volume: chatViewModel.volume,
                        inVolume: chatViewModel.inVolume,
                        isSpeechDetected: chatViewModel.isSpeechDetected,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // ── Bottom nav (mic + chat toggle) ──
            BeatriceBottomNav(
              connected: chatViewModel.isConnected,
              isChatOpen: _isChatOpen,
              onToggleChat: () {
                setState(() => _isChatOpen = !_isChatOpen);
              },
              onMicTap: _handleMicTap,
            ),
            // ── Chat drawer (slide-up bottom sheet) ──
            ChatDrawer(
              isOpen: _isChatOpen,
              onClose: () => setState(() => _isChatOpen = false),
              turns: chatViewModel.turns,
              connected: chatViewModel.isConnected,
              textController: _textController,
              onSend: _handleSend,
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return 'U';
    final names =
        trimmed.split(RegExp(r'\s+')).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return 'U';
    if (names.length == 1) return names[0][0].toUpperCase();
    return '${names[0][0].toUpperCase()}${names.last[0].toUpperCase()}';
  }

  @override
  void dispose() {
    _chatViewModel?.removeListener(_onVmChanged);
    _textController.dispose();
    _scrollController.dispose();
    _chatViewModel?.disconnect();
    super.dispose();
  }
}