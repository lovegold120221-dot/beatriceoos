import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  StreamSubscription<Uint8List>? _streamSubscription;

  bool get isRecording => _isRecording;

  Future<bool> requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    final cameraStatus = await Permission.camera.request();
    return micStatus.isGranted && cameraStatus.isGranted;
  }

  Future<Stream<Uint8List>?> startRecordingStream() async {
    if (_isRecording) return null;
    final granted = await requestPermissions();
    if (!granted) throw Exception('Microphone permission denied');

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) throw Exception('Recording permission denied');

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );

    final stream = await _recorder.startStream(config);
    _isRecording = true;
    return stream;
  }

  Future<Uint8List> stopRecording() async {
    if (!_isRecording) return Uint8List(0);
    _isRecording = false;
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    final path = await _recorder.stop();
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      } catch (_) {}
    }
    return Uint8List(0);
  }

  Future<void> dispose() async {
    if (_isRecording) {
      await _recorder.stop();
      _isRecording = false;
    }
    await _streamSubscription?.cancel();
  }
}
