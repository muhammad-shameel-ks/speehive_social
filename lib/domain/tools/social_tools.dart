import 'dart:convert';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:speehive_social/data/datasources/google/google_calendar_datasource.dart';
import 'package:speehive_social/data/datasources/linkedin/linkedin_post_datasource.dart';
import 'package:speehive_social/data/datasources/outlook/outlook_calendar_datasource.dart';

class SocialMediaTools {
  final GoogleCalendarDatasource? _googleCalendarDatasource;
  final OutlookCalendarDatasource? _outlookDatasource;
  final LinkedInPostDatasource? _linkedinDatasource;

  SocialMediaTools({
    GoogleCalendarDatasource? googleCalendarDatasource,
    OutlookCalendarDatasource? outlookDatasource,
    LinkedInPostDatasource? linkedinDatasource,
  })  : _googleCalendarDatasource = googleCalendarDatasource,
        _outlookDatasource = outlookDatasource,
        _linkedinDatasource = linkedinDatasource;

  Map<String, Tool> get all {
    return {
      'get_events': _getEventsTool,
      'create_post': _createPostTool,
      'create_linkedin_post': _createLinkedInPostTool,
      'generate_event_post': _generateEventPostTool,
      'schedule_post': _schedulePostTool,
      'generate_hashtags': _generateHashtagsTool,
      'optimize_content': _optimizeContentTool,
      'get_analytics': _analyticsTool,
      'get_trending_topics': _trendingTopicsTool,
    };
  }

  late final _getEventsTool = tool<Map<String, dynamic>, String>(
    description: 'Get calendar events from Google Calendar or Outlook. Use this to fetch today\'s events, upcoming events for the month, or events for a specific date range. Returns event details including title, time, attendees, location, and meeting links.',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'date': {
            'type': 'string',
            'description': 'Optional date in YYYY-MM-DD format. If omitted, returns today\'s events.',
          },
          'days': {
            'type': 'integer',
            'description': 'Number of days to look ahead (default: 1, max: 30). Use 30 for "upcoming events" or "this month" queries.',
          },
        },
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      // Try Google Calendar first, then Outlook
      if (_googleCalendarDatasource == null && _outlookDatasource == null) {
        return 'Error: No calendar integration configured. Please connect your Google Calendar or Outlook account in Settings.';
      }

      try {
        final dateStr = input['date'] as String?;
        final days = (input['days'] as int?) ?? 1;

        DateTime start;
        DateTime end;

        if (dateStr != null) {
          start = DateTime.parse(dateStr);
          end = start.add(Duration(days: days));
        } else {
          final now = DateTime.now();
          start = DateTime(now.year, now.month, now.day);
          end = start.add(Duration(days: days));
        }

        debugPrint('[TOOLS] get_events: fetching events from $start to $end');

        List<dynamic> events;
        String calendarSource;

        final googleCalendar = _googleCalendarDatasource;
        final outlook = _outlookDatasource;

        // Try Google Calendar first
        if (googleCalendar != null) {
          try {
            events = await googleCalendar.getEvents(start: start, end: end);
            calendarSource = 'Google Calendar';
          } catch (e) {
            debugPrint('[TOOLS] Google Calendar failed, trying Outlook: $e');
            if (outlook != null) {
              events = await outlook.getEvents(start: start, end: end);
              calendarSource = 'Outlook';
            } else {
              rethrow;
            }
          }
        } else {
          events = await outlook!.getEvents(start: start, end: end);
          calendarSource = 'Outlook';
        }

        if (events.isEmpty) {
          return json.encode({
            'events': [],
            'source': calendarSource,
            'message': 'No events found for the specified date range.',
          });
        }

        final eventsJson = events.map((e) => e.toJson()).toList();
        return json.encode({
          'events': eventsJson,
          'source': calendarSource,
          'count': events.length,
          'dateRange': {
            'start': start.toIso8601String(),
            'end': end.toIso8601String(),
          },
        });
      } catch (e) {
        debugPrint('[TOOLS] get_events error: $e');
        return json.encode({
          'error': e.toString(),
          'message': 'Failed to fetch events. Please check your calendar connection in Settings.',
        });
      }
    },
  );

  late final _createLinkedInPostTool = tool<Map<String, dynamic>, String>(
    description: 'Create and publish a post to LinkedIn using the LinkedIn Posts API. Use this to publish content directly to LinkedIn. Supports optional image attachment.',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': 'The post content/text to publish on LinkedIn',
          },
          'visibility': {
            'type': 'string',
            'enum': ['PUBLIC', 'CONNECTIONS'],
            'description': 'Post visibility (default: PUBLIC)',
          },
          'imagePath': {
            'type': 'string',
            'description': 'Optional local file path to an image to attach (JPG, PNG, or GIF)',
          },
        },
        'required': ['content'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      if (_linkedinDatasource == null) {
        return 'Error: LinkedIn integration not configured. Please connect your LinkedIn account in Settings.';
      }

      try {
        final content = input['content'] as String;
        final visibility = (input['visibility'] as String?) ?? 'PUBLIC';
        final imagePath = input['imagePath'] as String?;

        debugPrint('[TOOLS] create_linkedin_post: publishing to LinkedIn');
        final result = await _linkedinDatasource.createPost(
          content: content,
          visibility: visibility,
          imagePath: imagePath,
        );

        if (result.success) {
          return json.encode({
            'success': true,
            'postId': result.postId,
            'message': imagePath != null
                ? 'Post with image published successfully to LinkedIn.'
                : 'Post published successfully to LinkedIn.',
          });
        } else {
          return json.encode({
            'success': false,
            'error': result.error,
            'message': 'Failed to publish to LinkedIn: ${result.error}',
          });
        }
      } catch (e) {
        debugPrint('[TOOLS] create_linkedin_post error: $e');
        return json.encode({
          'success': false,
          'error': e.toString(),
          'message': 'Failed to publish to LinkedIn.',
        });
      }
    },
  );

  late final _generateEventPostTool = tool<Map<String, dynamic>, String>(
    description: 'Generate a LinkedIn post from calendar event details. Use this when you have event information and want to create engaging content for LinkedIn.',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'eventTitle': {
            'type': 'string',
            'description': 'The title/subject of the event',
          },
          'eventDescription': {
            'type': 'string',
            'description': 'Optional description or details about the event',
          },
          'eventTime': {
            'type': 'string',
            'description': 'When the event takes place (ISO 8601 format)',
          },
          'eventLocation': {
            'type': 'string',
            'description': 'Where the event is held',
          },
          'attendees': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'List of attendees or key participants',
          },
          'tone': {
            'type': 'string',
            'enum': ['professional', 'casual', 'excited', 'informative'],
            'description': 'Desired tone for the post',
          },
          'autoPublish': {
            'type': 'boolean',
            'description': 'If true, publish directly to LinkedIn. If false, return as draft. Default: false',
          },
        },
        'required': ['eventTitle'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      try {
        final title = input['eventTitle'] as String;
        final description = input['eventDescription'] as String?;
        final time = input['eventTime'] as String?;
        final location = input['eventLocation'] as String?;
        final attendees = (input['attendees'] as List?)?.cast<String>();
        final tone = (input['tone'] as String?) ?? 'professional';
        final autoPublish = (input['autoPublish'] as bool?) ?? false;

        debugPrint('[TOOLS] generate_event_post: generating post for "$title"');

        // Generate the post content based on tone
        final postContent = _generateLinkedInPostContent(
          title: title,
          description: description,
          time: time,
          location: location,
          attendees: attendees,
          tone: tone,
        );

        // If auto-publish is enabled and LinkedIn is configured
        if (autoPublish && _linkedinDatasource != null) {
          final result = await _linkedinDatasource.createPost(
            content: postContent,
          );

          if (result.success) {
            return json.encode({
              'success': true,
              'published': true,
              'postId': result.postId,
              'content': postContent,
              'message': 'Post generated and published to LinkedIn successfully.',
            });
          } else {
            return json.encode({
              'success': true,
              'published': false,
              'content': postContent,
              'error': result.error,
              'message': 'Post generated but failed to publish: ${result.error}',
            });
          }
        }

        // Return as draft
        return json.encode({
          'success': true,
          'published': false,
          'content': postContent,
          'message': 'Post generated successfully. Ready for review before publishing.',
        });
      } catch (e) {
        debugPrint('[TOOLS] generate_event_post error: $e');
        return json.encode({
          'success': false,
          'error': e.toString(),
          'message': 'Failed to generate event post.',
        });
      }
    },
  );

  String _generateLinkedInPostContent({
    required String title,
    String? description,
    String? time,
    String? location,
    List<String>? attendees,
    String tone = 'professional',
  }) {
    final buffer = StringBuffer();

    switch (tone) {
      case 'excited':
        buffer.writeln('Excited to share! 🎉');
        buffer.writeln();
        buffer.writeln('$title');
        break;
      case 'casual':
        buffer.writeln('$title');
        break;
      case 'informative':
        buffer.writeln('📢 $title');
        break;
      default:
        buffer.writeln('$title');
    }

    buffer.writeln();

    if (description != null && description.isNotEmpty) {
      buffer.writeln(description);
      buffer.writeln();
    }

    if (time != null) {
      buffer.writeln('📅 When: $time');
    }

    if (location != null && location.isNotEmpty) {
      buffer.writeln('📍 Where: $location');
    }

    if (attendees != null && attendees.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Looking forward to connecting with: ${attendees.join(", ")}');
    }

    buffer.writeln();
    buffer.writeln('#event #networking #professional');

    return buffer.toString();
  }

  static final _createPostTool = tool<Map<String, dynamic>, String>(
    description: 'Create and optionally publish a social media post across one or more platforms',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'platforms': {
            'type': 'array',
            'items': {'type': 'string', 'enum': ['twitter', 'linkedin', 'instagram', 'facebook']},
            'description': 'Target platforms for the post',
          },
          'content': {
            'type': 'string',
            'description': 'The post content/text',
          },
          'mediaUrls': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'URLs of images or videos to attach',
          },
          'scheduledAt': {
            'type': 'string',
            'description': 'ISO 8601 datetime for scheduling. If omitted, post immediately',
          },
        },
        'required': ['platforms', 'content'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      final platforms = (input['platforms'] as List).cast<String>();
      final content = input['content'] as String;
      return 'Post created for ${platforms.join(", ")}: "$content"';
    },
  );

  static final _schedulePostTool = tool<Map<String, dynamic>, String>(
    description: 'Schedule a post for future publication on a specific platform',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'platform': {
            'type': 'string',
            'enum': ['twitter', 'linkedin', 'instagram', 'facebook'],
          },
          'content': {'type': 'string'},
          'scheduledAt': {
            'type': 'string',
            'description': 'ISO 8601 datetime for scheduling',
          },
          'mediaUrls': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['platform', 'content', 'scheduledAt'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      final platform = input['platform'] as String;
      final content = input['content'] as String;
      final scheduledAt = input['scheduledAt'] as String;
      return 'Post scheduled for $platform at $scheduledAt: "$content"';
    },
  );

  static final _generateHashtagsTool = tool<Map<String, dynamic>, String>(
    description: 'Generate relevant hashtags for content to maximize reach',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'description': 'The content to generate hashtags for'},
          'platform': {
            'type': 'string',
            'enum': ['twitter', 'linkedin', 'instagram', 'facebook'],
          },
          'count': {
            'type': 'integer',
            'description': 'Number of hashtags to generate (default: 5)',
          },
        },
        'required': ['content', 'platform'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      return 'Generated hashtags for "${input['content']}" on ${input['platform']}';
    },
  );

  static final _optimizeContentTool = tool<Map<String, dynamic>, String>(
    description: 'Optimize content for a specific platform\'s best practices, character limits, and audience',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'description': 'The content to optimize'},
          'platform': {
            'type': 'string',
            'enum': ['twitter', 'linkedin', 'instagram', 'facebook'],
          },
          'tone': {
            'type': 'string',
            'enum': ['professional', 'casual', 'engaging', 'educational', 'humorous'],
          },
        },
        'required': ['content', 'platform'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      return 'Optimized content for ${input['platform']} with ${input['tone'] ?? "default"} tone';
    },
  );

  static final _analyticsTool = tool<Map<String, dynamic>, String>(
    description: 'Get analytics and engagement metrics for posts or accounts',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'postId': {'type': 'string'},
          'platform': {
            'type': 'string',
            'enum': ['twitter', 'linkedin', 'instagram', 'facebook'],
          },
          'timeframe': {
            'type': 'string',
            'enum': ['7d', '30d', '90d'],
            'description': 'Analysis timeframe',
          },
        },
        'required': ['postId', 'platform'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      return 'Analytics for post ${input['postId']} on ${input['platform']}';
    },
  );

  static final _trendingTopicsTool = tool<Map<String, dynamic>, String>(
    description: 'Get current trending topics for a platform to inspire content',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'platform': {
            'type': 'string',
            'enum': ['twitter', 'linkedin', 'instagram'],
          },
          'category': {
            'type': 'string',
            'description': 'Optional category filter',
          },
        },
        'required': ['platform'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, options) async {
      return 'Trending topics for ${input['platform']}';
    },
  );
}
