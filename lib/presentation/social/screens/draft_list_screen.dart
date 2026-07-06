import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speehive_social/core/di/providers.dart';
import 'package:speehive_social/core/utils/extensions.dart';
import 'package:speehive_social/domain/entities/post_draft.dart';

class DraftListScreen extends ConsumerStatefulWidget {
  const DraftListScreen({super.key});

  @override
  ConsumerState<DraftListScreen> createState() => _DraftListScreenState();
}

class _DraftListScreenState extends ConsumerState<DraftListScreen> {
  List<PostDraft> _drafts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    setState(() => _isLoading = true);
    final draftService = ref.read(draftStorageServiceProvider);
    final drafts = await draftService.getDrafts();
    if (mounted) {
      setState(() {
        _drafts = drafts;
        _isLoading = false;
      });
    }
  }

  Future<void> _approveDraft(PostDraft draft) async {
    final draftService = ref.read(draftStorageServiceProvider);
    final linkedinService = ref.read(linkedinOAuthServiceProvider);

    final isAuth = await linkedinService.isAuthenticated();
    if (!isAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please connect LinkedIn in Settings first')),
        );
      }
      return;
    }

    String? imagePath;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _PublishDialog(
        onPickImage: (path) => imagePath = path,
      ),
    );

    if (result != true) return;

    final linkedinDatasource = ref.read(linkedinPostDatasourceProvider);
    final postResult = await linkedinDatasource.createPost(
      content: draft.content,
      imagePath: imagePath,
    );

    if (postResult.success) {
      await draftService.markAsPublished(draft.id, postResult.postId ?? '');
      await _loadDrafts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(imagePath != null ? 'Post with image published to LinkedIn' : 'Post published to LinkedIn')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: ${postResult.error}')),
        );
      }
    }
  }

  Future<void> _rejectDraft(PostDraft draft) async {
    final draftService = ref.read(draftStorageServiceProvider);
    await draftService.updateDraftStatus(draft.id, DraftStatus.rejected);
    await _loadDrafts();
  }

  Future<void> _deleteDraft(PostDraft draft) async {
    final draftService = ref.read(draftStorageServiceProvider);
    await draftService.deleteDraft(draft.id);
    await _loadDrafts();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft Posts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDrafts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 64,
                        color: cs.onSurfaceVariant.withAlpha(80),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No drafts yet',
                        style: context.textTheme.headlineSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ask the AI to generate posts from your calendar events',
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _drafts.length,
                  itemBuilder: (context, index) {
                    final draft = _drafts[index];
                    return _DraftCard(
                      draft: draft,
                      onApprove: () => _approveDraft(draft),
                      onReject: () => _rejectDraft(draft),
                      onDelete: () => _deleteDraft(draft),
                    );
                  },
                ),
    );
  }
}

class _PublishDialog extends StatefulWidget {
  final Function(String? path) onPickImage;

  const _PublishDialog({required this.onPickImage});

  @override
  State<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends State<_PublishDialog> {
  String? _selectedImagePath;

  Future<void> _pickImage() async {
    final result = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (result != null) {
      setState(() {
        _selectedImagePath = result.path;
      });
      widget.onPickImage(_selectedImagePath);
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImagePath = null;
    });
    widget.onPickImage(null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    return AlertDialog(
      title: const Text('Publish to LinkedIn'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Would you like to attach an image to this post?',
            style: context.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_selectedImagePath != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(140),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.image, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedImagePath!.split('/').last,
                      style: context.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                    onPressed: _removeImage,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                label: const Text('Pick an image'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.publish, size: 18),
          label: const Text('Publish'),
        ),
      ],
    );
  }
}

class _DraftCard extends StatelessWidget {
  final PostDraft draft;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _DraftCard({
    required this.draft,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (draft.status) {
      case DraftStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        statusText = 'Pending';
        break;
      case DraftStatus.approved:
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        statusText = 'Approved';
        break;
      case DraftStatus.rejected:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Rejected';
        break;
      case DraftStatus.published:
        statusColor = Colors.green;
        statusIcon = Icons.public;
        statusText = 'Published';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: context.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (draft.eventTitle != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      draft.eventTitle!,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.outlineVariant.withAlpha(50),
                ),
              ),
              child: Text(
                draft.content,
                style: context.textTheme.bodyMedium,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Created: ${draft.createdAt.formatted}',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (draft.status == DraftStatus.pending) ...[
                  TextButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.publish, size: 18),
                    label: const Text('Publish'),
                  ),
                ] else if (draft.status == DraftStatus.published) ...[
                  Text(
                    'Published: ${draft.publishedAt?.formatted ?? "N/A"}',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: Colors.green,
                    ),
                  ),
                ] else ...[
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
