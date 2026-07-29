import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../core/logger.dart';

class AudioRecorderService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  double _volume = 0.0;
  bool _isSpeechDetected = false;
  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<Uint8List>? _recordStreamSub;

  final _audioDataController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get onAudioData => _audioDataController.stream;

  bool get isRecording => _isRecording;
  double get volume => _volume;
  bool get isSpeechDetected => _isSpeechDetected;

  static const double _speechThreshold = 0.04;

  Future<bool> requestPermissions() async {
    try {
      return await _recorder.hasPermission();
    } catch (e, s) {
      appLogger.w('Audio permission request failed', error: e, stackTrace: s);
      return false;
    }
  }

  Future<void> startRecording() async {
    if (_isRecording) return;
    final granted = await requestPermissions();
    if (!granted) {
      appLogger.w('Audio recording permission denied');
      return;
    }

    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 16000,
        autoGain: false,
        echoCancel: true,
        noiseSuppress: false,
      ));

      _recordStreamSub = stream.listen((data) {
        _audioDataController.add(data.toList());
      });

      _isRecording = true;
      notifyListeners();

      _amplitudeSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
        _volume = math.min(a.current / 16000.0, 1.0);
        _isSpeechDetected = a.current > _speechThreshold;
        notifyListeners();
      });
    } catch (e, s) {
      appLogger.w('Audio recording start failed', error: e, stackTrace: s);
    }
  }

  Future<List<int>> stopRecording() async {
    if (!_isRecording) return <int>[];
    _amplitudeSub?.cancel();
    _recordStreamSub?.cancel();
    try {
      await _recorder.stop();
    } catch (e, s) {
      appLogger.w('Audio recording stop failed', error: e, stackTrace: s);
    }
    _isRecording = false;
    _volume = 0.0;
    _isSpeechDetected = false;
    notifyListeners();
    return <int>[];
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _recordStreamSub?.cancel();
    _recorder.dispose();
    _audioDataController.close();
    super.dispose();
  }
}
