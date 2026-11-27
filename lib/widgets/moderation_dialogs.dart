import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth_screen.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';

const _reportReasons = [
  'Inappropriate or explicit content',
  'Unsafe location or private property',
  'Spam or misleading location',
  'Harassment or hate speech',
  'Copyright or privacy concern',
];

/// Prompts the user to sign in when a restricted community action is attempted
/// by a guest while accounts are enabled.
Future<bool> requireSignedInAccount(
  BuildContext context, {
  required String actionLabel,
}) async {
  final auth = context.read<AuthState>();
  if (auth.canContribute) return true;

  final openAuth = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Account required'),
      content: Text(
        'Sign in or create an account to $actionLabel. Guests can browse and '
        'save spots locally on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Sign in'),
        ),
      ],
    ),
  );
  if (openAuth == true && context.mounted) {
    await Navigator.of(context).push(AppMotion.slideUp(const AuthScreen()));
  }
  return context.mounted && context.read<AuthState>().canContribute;
}

/// Opens a UGC report & optional block sheet for a spot or comment.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? authorId,
  String? authorName,
}) async {
  if (!await requireSignedInAccount(context, actionLabel: 'report content')) {
    return;
  }
  if (!context.mounted) return;

  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  var reason = _reportReasons.first;
  var alsoBlock = false;
  final detailsController = TextEditingController();

  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetType == 'spot' ? 'Report spot' : 'Report comment',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Help keep PhotoSpot safe and accurate. Reports are reviewed '
                  'under our Community Guidelines.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                for (final item in _reportReasons)
                  InkWell(
                    onTap: () => setSheetState(() => reason = item),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            reason == item
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: reason == item
                                ? AppColors.accent
                                : AppColors.textFaint,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsController,
                  maxLines: 2,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    counterText: '',
                  ),
                ),
                if (authorId != null &&
                    authorId.isNotEmpty &&
                    authorId != app.activeUserId &&
                    authorId != 'photospot-seed') ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.textPrimary,
                    activeTrackColor: AppColors.accent,
                    value: alsoBlock,
                    onChanged: (v) => setSheetState(() => alsoBlock = v),
                    title: Text(
                      'Block ${authorName?.isNotEmpty == true ? authorName : 'this user'}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'Hide all spots and comments from this person.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                PressButton(
                  semanticLabel: 'Submit report',
                  onTap: () => Navigator.of(sheetContext).pop(true),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Submit report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  final details = detailsController.text;
  detailsController.dispose();

  if (submitted != true) return;
  try {
    await app.reportContent(
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details,
    );
    if (alsoBlock && authorId != null && authorId.isNotEmpty) {
      await app.blockUser(authorId);
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Report received. Thank you.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not send report. Try again later.')),
    );
  }
}
