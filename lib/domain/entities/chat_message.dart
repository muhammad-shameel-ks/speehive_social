import 'package:equatable/equatable.dart';

enum MessageRole { user, assistant, system, tool }

class ToolCallData extends Equatable {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? result;

  const ToolCallData({
    required this.id,
    required this.name,
    required this.arguments,
    this.result,
  });

  ToolCallData copyWith({String? result}) {
    return ToolCallData(
      id: id,
      name: name,
      arguments: arguments,
      result: result ?? this.result,
    );
  }

  @override
  List<Object?> get props => [id, name, arguments, result];
}

class ChatMessage extends Equatable {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ToolCallData> toolCalls;
  final bool isLoading;
  final Map<String, dynamic>? metadata;
  final String? imagePath;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCalls = const [],
    this.isLoading = false,
    this.metadata,
    this.imagePath,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    List<ToolCallData>? toolCalls,
    bool? isLoading,
    Map<String, dynamic>? metadata,
    String? imagePath,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolCalls: toolCalls ?? this.toolCalls,
      isLoading: isLoading ?? this.isLoading,
      metadata: metadata ?? this.metadata,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  bool get hasToolCalls => toolCalls.isNotEmpty;

  bool get hasToolResults => toolCalls.any((t) => t.result != null);

  @override
  List<Object?> get props => [id, role, content, timestamp, toolCalls, isLoading, metadata, imagePath];
}
