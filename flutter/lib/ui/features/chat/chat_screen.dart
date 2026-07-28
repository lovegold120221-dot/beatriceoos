import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/connectivity_controller.dart';
import '../../../data/models/conversation_turn.dart';
import '../../viewmodels/chat_viewmodel.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  ChatViewModel? _chatViewModel;
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

  Future<void> _handleSend(ChatViewModel viewModel) async {
    final text = _textController.text.trim();
    if (text.isEmpty || viewModel.isSending) return;
    _textController.clear();
    await viewModel.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final chatViewModel = context.watch<ChatViewModel>();
    final connectivity = context.watch<ConnectivityController>();
    final turns = chatViewModel.turns;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Beatrice'),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chatViewModel.isConnected
                    ? const Color(0xFF00D4AA)
                    : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          if (!chatViewModel.isConnected)
            IconButton(
              tooltip: 'Reconnect',
              icon: chatViewModel.isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: chatViewModel.isConnecting
                  ? null
                  : () => chatViewModel.connect(),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).pushNamed('/profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!connectivity.isOnline)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orangeAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('You are offline. Reconnect when back online.',
                        style: TextStyle(fontSize: 12, color: Colors.orangeAccent)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: turns.isEmpty
                ? _buildEmptyState(chatViewModel)
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: turns.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final turn = turns[index];
                      return _buildTurnBubble(turn);
                    },
                  ),
          ),
          if (chatViewModel.isListening)
            const LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
            ),
          _buildInputBar(chatViewModel),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ChatViewModel chatViewModel) {
    if (chatViewModel.isConnecting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chatViewModel.errorMessage != null && !chatViewModel.isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                chatViewModel.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => chatViewModel.connect(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 56, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          const Text(
            'Say hi to Beatrice',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnBubble(ConversationTurn turn) {
    final isUser = turn.role == 'user';
    final isSystem = turn.role == 'system';
    if (isSystem) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(turn.text,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      );
    }
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF4F46E5) : const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: turn.isFinal
            ? Text(turn.text,
                style: const TextStyle(color: Colors.white, fontSize: 15))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(turn.text,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildInputBar(ChatViewModel viewModel) {
    final disabled = viewModel.isSending || !viewModel.isConnected;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: viewModel.isConnected,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.send,
              onSubmitted: viewModel.isConnected ? (_) => _handleSend(viewModel) : null,
              decoration: InputDecoration(
                hintText: viewModel.isConnected
                    ? 'Type a message...'
                    : 'Not connected',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                filled: true,
                fillColor: const Color(0xFF16213E),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'send',
            onPressed: disabled ? null : () => _handleSend(viewModel),
            child: viewModel.isSending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _chatViewModel?.removeListener(_onVmChanged);
    _scrollController.dispose();
    _textController.dispose();
    // Best-effort disconnect; the VM also disconnects in its own dispose.
    _chatViewModel?.disconnect();
    super.dispose();
  }
}