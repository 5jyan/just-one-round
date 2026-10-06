import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

class PixelButton extends StatefulWidget {
  const PixelButton({
    required this.label,
    required this.onPressed,
    this.onDisabledPressed,
    this.icon,
    this.activateOnTapDown = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onDisabledPressed;
  final IconData? icon;
  final bool activateOnTapDown;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  var _pressed = false;
  int? _activePointer;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      constraints: const BoxConstraints(minHeight: 56),
      transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
      decoration: BoxDecoration(
        color: enabled ? AppColors.primary : AppColors.surfaceLight,
        border: Border.all(color: AppColors.text, width: 2),
        boxShadow: _pressed || !enabled
            ? null
            : const [
                BoxShadow(color: AppColors.primaryShadow, offset: Offset(0, 6)),
              ],
      ),
      child: ClipPath(
        clipper: const PixelCornerClipper(corner: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon case final icon?) ...[
                Icon(icon, color: AppColors.backgroundDeep, size: 22),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: WordSafeText(
                    widget.label,
                    singleLine: true,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.backgroundDeep,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final interaction = widget.activateOnTapDown
        ? Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: enabled
                ? (event) {
                    if (_activePointer != null) return;
                    _activePointer = event.pointer;
                    _setPressed(true);
                    widget.onPressed?.call();
                  }
                : null,
            onPointerUp: (event) {
              if (_activePointer != event.pointer) return;
              _activePointer = null;
              _setPressed(false);
            },
            onPointerCancel: (event) {
              if (_activePointer != event.pointer) return;
              _activePointer = null;
              _setPressed(false);
            },
            child: content,
          )
        : GestureDetector(
            onTapDown: enabled ? (_) => _setPressed(true) : null,
            onTapCancel: enabled ? () => _setPressed(false) : null,
            onTapUp: enabled
                ? (_) {
                    _setPressed(false);
                    widget.onPressed?.call();
                  }
                : null,
            onTap: enabled ? null : widget.onDisabledPressed,
            child: content,
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: widget.activateOnTapDown && enabled
          ? widget.onPressed
          : !enabled
          ? widget.onDisabledPressed
          : null,
      child: interaction,
    );
  }
}
