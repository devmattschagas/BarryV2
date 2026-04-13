import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'errors.dart';

class LocalSttService {
  LocalSttService(this._speech);

  final SpeechToText _speech;
  bool _isInitialized = false;

  Future<void> startListening({
    required void Function(String partial, bool isFinal) onTranscript,
    required void Function(RuntimeFailure failure) onError,
  }) async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    final available = _isInitialized
        ? true
        : await _speech.initialize(
            onError: (SpeechRecognitionError error) {
              final message = error.permanent
                  ? 'Erro STT local permanente: ${error.errorMsg}'
                  : 'Erro STT local: ${error.errorMsg}';
              onError(RuntimeFailure(RuntimeErrorType.localUnavailable, message));
            },
          );
    _isInitialized = available;

    if (!available) {
      onError(
        RuntimeFailure(
          RuntimeErrorType.localUnavailable,
          'STT local indisponível neste dispositivo. Verifique permissão de microfone.',
        ),
      );
      return;
    }

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        onTranscript(result.recognizedWords, result.finalResult);
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> stop() => _speech.stop();
}
