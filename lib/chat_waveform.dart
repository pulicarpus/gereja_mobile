import 'dart:math' as math;
import 'package:flutter/material.dart';

class ChatWaveform extends StatelessWidget {
  final List<double> samples;
  final bool isMe;
  final double progress;

  const ChatWaveform({
    super.key,
    required this.samples,
    required this.isMe,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Text(
        "Voice Note",
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: Colors.black54,
        ),
      );
    }

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.4,
      height: 30,
      child: CustomPaint(
        painter: _WaveformPainter(
          samples: samples,
          progress: progress.clamp(0.0, 1.0),
          playedColor: isMe ? const Color(0xFF075E54) : Colors.indigo,
          pendingColor: isMe ? Colors.black26 : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color pendingColor;

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.pendingColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final maxAbs = samples
        .map((e) => e.isFinite ? e.abs() : 0.0)
        .fold<double>(0.0, math.max);
    final divisor = maxAbs <= 0 ? 1.0 : maxAbs;
    final count = samples.length;
    final spacing = size.width / count;
    final centerY = size.height / 2;
    final playedUntil = (count * progress).floor();

    final playedPaint = Paint()
      ..color = playedColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final pendingPaint = Paint()
      ..color = pendingColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final normalized = (samples[i].isFinite ? samples[i].abs() : 0.0) / divisor;
      final height = math.max(4.0, normalized * size.height);
      final x = (i + 0.5) * spacing;
      final paint = i < playedUntil ? playedPaint : pendingPaint;
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.samples != samples ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.pendingColor != pendingColor;
  }
}
