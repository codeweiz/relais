import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/agent_status.dart';

/// Colors for each provider.
Color providerColor(String provider) {
  switch (provider) {
    case 'claude-code':
    case 'claude':
      return const Color(0xFF7C7CFF);
    case 'gemini':
    case 'gemini-cli':
      return const Color(0xFF4285F4);
    case 'opencode':
      return const Color(0xFF00BCD4);
    case 'codex':
      return const Color(0xFF4CD137);
    default:
      return const Color(0xFF9E9E9E);
  }
}

/// Status ring color.
Color statusColor(String status) {
  switch (status) {
    case 'idle':
      return const Color(0xFF22C55E);
    case 'working':
      return const Color(0xFFA855F7);
    case 'thinking':
      return const Color(0xFF3B82F6);
    case 'tool_calling':
      return const Color(0xFFF97316);
    case 'error':
      return const Color(0xFFEF4444);
    default:
      return const Color(0xFF22C55E);
  }
}

/// Provider initial letter for avatar.
String providerInitial(String provider) {
  switch (provider) {
    case 'claude-code':
    case 'claude':
      return 'C';
    case 'gemini':
    case 'gemini-cli':
      return 'G';
    case 'opencode':
      return 'O';
    case 'codex':
      return 'X';
    default:
      return '?';
  }
}

/// Slot position for an agent given index and total count.
Offset slotPosition(int index, int total, Size size) {
  final cols = total <= 4 ? total : (total <= 8 ? 4 : (total / 3).ceil());
  final rows = (total / cols).ceil();
  final slotW = size.width / cols;
  final slotH = size.height / rows;
  final row = index ~/ cols;
  final col = index % cols;
  return Offset(
    col * slotW + slotW / 2,
    row * slotH + slotH / 2,
  );
}

/// Paints the office floor grid.
class OfficePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    // Draw grid
    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Paints a single agent: avatar circle, status ring, name label, activity bubble.
class AgentPainter extends CustomPainter {
  final AgentStatusInfo agent;
  final double animationValue; // 0.0 - 1.0 for status ring animation

  AgentPainter({required this.agent, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    const avatarRadius = 28.0;

    // Desk outline below avatar
    final deskRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, avatarRadius + 14),
        width: 70,
        height: 12,
      ),
      const Radius.circular(4),
    );
    final deskPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(deskRect, deskPaint);

    // Avatar circle
    final avatarPaint = Paint()
      ..color = providerColor(agent.provider)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, avatarRadius, avatarPaint);

    // Provider initial letter
    final textPainter = TextPainter(
      text: TextSpan(
        text: providerInitial(agent.provider),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    // Status ring
    final ringColor = statusColor(agent.status);
    double ringOpacity = 1.0;
    if (agent.status == 'working' || agent.status == 'thinking') {
      ringOpacity = 0.4 + 0.6 * ((math.sin(animationValue * math.pi * 2) + 1) / 2);
    } else if (agent.status == 'error') {
      ringOpacity = animationValue > 0.5 ? 1.0 : 0.2;
    }

    final ringPaint = Paint()
      ..color = ringColor.withValues(alpha: ringOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    if (agent.status == 'tool_calling') {
      // Dashed rotating ring
      final dashPath = Path()
        ..addArc(
          Rect.fromCircle(center: center, radius: avatarRadius + 4),
          animationValue * math.pi * 2,
          math.pi * 1.5,
        );
      canvas.drawPath(dashPath, ringPaint);
    } else {
      canvas.drawCircle(center, avatarRadius + 4, ringPaint);
    }

    // Name label
    final namePainter = TextPainter(
      text: TextSpan(
        text: agent.name,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    namePainter.paint(
      canvas,
      Offset(center.dx - namePainter.width / 2, center.dy + avatarRadius + 24),
    );

    // Activity bubble (only if non-empty)
    if (agent.activity.isNotEmpty) {
      final bubblePainter = TextPainter(
        text: TextSpan(
          text: agent.activity,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: 120);

      final bubbleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy - avatarRadius - 22),
          width: bubblePainter.width + 16,
          height: bubblePainter.height + 10,
        ),
        const Radius.circular(8),
      );
      final bubbleBg = Paint()
        ..color = providerColor(agent.provider).withValues(alpha: 0.15);
      final bubbleBorder = Paint()
        ..color = providerColor(agent.provider).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(bubbleRect, bubbleBg);
      canvas.drawRRect(bubbleRect, bubbleBorder);

      bubblePainter.paint(
        canvas,
        Offset(
          center.dx - bubblePainter.width / 2,
          center.dy - avatarRadius - 22 - bubblePainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant AgentPainter oldDelegate) {
    if (agent.status == 'idle') return false;
    return oldDelegate.agent.status != agent.status ||
        oldDelegate.agent.activity != agent.activity ||
        oldDelegate.animationValue != animationValue;
  }
}
