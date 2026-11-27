import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/comment.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';

/// A spot's comment thread plus a composer. Loads once, posts optimistically,
/// and keeps the count in sync with the detail header.
class CommentsSection extends StatefulWidget {
  const CommentsSection({super.key, required this.spotId});

  final String spotId;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadComments(widget.spotId);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    final error = Validators.comment(_controller.text);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _posting = true);
    try {
      await state.postComment(widget.spotId, _controller.text);
      _controller.clear();
      _focus.unfocus();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final auth = context.watch<AuthState>();
    final comments = state.commentsFor(widget.spotId);
    final loading = state.isLoadingComments(widget.spotId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.forum_outlined,
              color: AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 8),
            const Text(
              'Comments',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCount(
                comments.isEmpty
                    ? state.spotById(widget.spotId)?.commentCount ?? 0
                    : comments.length,
              ),
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!loading && comments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Text(
              'No comments yet. Share what you saw — light, timing, the best angle.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          )
        else
          for (final comment in comments) ...[
            _CommentTile(comment: comment),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 6),
        _Composer(
          controller: _controller,
          focusNode: _focus,
          posting: _posting,
          hint: auth.isSignedIn
              ? 'Add what you saw…'
              : 'Comment as ${auth.displayName}',
          onSubmit: _submit,
        ),
        if (!AppInfo.backendConfigured) ...[
          const SizedBox(height: 8),
          const Text(
            'Demo mode: comments stay on this device.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final SpotComment comment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accent, Color(0xFF7C6CFF)],
              ),
            ),
            child: Text(
              comment.initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      formatAgo(comment.createdAt),
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.body,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.posting,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool posting;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('comment_field'),
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Post comment',
          child: PressButton(
            enabled: !posting,
            onTap: onSubmit,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.action,
                borderRadius: BorderRadius.circular(14),
              ),
              child: posting
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onAction,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: AppColors.onAction,
                      size: 20,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
