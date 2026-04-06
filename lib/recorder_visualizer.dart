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
      // 👇 waveformType SUDAH DIHAPUS DI VERSI BARU, JADI KITA HAPUS JUGA 👇
      waveStyle: const WaveStyle(
        waveColor: Colors.redAccent,
        spacing: 3.0,
        showMiddleLine: false,
        extendWaveform: true,
        // 👇 showVisualizerLpBar JUGA SUDAH GANTI, KITA HAPUS SAJA 👇
        waveCap: StrokeCap.round,
      ),
    );
  }
}