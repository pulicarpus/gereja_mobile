import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class ChatWaveform extends StatefulWidget {
  final List<double> samples;
  final bool isMe;
  final double progress; // 👈 PARAMETER BARU UNTUK PROGRESS BERJALAN

  const ChatWaveform({super.key, required this.samples, required this.isMe, this.progress = 0.0});

  @override
  State<ChatWaveform> createState() => _ChatWaveformState();
}

class _ChatWaveformState extends State<ChatWaveform> {
  late PlayerController playerController;

  @override
  void initState() {
    super.initState();
    playerController = PlayerController();
    playerController.preparePlayer(
      path: "",
      noOfSamples: widget.samples.length,
    );
  }

  @override
  void dispose() {
    playerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.samples.isEmpty) return const SizedBox.shrink();

    // 👇 JURUS ILUSI SULTAN: Mewarnai gelombang sesuai progress audio 👇
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          colors: [
            widget.isMe ? const Color(0xFF075E54) : Colors.indigo, // Warna sudah diputar
            widget.isMe ? Colors.black12 : Colors.grey[300]!, // Warna belum diputar
          ],
          stops: [widget.progress, widget.progress],
        ).createShader(bounds);
      },
      child: AudioFileWaveforms(
        size: Size(MediaQuery.of(context).size.width * 0.4, 30),
        playerController: playerController,
        waveformData: widget.samples,
        waveformType: WaveformType.fitWidth,
        playerWaveStyle: const PlayerWaveStyle(
          fixedWaveColor: Colors.white, // Kanvas dasar yang akan ditimpa warna
          spacing: 3.5,
          waveThickness: 2.5,
          waveCap: StrokeCap.round,
        ),
      ),
    );
  }
}