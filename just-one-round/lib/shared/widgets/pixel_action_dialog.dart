import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

/// Stable hooks shared by confirmation and completion dialogs.
abstract final class PixelActionDialogKeys {
  static const dialog = Key('pixel-action-dialog');
  static const panel = Key('pixel-action-dialog-panel');
  static const title = Key('pixel-action-dialog-title');
  static const message = Key('pixel-action-dialog-message');
  static const cancel = Key('pixel-action-dialog-cancel');
  static const confirm = Key('pixel-action-dialog-confirm');
}

/// A compact, accessible action dialog that follows the app's pixel UI.
///
/// Confirmation dialogs provide an explicit cancel action. Completion dialogs
/// omit it and can be dismissed only with their confirmation action (or the
/// route's system back action when used directly).
class PixelActionDialog extends StatelessWidget {
  const PixelActionDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
    this.onCancel,
    this.confirmLabel = '확인',
    this.cancelLabel = '취소',
    this.icon,
    this.isCompletion = false,
    this.panelKey = PixelActionDialogKeys.panel,
    this.titleKey = PixelActionDialogKeys.title,
    this.messageKey = PixelActionDialogKeys.message,
    this.cancelKey = PixelActionDialogKeys.cancel,
    this.confirmKey = PixelActionDialogKeys.confirm,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final String confirmLabel;
  final String cancelLabel;
  final IconData? icon;
  final bool isCompletion;
  final Key panelKey;
  final Key titleKey;
  final Key messageKey;
  final Key cancelKey;
  final Key confirmKey;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: Semantics(
      namesRoute: true,
      scopesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: PixelPanel(
        key: panelKey,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon case final icon?) ...[
              Icon(icon, color: AppColors.primary, size: 30),
              const SizedBox(height: 8),
            ],
            WordSafeText(
              title,
              key: titleKey,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            WordSafeText(
              message,
              key: messageKey,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            if (isCompletion)
              PixelButton(
                key: confirmKey,
                label: confirmLabel,
                onPressed: onConfirm,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: cancelKey,
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.text,
                        minimumSize: const Size.fromHeight(56),
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 2,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Galmuri',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: WordSafeText(cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PixelButton(
                      key: confirmKey,
                      label: confirmLabel,
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

Future<bool?> showPixelConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '확인',
  String cancelLabel = '취소',
  IconData? icon,
  bool barrierDismissible = true,
  Key? dialogKey,
  Key? panelKey,
  Key? titleKey,
  Key? messageKey,
  Key? cancelKey,
  Key? confirmKey,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (dialogContext) => PixelActionDialog(
    key: dialogKey ?? PixelActionDialogKeys.dialog,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    icon: icon,
    panelKey: panelKey ?? PixelActionDialogKeys.panel,
    titleKey: titleKey ?? PixelActionDialogKeys.title,
    messageKey: messageKey ?? PixelActionDialogKeys.message,
    cancelKey: cancelKey ?? PixelActionDialogKeys.cancel,
    confirmKey: confirmKey ?? PixelActionDialogKeys.confirm,
    onCancel: () => Navigator.of(dialogContext).pop(false),
    onConfirm: () => Navigator.of(dialogContext).pop(true),
  ),
);

Future<void> showPixelCompletionDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '확인',
  IconData? icon,
  bool barrierDismissible = false,
  Key? dialogKey,
  Key? panelKey,
  Key? titleKey,
  Key? messageKey,
  Key? confirmKey,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => PixelActionDialog(
      key: dialogKey ?? PixelActionDialogKeys.dialog,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      isCompletion: true,
      panelKey: panelKey ?? PixelActionDialogKeys.panel,
      titleKey: titleKey ?? PixelActionDialogKeys.title,
      messageKey: messageKey ?? PixelActionDialogKeys.message,
      confirmKey: confirmKey ?? PixelActionDialogKeys.confirm,
      onConfirm: () => Navigator.of(dialogContext).pop(),
    ),
  );
}
