import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../core/logger.dart';

class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;
  double _volumeLevel = 1.0;
  final List<Uint8List> _bufferQueue = [];

  StreamSubscription? _stateSub;

  bool get isPlaying => _isPlaying;
  double get volumeLevel => _volumeLevel;

  AudioPlayerService() {
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
  }

  void setVolume(double volume) {
    _volumeLevel = volume.clamp(0.0, 1.0);
    _player.setVolume(_volumeLevel);
  }

  void enqueueAudio(List<int> pcmData) {
    _bufferQueue.add(Uint8List.fromList(pcmData));
    if (!_isPlaying) {
      _playNext();
    }
  }

  Future<void> _playNext() async {
    if (_bufferQueue.isEmpty) return;
    final data = _bufferQueue.removeAt(0);
    try {
      final wavData = _pcmToWav(data, sampleRate: 24000);
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/beatrice_audio_${DateTime.now().millisecondsSinceEpoch}.wav');
      await file.writeAsBytes(wavData);
      await _player.play(DeviceFileSource(file.path));
    } catch (e, s) {
      appLogger.w('Audio playback failed', error: e, stackTrace: s);
      _playNext();
    }
  }

  void clearBuffer() {
    _bufferQueue.clear();
    _player.stop();
    _isPlaying = false;
    notifyListeners();
  }

  Uint8List _pcmToWav(List<int> pcmData, {int sampleRate = 24000}) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    const headerSize = 44;
    final totalSize = headerSize + dataSize;

    final wav = List<int>.filled(totalSize, 0);
    wav[0] = 0x52; wav[1] = 0x49; wav[2] = 0x46; wav[3] = 0x46;
    _writeInt32(wav, 4, totalSize - 8);
    wav[8] = 0x57; wav[9] = 0x41; wav[10] = 0x56; wav[11] = 0x45;
    wav[12] = 0x66; wav[13] = 0x6D; wav[14] = 0x74; wav[15] = 0x20;
    _writeInt32(wav, 16, 16);
    _writeInt16(wav, 20, 1);
    _writeInt16(wav, 22, numChannels);
    _writeInt32(wav, 24, sampleRate);
    _writeInt32(wav, 28, byteRate);
    _writeInt16(wav, 32, blockAlign);
    _writeInt16(wav, 34, bitsPerSample);
    wav[36] = 0x64; wav[37] = 0x61; wav[38] = 0x74; wav[39] = 0x61;
    _writeInt32(wav, 40, dataSize);
    for (var i = 0; i < dataSize; i++) {
      wav[44 + i] = pcmData[i];
    }
    return Uint8List.fromList(wav);
  }

  void _writeInt16(List<int> buffer, int offset, int value) {
    buffer[offset] = value & 0xFF;
    buffer[offset + 1] = (value >> 8) & 0xFF;
  }

  void _writeInt32(List<int> buffer, int offset, int value) {
    buffer[offset] = value & 0xFF;
    buffer[offset + 1] = (value >> 8) & 0xFF;
    buffer[offset + 2] = (value >> 16) & 0xFF;
    buffer[offset + 3] = (value >> 24) & 0xFF;
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
