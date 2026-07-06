import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speehive_social/core/constants/app_constants.dart';
import 'package:speehive_social/data/datasources/auth/linkedin_oauth_service.dart';

class LinkedInPostResult {
  final String? postId;
  final bool success;
  final String? error;

  const LinkedInPostResult({
    this.postId,
    this.success = false,
    this.error,
  });
}

class LinkedInPostDatasource {
  final LinkedInOAuthService _oauthService;

  LinkedInPostDatasource(this._oauthService);

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Restli-Protocol-Version': '2.0.0',
        'LinkedIn-Version': '202606',
      };

  Future<String?> uploadImage({
    required String token,
    required String personUrn,
    required String imagePath,
  }) async {
    try {
      final initResponse = await http.post(
        Uri.parse('${LinkedInConfig.apiBaseUrl}/rest/images?action=initializeUpload'),
        headers: _headers(token),
        body: json.encode({
          'initializeUploadRequest': {
            'owner': personUrn,
          },
        }),
      );

      if (initResponse.statusCode != 200) {
        debugPrint('[LINKEDIN] Image init failed: ${initResponse.statusCode} ${initResponse.body}');
        return null;
      }

      final initData = json.decode(initResponse.body);
      final uploadUrl = initData['value']['uploadUrl'] as String;
      final imageUrn = initData['value']['image'] as String;

      debugPrint('[LINKEDIN] Image initialized: $imageUrn');

      final imageBytes = await File(imagePath).readAsBytes();

      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Content-Type': 'application/octet-stream',
        },
        body: imageBytes,
      );

      if (uploadResponse.statusCode != 200 && uploadResponse.statusCode != 201) {
        debugPrint('[LINKEDIN] Image upload failed: ${uploadResponse.statusCode}');
        return null;
      }

      debugPrint('[LINKEDIN] Image uploaded successfully: $imageUrn');
      return imageUrn;
    } catch (e) {
      debugPrint('[LINKEDIN] Image upload error: $e');
      return null;
    }
  }

  Future<LinkedInPostResult> createPost({
    required String content,
    String? authorUrn,
    String visibility = 'PUBLIC',
    String? imagePath,
    String? imageUrn,
  }) async {
    final token = await _oauthService.getValidAccessToken();
    if (token == null) {
      return const LinkedInPostResult(
        success: false,
        error: 'Not authenticated with LinkedIn',
      );
    }

    final personUrn = authorUrn ?? await _oauthService.getPersonUrn();
    if (personUrn == null) {
      return const LinkedInPostResult(
        success: false,
        error: 'Could not retrieve LinkedIn person URN',
      );
    }

    String? finalImageUrn = imageUrn;

    if (imagePath != null && finalImageUrn == null) {
      finalImageUrn = await uploadImage(
        token: token,
        personUrn: personUrn,
        imagePath: imagePath,
      );
      if (finalImageUrn == null) {
        return const LinkedInPostResult(
          success: false,
          error: 'Failed to upload image',
        );
      }
    }

    try {
      final postBody = <String, dynamic>{
        'author': personUrn,
        'commentary': content,
        'visibility': visibility,
        'distribution': {
          'feedDistribution': 'MAIN_FEED',
          'targetEntities': [],
          'thirdPartyDistributionChannels': [],
        },
        'lifecycleState': 'PUBLISHED',
      };

      if (finalImageUrn != null) {
        postBody['content'] = {
          'media': {
            'id': finalImageUrn,
          },
        };
      }

      final response = await http.post(
        Uri.parse('${LinkedInConfig.apiBaseUrl}/rest/posts'),
        headers: _headers(token),
        body: json.encode(postBody),
      );

      if (response.statusCode == 201) {
        final postId = response.headers['x-restli-id'];
        debugPrint('[LINKEDIN] Post created successfully: $postId');
        return LinkedInPostResult(
          postId: postId,
          success: true,
        );
      } else if (response.statusCode == 401) {
        final refreshed = await _oauthService.refreshAccessToken();
        if (refreshed != null) {
          return createPost(
            content: content,
            authorUrn: authorUrn,
            visibility: visibility,
            imagePath: imagePath,
            imageUrn: imageUrn,
          );
        }
        return const LinkedInPostResult(
          success: false,
          error: 'Authentication expired. Please reconnect LinkedIn.',
        );
      } else {
        debugPrint('[LINKEDIN] Post creation failed: ${response.statusCode} ${response.body}');
        return LinkedInPostResult(
          success: false,
          error: 'Failed to create post: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[LINKEDIN] Post creation error: $e');
      return LinkedInPostResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<List<Map<String, dynamic>>> getRecentPosts({int count = 10}) async {
    final token = await _oauthService.getValidAccessToken();
    if (token == null) return [];

    final personUrn = await _oauthService.getPersonUrn();
    if (personUrn == null) return [];

    try {
      final response = await http.get(
        Uri.parse('${LinkedInConfig.apiBaseUrl}/rest/posts')
            .replace(queryParameters: {
          'q': 'authors',
          'authors': 'List($personUrn)',
          'count': count.toString(),
          'sortBy': 'LAST_MODIFIED',
        }),
        headers: _headers(token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['elements'] ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('[LINKEDIN] Failed to get recent posts: $e');
      return [];
    }
  }
}
