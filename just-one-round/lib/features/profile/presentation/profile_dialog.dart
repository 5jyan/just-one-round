import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

class ProfileDraft {
  const ProfileDraft({
    required this.nickname,
    required this.birthYear,
    required this.birthMonth,
    required this.gender,
  });

  final String nickname;
  final int? birthYear;
  final int? birthMonth;
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
  int? _birthYear;
  int? _birthMonth;
  ProfileGender? _gender;

  static final _years = [
    for (var year = DateTime.now().year; year >= 1900; year--) year,
  ];

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.profile.nickname);
    _birthYear = widget.profile.birthYear;
    _birthMonth = widget.profile.birthMonth;
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int?>(
                      initialValue: _birthYear,
                      decoration: const InputDecoration(
                        labelText: '출생 연도 · 선택',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('입력 안 함'),
                        ),
                        ..._years.map(
                          (year) => DropdownMenuItem(
                            value: year,
                            child: Text('$year년'),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _birthYear = value;
                        if (value == null) _birthMonth = null;
                        if (value == DateTime.now().year &&
                            (_birthMonth ?? 0) > DateTime.now().month) {
                          _birthMonth = null;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey((_birthYear, _birthMonth)),
                      initialValue: _birthMonth,
                      decoration: const InputDecoration(
                        labelText: '월',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (
                          var month = 1;
                          month <=
                              (_birthYear == DateTime.now().year
                                  ? DateTime.now().month
                                  : 12);
                          month++
                        )
                          DropdownMenuItem(
                            value: month,
                            child: Text('$month월'),
                          ),
                      ],
                      onChanged: _birthYear == null
                          ? null
                          : (value) => setState(() => _birthMonth = value),
                      validator: (_) =>
                          _birthYear != null && _birthMonth == null
                          ? '월을 선택해 주세요.'
                          : null,
                    ),
                  ),
                ],
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
                  const DropdownMenuItem(
                    value: ProfileGender.male,
                    child: Text('남성'),
                  ),
                  const DropdownMenuItem(
                    value: ProfileGender.female,
                    child: Text('여성'),
                  ),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 10),
              const Text(
                '출생 연월과 성별은 입력하지 않아도 게임을 이용할 수 있어요.',
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
                birthYear: _birthYear,
                birthMonth: _birthMonth,
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
