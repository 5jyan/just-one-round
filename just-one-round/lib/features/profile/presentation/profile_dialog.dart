import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

class ProfileDraft {
  const ProfileDraft({
    required this.nickname,
    required this.birthDecade,
    required this.gender,
  });

  final String nickname;
  final int? birthDecade;
  final ProfileGender? gender;
}

Future<ProfileDraft?> showProfileDialog(
  BuildContext context, {
  required UserProfile profile,
}) {
  return showDialog<ProfileDraft>(
    context: context,
    builder: (context) => _ProfileDialog(profile: profile),
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profile});

  final UserProfile profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;
  int? _birthDecade;
  ProfileGender? _gender;

  static final _decades = [
    for (var decade = 2010; decade >= 1940; decade -= 10) decade,
  ];

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.profile.nickname);
    _birthDecade = widget.profile.birthDecade;
    _gender = widget.profile.gender;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('내 프로필'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nicknameController,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: '닉네임',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final length = value?.trim().characters.length ?? 0;
                  if (length < 2 || length > 12) return '2~12자로 입력해 주세요.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _birthDecade,
                decoration: const InputDecoration(
                  labelText: '연령대 · 선택',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('입력하지 않음')),
                  ..._decades.map(
                    (decade) => DropdownMenuItem(
                      value: decade,
                      child: Text('$decade년대생'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _birthDecade = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProfileGender?>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: '성별 · 선택',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('입력하지 않음')),
                  ...ProfileGender.values.map(
                    (gender) => DropdownMenuItem(
                      value: gender,
                      child: Text(gender.label),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 10),
              const Text(
                '연령대와 성별은 입력하지 않아도 게임을 이용할 수 있어요.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              ProfileDraft(
                nickname: _nicknameController.text.trim(),
                birthDecade: _birthDecade,
                gender: _gender,
              ),
            );
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}
