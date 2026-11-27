import 'dart:async';

import 'package:flutter/services.dart';

/// Copia valores sensíveis e limpa a área de transferência após um tempo,
/// se ela ainda contiver o mesmo valor.
abstract final class SensitiveClipboard {
  static const Duration clearAfter = Duration(seconds: 30);
  static Timer? _timer;

  static Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _timer?.cancel();
    _timer = Timer(clearAfter, () => unawaited(_clearIfUnchanged(value)));
  }

  static Future<void> _clearIfUnchanged(String value) async {
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}
