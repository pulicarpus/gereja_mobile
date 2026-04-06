import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class ChatWaveform extends StatefulWidget {
  final List<double> samples;
  final bool isMe;

  const ChatWaveform({super.key, required this.samples, required this.isMe});

  @override
  State<ChatWaveform> createState() => _ChatWaveformState();
}

class _ChatWaveformState extends State<ChatWaveform> {
  late PlayerController playerController;

  @override
  void initState() {
    super.initState();
    playerController = PlayerController();
    // Memasukkan data sampel ke dalam controller
    playerController.preparePlayer(
      path: "", // Kosongkan saja karena kita cuma mau gambar statis
      noOfSamples: widget.samples.length,
    );
    playerController.updateFrequency = UpdateFrequency.low;
  }

  @override
  void dispose() {
    playerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.samples.isEmpty) return const SizedBox.shrink();

    return AudioFileWaveforms(
      size: Size(MediaQuery.of(context).size.width * 0.4, 30),
      playerController: playerController,
      waveformType: WaveformType.fitWidth,
      playerWaveStyle: PlayerWaveStyle(
        fixedWaveColor: widget.isMe ? Colors.black12 : Colors.grey[300]!,
        liveWaveColor: widget.isMe ? const Color(0xFF075E54) : Colors.indigo,
        spacing: 3.5,
        waveThickness: 2.5,
        waveCap: StrokeCap.round,
      ),
    );
  }
}