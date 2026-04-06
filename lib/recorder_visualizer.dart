import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class RecorderVisualizer extends StatelessWidget {
  final RecorderController controller;
  const RecorderVisualizer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AudioWaveforms(
      size: Size(MediaQuery.of(context).size.width * 0.4, 30),
      recorderController: controller,
      enableGesture: false,
      waveStyle: const WaveStyle(
        waveColor: Colors.redAccent,
        // 👇 JURUS KUNCI: Spacing harus lebih besar dari thickness (default 3.0) 👇
        spacing: 4.0, 
        waveThickness: 2.5, // Kita kecilkan dikit biar makin estetik
        showMiddleLine: false,
        extendWaveform: true,
        waveCap: StrokeCap.round,
      ),
    );
  }
}