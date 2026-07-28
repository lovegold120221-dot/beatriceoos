import 'dart:typed_data';

/// Audio recording is stubbed in this initial port.
/// Gemini Live Audio streaming requires a WebSocket-based Live API client
/// that is not available in the standard google_generative_ai package (v0.4.x).
///
/// Future enhancement: implement direct WebSocket connection to Gemini Live API
/// for bidirectional audio streaming.
class AudioService {
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<bool> requestPermissions() async {
    return true;
  }

  Future<void> startRecording() async {
    _isRecording = true;
  }

  Future<Uint8List> stopRecording() async {
    _isRecording = false;
    return Uint8List(0);
  }

  Future<void> dispose() async {
    _isRecording = false;
  }
}
