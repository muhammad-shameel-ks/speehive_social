import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speehive_social/core/utils/extensions.dart';
import 'package:speehive_social/domain/entities/chat_message.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isLastMessage;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.isLastMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final cs = context.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 64 : 16,
        right: isUser ? 16 : 64,
        top: 4,
        bottom: isLastMessage ? 16 : 4,
      ),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.hasToolCalls && !isUser)
            ...message.toolCalls.map((tool) => _buildToolCall(context, cs, tool)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 20),
              ),
            ),
            child: isUser
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (message.imagePath != null && message.imagePath!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 200,
                                maxHeight: 200,
                              ),
                              child: _buildImagePreview(message.imagePath!),
                            ),
                          ),
                        ),
                      if (message.content.isNotEmpty)
                        Text(message.content, style: context.textTheme.bodyMedium),
                    ],
                  )
                : MarkdownBody(
                    data: message.content,
                    styleSheet: MarkdownStyleSheet(
                      p: context.textTheme.bodyMedium,
                      code: TextStyle(
                        backgroundColor: cs.tertiaryContainer,
                        color: cs.onTertiaryContainer,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
          ),
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(
                message.timestamp.timeOnly,
                style: context.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withAlpha(150),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String imagePath) {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(50),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text('Image not found', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(50),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Text('Failed to load image', style: TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolCall(BuildContext context, ColorScheme cs, ToolCallData tool) {
    final isDone = tool.result != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tool.name,
              style: context.textTheme.bodySmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          isDone
              ? Icon(Icons.check_circle, size: 14, color: Colors.green)
              : Icon(Icons.radio_button_checked, size: 14, color: cs.primary),
        ],
      ),
    );
  }
}
