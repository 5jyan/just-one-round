import 'package:flutter/services.dart';

const _environmentChannel = MethodChannel('just_one_round/app_environment');

Future<bool> isIosSimulator() async {
  try {
    return await _environmentChannel.invokeMethod<bool>('isIosSimulator') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
