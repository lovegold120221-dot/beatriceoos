import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final Record _recorder = Record();
  bool _isRecording = false;
  Stream<Uint8List>? _audioStream;
  late StreamSubscription<Uint8List>? _streamSubscription;

  bool get isRecording => _isRecording;

  Future<bool> requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    final cameraStatus = await Permission.camera.request();
    final speakerStatus = await Permission.speaker.request();
    return micStatus.isGranted && cameraStatus.isGranted;
  }

  Future<void> startRecording() async {
    if (_isRecording) return;
    final granted = await requestPermissions();
    if (!granted) throw Exception('Microphone permission denied');

    await _recorder.start(
      encoder: AudioEncoder.pcm16bits,
      samplingRate: 16000,
      numChannels: 1,
      bitRate: 64000,
    );
    _isRecording = true;
  }

  Future<Uint8List> stopRecording() async {
    if (!_isRecording) return Uint8List(0);
    _isRecording = false;
    final audio = await _recorder.stop();
    return audio ?? Uint8List(0);
  }

  Stream<Uint8List>? get audioStream {
    if (_audioStream == null) {
      _audioStream = _recorder.onRecordingStatusChanged.map((status) {
        if (status is RecordingStatus) {
          return status.buffer;
        }
        return Uint8List(0);
      });
    }
    return _audioStream;
  }

  Future<void> dispose() async {
    if (_isRecording) await stopRecording();
    await _recorder.dispose();
  }
}