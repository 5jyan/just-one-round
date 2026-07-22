import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';

Future<String?> showNicknameDialog(
  BuildContext context, {
  String? initialNickname,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NicknameDialog(initialNickname: initialNickname),
  );
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({this.initialNickname});

  final String? initialNickname;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('랭킹 닉네임'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('nickname-field'),
          controller: _controller,
          autofocus: true,
          maxLength: 12,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: '2~12자로 입력하세요',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final length = value?.trim().characters.length ?? 0;
            if (length < 2 || length > 12) return '2~12자로 입력해 주세요.';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('나중에'),
        ),
        FilledButton(
          key: const Key('save-nickname'),
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }
}
