import 'package:flutter_tts/flutter_tts.dart';

import 'errors.dart';

class LocalTtsService {
  LocalTtsService(this._tts);

  final FlutterTts _tts;

  Future<void> speak(String text) async {
    try {
      await _tts.stop();
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.45);
      await _tts.speak(text);
    } catch (e) {
      throw RuntimeFailure(RuntimeErrorType.localUnavailable, 'Falha no TTS local: $e');
    }
  }

  Future<void> stop() => _tts.stop();
}
