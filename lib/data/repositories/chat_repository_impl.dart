import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:speehive_social/core/constants/app_constants.dart';
import 'package:speehive_social/core/constants/prompts.dart';
import 'package:speehive_social/core/errors/failures.dart';
import 'package:speehive_social/data/datasources/ai/ai_provider.dart';
import 'package:speehive_social/domain/entities/chat_message.dart';
import 'package:speehive_social/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final AppAIProvider _aiProvider;

  ChatRepositoryImpl(this._aiProvider);

  @override
  Future<Result<Stream<String>>> streamResponse({
    required List<ChatMessage> messages,
    required Map<String, dynamic> tools,
    int? maxSteps,
  }) async {
    try {
      debugPrint('[CHAT] Repo.streamResponse: getting languageModel...');
      final model = _aiProvider.languageModel;
      debugPrint('[CHAT] Repo.streamResponse: got model, converting ${messages.length} messages...');
      final convertedMessages = _convertMessages(messages);
      final convertedTools = _convertTools(tools);
      debugPrint('[CHAT] Repo.streamResponse: converted tools count=${convertedTools.length}');
      debugPrint('[CHAT] Repo.streamResponse: calling streamText with timeout...');
      
      final result = await streamText(
        model: model,
        messages: convertedMessages,
        tools: convertedTools,
        maxSteps: maxSteps ?? ApiConfig.maxToolSteps,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[CHAT] Repo.streamResponse: streamText TIMED OUT after 30s');
          throw TimeoutException('AI request timed out after 30 seconds');
        },
      );
      debugPrint('[CHAT] Repo.streamResponse: streamText returned, result type=${result.runtimeType}');

      final textStream = result.textStream;
      debugPrint('[CHAT] Repo.streamResponse: got textStream, returning success');
      return Result.success(textStream);
    } on TimeoutException catch (e) {
      debugPrint('[CHAT] Repo.streamResponse: TimeoutException: ${e.message}');
      return Result.failure(AIServiceFailure(message: e.message ?? 'Request timed out'));
    } on Failure catch (e) {
      debugPrint('[CHAT] Repo.streamResponse: Failure caught: ${e.message}');
      return Result.failure(e);
    } catch (e, stackTrace) {
      debugPrint('[CHAT] Repo.streamResponse: Exception caught: $e');
      debugPrint('[CHAT] Repo.streamResponse: STACK: $stackTrace');
      return Result.failure(AIServiceFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Stream<String>>> streamResponseWithToolCalls({
    required List<ChatMessage> messages,
    required Map<String, dynamic> tools,
    int? maxSteps,
    void Function(List<ToolCallData>)? onToolCalls,
  }) async {
    try {
      debugPrint('[CHAT] Repo.streamResponseWithToolCalls: getting languageModel...');
      final model = _aiProvider.languageModel;
      final convertedMessages = _convertMessages(messages);
      final convertedTools = _convertTools(tools);
      
      final result = await streamText(
        model: model,
        messages: convertedMessages,
        tools: convertedTools,
        maxSteps: maxSteps ?? ApiConfig.maxToolSteps,
        onStepFinish: (step) {
          debugPrint('[CHAT] Step finished: toolCalls=${step.toolCalls.length}, toolResults=${step.toolResults.length}');
          
          if (step.toolCalls.isNotEmpty) {
            final toolCalls = step.toolCalls.map((tc) {
              final matchingResult = step.toolResults
                  .where((tr) => tr.toolCallId == tc.toolCallId)
                  .map((tr) => tr.output.toString())
                  .firstOrNull;
              
              return ToolCallData(
                id: tc.toolCallId,
                name: tc.toolName,
                arguments: <String, dynamic>{},
                result: matchingResult,
              );
            }).toList();
            
            debugPrint('[CHAT] Tool calls: ${toolCalls.map((t) => t.name).join(", ")}');
            onToolCalls?.call(toolCalls);
          }
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('AI request timed out after 30 seconds');
        },
      );

      final textStream = result.textStream;
      return Result.success(textStream);
    } on TimeoutException catch (e) {
      return Result.failure(AIServiceFailure(message: e.message ?? 'Request timed out'));
    } on Failure catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(AIServiceFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<String>> generateResponse({
    required List<ChatMessage> messages,
    required Map<String, dynamic> tools,
    int? maxSteps,
  }) async {
    try {
      final model = _aiProvider.languageModel;
      final convertedMessages = _convertMessages(messages);
      final convertedTools = _convertTools(tools);

      final result = await generateText(
        model: model,
        messages: convertedMessages,
        tools: convertedTools,
        maxSteps: maxSteps ?? ApiConfig.maxToolSteps,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('AI request timed out after 60 seconds');
        },
      );

      return Result.success(result.text);
    } on TimeoutException catch (e) {
      return Result.failure(AIServiceFailure(message: e.message ?? 'Request timed out'));
    } on Failure catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(AIServiceFailure(message: e.toString()));
    }
  }

  List<ModelMessage> _convertMessages(List<ChatMessage> messages) {
    final systemMessage = ModelMessage(
      role: ModelMessageRole.system,
      content: systemPrompt,
    );
    return [
      systemMessage,
      ...messages.map((m) {
        if (m.imagePath != null && m.imagePath!.isNotEmpty && m.role == MessageRole.user) {
          return _convertMessageWithImage(m);
        }
        return ModelMessage(
          role: _toModelMessageRole(m.role),
          content: m.content,
        );
      }),
    ];
  }

  ModelMessage _convertMessageWithImage(ChatMessage message) {
    final parts = <LanguageModelV3ContentPart>[];

    try {
      final file = File(message.imagePath!);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        final base64Image = base64Encode(bytes);

        final extension = message.imagePath!.split('.').last.toLowerCase();
        String mediaType;
        switch (extension) {
          case 'png':
            mediaType = 'image/png';
            break;
          case 'gif':
            mediaType = 'image/gif';
            break;
          case 'webp':
            mediaType = 'image/webp';
            break;
          default:
            mediaType = 'image/jpeg';
        }

        parts.add(LanguageModelV3ImagePart(
          image: DataContentBase64(base64Image),
          mediaType: mediaType,
        ));
      }
    } catch (e) {
      debugPrint('[CHAT] Failed to read image file: $e');
    }

    if (message.content.isNotEmpty) {
      parts.add(LanguageModelV3TextPart(text: message.content));
    }

    if (parts.isEmpty) {
      return ModelMessage(
        role: _toModelMessageRole(message.role),
        content: message.content,
      );
    }

    return ModelMessage.parts(
      role: _toModelMessageRole(message.role),
      parts: parts,
    );
  }

  ModelMessageRole _toModelMessageRole(MessageRole role) {
    switch (role) {
      case MessageRole.user:
        return ModelMessageRole.user;
      case MessageRole.assistant:
        return ModelMessageRole.assistant;
      case MessageRole.system:
        return ModelMessageRole.system;
      case MessageRole.tool:
        return ModelMessageRole.tool;
    }
  }

  ToolSet _convertTools(Map<String, dynamic> tools) {
    final result = ToolSet();
    for (final entry in tools.entries) {
      if (entry.value is Tool) {
        result[entry.key] = entry.value as Tool<dynamic, dynamic>;
      }
    }
    return result;
  }
}
