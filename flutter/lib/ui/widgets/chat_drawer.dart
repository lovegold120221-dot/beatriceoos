import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/conversation_turn.dart';

/// Bottom-sheet chat drawer matching the web app's ChatDrawer.
/// Slides up from the bottom with a blurred overlay, dark background,
/// and chat bubbles styled to match the web app.
class ChatDrawer extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final List<ConversationTurn> turns;
  final bool connected;
  final TextEditingController textController;
  final void Function(String) onSend;

  const ChatDrawer({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.turns,
    required this.connected,
    required this.textController,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOpen) return const SizedBox.shrink();

    return Stack(
      children: [
        // Blurred overlay
        GestureDetector(
          onTap: onClose,
          child: Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // Slide-up sheet
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppTheme.border),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildMessages(),
                _buildInputBar(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              'Conversation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${turns.length} turns',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
        GestureDetector(
          onTap: onClose,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 24, color: Color(0xFFaaaaaa)),
          ),
        ),
      ],
    );
  }

  Widget _buildMessages() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 380),
      child: turns.isEmpty
          ? Column(
              children: const [
                SizedBox(height: 40),
                Icon(Icons.chat, size: 36, color: AppTheme.textMuted),
                SizedBox(height: 12),
                Text('No messages yet.',
                    style: TextStyle(color: AppTheme.textSecondary)),
                SizedBox(height: 6),
                Text(
                  'Speak via microphone or send a message below to start chatting with Beatrice.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: turns.length,
              itemBuilder: (ctx, index) => _buildBubble(ctx, turns[index]),
            ),
    );
  }

  Widget _buildBubble(BuildContext context, ConversationTurn turn) {
    final isUser = turn.role == 'user';
    final isSystem = turn.role == 'system';

    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          turn.text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.cardUser : AppTheme.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isUser ? const Radius.circular(14) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(14),
          ),
          border: isUser ? null : Border.all(color: AppTheme.borderSubtle),
        ),
        child: turn.isFinal
            ? Text(
                turn.text,
                style: TextStyle(
                  color: isUser ? const Color(0xFFe0f2fe) : const Color(0xFFf1f1f1),
                  fontSize: 13,
                  height: 1.45,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    turn.text,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  ),
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

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              enabled: connected,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              onSubmitted: connected ? (v) => onSend(v) : null,
              decoration: InputDecoration(
                hintText: connected ? 'Type a message to Beatrice...' : 'Connect session to send text...',
                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                filled: true,
                fillColor: AppTheme.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.cyan),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: connected ? () => onSend(textController.text) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Send',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}