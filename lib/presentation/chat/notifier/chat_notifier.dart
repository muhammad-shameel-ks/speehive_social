import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:speehive_social/core/di/providers.dart';
import 'package:speehive_social/data/datasources/ai/ai_provider.dart';
import 'package:speehive_social/domain/entities/chat_message.dart';
import 'package:speehive_social/domain/repositories/chat_repository.dart';
import 'package:speehive_social/domain/tools/social_tools.dart';

@immutable
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isStreaming;
  final String streamingContent;
  final List<ToolCallData> streamingToolCalls;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isStreaming = false,
    this.streamingContent = '',
    this.streamingToolCalls = const [],
    this.error,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isStreaming,
    String? streamingContent,
    List<ToolCallData>? streamingToolCalls,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingContent: streamingContent ?? this.streamingContent,
      streamingToolCalls: streamingToolCalls ?? this.streamingToolCalls,
      error: error,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  final _uuid = const Uuid();
  Timer? _emitTimer;
  String _accumulatedContent = '';
  ChatRepository? _repo;
  AppAIProvider? _ai;

  @override
  ChatState build() => const ChatState();

  ChatRepository get _chatRepository => _repo ?? ref.read(chatRepositoryProvider);
  AppAIProvider get _aiProvider => _ai ?? ref.read(aiProvider);

  SocialMediaTools get _tools => SocialMediaTools(
        googleCalendarDatasource: ref.read(googleCalendarDatasourceProvider),
        outlookDatasource: ref.read(outlookCalendarDatasourceProvider),
        linkedinDatasource: ref.read(linkedinPostDatasourceProvider),
      );

  void sendMessage(String content) async {
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );

    final messages = [...state.messages, userMessage];
    state = state.copyWith(
      messages: messages,
      isLoading: true,
      error: null,
    );

    try {
      final result = await _chatRepository.generateResponse(
        messages: messages,
        tools: _tools.all,
      );

      if (result.isSuccess) {
        final assistantMessage = ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: result.data!,
          timestamp: DateTime.now(),
        );
        state = state.copyWith(
          messages: [...state.messages, assistantMessage],
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result.error!.message,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void streamMessage(String content, {String? imagePath}) async {
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
      imagePath: imagePath,
    );

    final messages = [...state.messages, userMessage];
    state = state.copyWith(
      messages: messages,
      isStreaming: true,
      streamingContent: '',
      streamingToolCalls: [],
      error: null,
    );

    _emitTimer?.cancel();
    _accumulatedContent = '';
    List<ToolCallData> capturedToolCalls = [];

    try {
      final result = await _chatRepository.streamResponseWithToolCalls(
        messages: messages,
        tools: _tools.all,
        onToolCalls: (toolCalls) {
          capturedToolCalls = toolCalls;
          debugPrint('[CHAT] Captured ${toolCalls.length} tool calls');
          state = state.copyWith(streamingToolCalls: toolCalls);
        },
      );

      if (result.isSuccess) {
        final assistantId = _uuid.v4();

        _accumulatedContent = '';

        final subscription = result.data!
            .timeout(const Duration(seconds: 60), onTimeout: (sink) {
          sink.close();
        }).listen(
          (textChunk) {
            _accumulatedContent += textChunk;
            _scheduleEmit();
          },
          onDone: () {
            _emitTimer?.cancel();
            final assistantMessage = ChatMessage(
              id: assistantId,
              role: MessageRole.assistant,
              content: _accumulatedContent,
              timestamp: DateTime.now(),
              toolCalls: capturedToolCalls,
            );
            state = state.copyWith(
              messages: [...state.messages, assistantMessage],
              isStreaming: false,
              streamingContent: '',
              streamingToolCalls: [],
            );
          },
          onError: (error) {
            _emitTimer?.cancel();
            state = state.copyWith(
              isStreaming: false,
              error: error.toString(),
            );
          },
        );

        ref.onDispose(() => subscription.cancel());
      } else {
        state = state.copyWith(
          isStreaming: false,
          error: result.error!.message,
        );
      }
    } catch (e) {
      _emitTimer?.cancel();
      state = state.copyWith(
        isStreaming: false,
        error: e.toString(),
      );
    }
  }

  void _scheduleEmit() {
    _emitTimer?.cancel();
    _emitTimer = Timer(const Duration(milliseconds: 50), () {
      state = state.copyWith(streamingContent: _accumulatedContent);
    });
  }

  void clearMessages() {
    _emitTimer?.cancel();
    _accumulatedContent = '';
    state = const ChatState();
  }

  void updateConfig({String? apiKey, String? baseUrl, String? model}) {
    _aiProvider.updateConfig(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
    );
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
