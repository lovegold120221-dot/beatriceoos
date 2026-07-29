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
import '../../widgets/error_screen.dart';
import '../../widgets/task_status_overlay.dart';
import '../../widgets/video_drawer.dart';
import '../../widgets/welcome_screen.dart';
import '../../../data/models/template_model.dart';

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
  bool _isVideoDrawerOpen = false;
  int _lastTurnCount = 0;
  Template _currentTemplate = Template.personalAssistant;

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

  void _handleHoldToTalkStart() {
    _chatViewModel?.startAudioCapture();
  }

  void _handleHoldToTalkEnd() {
    _chatViewModel?.stopAudioCapture();
  }

  void _handleTemplateChanged(Template template) {
    setState(() => _currentTemplate = template);
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
            // ── Main column ──
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
                Expanded(
                  child: _buildBody(chatViewModel),
                ),
              ],
            ),
            // Error banner
            if (chatViewModel.errorMessage != null &&
                !chatViewModel.isConnected)
              Positioned(
                top: 100,
                left: 16,
                right: 16,
                child: ErrorScreen(
                  errorMessage: chatViewModel.errorMessage,
                  errorCode: 'CONNECT_ERR',
                  onDismiss: () => chatViewModel.clearTurns(),
                  onRetry: () => chatViewModel.connect(),
                ),
              ),
            // Task status overlay
            TaskStatusOverlay(
              isRunning: chatViewModel.isTaskRunning,
              message: chatViewModel.isTaskRunning ? 'Running device task...' : '',
            ),
            // Bottom nav
            BeatriceBottomNav(
              connected: chatViewModel.isConnected,
              isChatOpen: _isChatOpen,
              onToggleChat: () {
                setState(() => _isChatOpen = !_isChatOpen);
              },
              onMicTap: _handleMicTap,
              onHoldToTalkStart: _handleHoldToTalkStart,
              onHoldToTalkEnd: _handleHoldToTalkEnd,
            ),
            // Chat drawer
            ChatDrawer(
              isOpen: _isChatOpen,
              onClose: () => setState(() => _isChatOpen = false),
              turns: chatViewModel.turns,
              connected: chatViewModel.isConnected,
              textController: _textController,
              onSend: _handleSend,
            ),
            // Video drawer
            VideoDrawer(
              isOpen: _isVideoDrawerOpen,
              onClose: () => setState(() => _isVideoDrawerOpen = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ChatViewModel vm) {
    if (vm.isConnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.primary,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Connecting...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (vm.isConnected || vm.turns.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: BeatriceOrb(
            connected: vm.isConnected,
            volume: vm.volume,
            inVolume: vm.inVolume,
            isSpeechDetected: vm.isSpeechDetected,
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 100),
        child: WelcomeScreen(
          currentTemplate: _currentTemplate,
          onTemplateChanged: _handleTemplateChanged,
          onPromptTap: _handleSend,
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
