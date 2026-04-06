import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class ChatWaveform extends StatelessWidget {
  final List<double> samples;
  final bool isMe;

  const ChatWaveform({super.key, required this.samples, required this.isMe});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) return const SizedBox.shrink();

    return AudioFileWaveforms(
      size: Size(MediaQuery.of(context).size.width * 0.4, 30),
      playerController: PlayerController(), // Hanya untuk render visual
      waveformType: WaveformType.fitWidth,
      playerWaveStyle: PlayerWaveStyle(
        fixedWaveColor: isMe ? Colors.black12 : Colors.grey[300]!,
        liveWaveColor: isMe ? const Color(0xFF075E54) : Colors.indigo,
        spacing: 3.5,
        waveThickness: 2.5,
        waveCap: StrokeCap.round,
      ),
      samples: samples,
    );
  }
}