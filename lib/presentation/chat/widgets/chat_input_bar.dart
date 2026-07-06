import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:speehive_social/core/utils/extensions.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String text, {String? imagePath}) onSend;
  final bool isLoading;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.isLoading = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  String? _selectedImagePath;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (result != null) {
      setState(() {
        _selectedImagePath = result.path;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImagePath = null;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if ((text.isEmpty && _selectedImagePath == null) || widget.isLoading) return;
    widget.onSend(text, imagePath: _selectedImagePath);
    _controller.clear();
    setState(() {
      _hasText = false;
      _selectedImagePath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withAlpha(60)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedImagePath != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withAlpha(140),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedImagePath!.split('/').last,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
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
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withAlpha(140),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.attach_file_outlined,
                              color: cs.onSurfaceVariant),
                          onPressed: widget.isLoading ? null : _pickImage,
                          tooltip: 'Attach image',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLines: null,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: 'Message SpeeHive Intelligence...',
                              border: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              hintStyle: context.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant.withAlpha(120),
                              ),
                            ),
                            onSubmitted: (_) => _handleSend(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Material(
                    color: (_hasText || _selectedImagePath != null) && !widget.isLoading
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _handleSend,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: widget.isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                (_hasText || _selectedImagePath != null)
                                    ? Icons.arrow_upward_rounded
                                    : Icons.mic_outlined,
                                color: (_hasText || _selectedImagePath != null)
                                    ? cs.onPrimary
                                    : cs.onSurfaceVariant,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
