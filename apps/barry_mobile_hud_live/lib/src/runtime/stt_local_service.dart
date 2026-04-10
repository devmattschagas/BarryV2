import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'errors.dart';

class LocalSttService {
  LocalSttService(this._speech);

  final SpeechToText _speech;

  Future<void> startListening({
    required void Function(String partial, bool isFinal) onTranscript,
    required void Function(RuntimeFailure failure) onError,
  }) async {
    final available = await _speech.initialize(
      onError: (SpeechRecognitionError error) {
        onError(RuntimeFailure(RuntimeErrorType.localUnavailable, 'Erro STT local: ${error.errorMsg}'));
      },
    );

    if (!available) {
      onError(RuntimeFailure(RuntimeErrorType.localUnavailable, 'STT local indisponível neste dispositivo.'));
      return;
    }

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        onTranscript(result.recognizedWords, result.finalResult);
      },
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.dictation,
    );
  }

  Future<void> stop() => _speech.stop();
}
