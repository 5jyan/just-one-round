import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/licenses/Galmuri-OFL-1.1.txt',
    );
    yield LicenseEntryWithLineBreaks(['Galmuri'], license);
  });
  runApp(const ProviderScope(child: JustOneRoundApp()));
}
