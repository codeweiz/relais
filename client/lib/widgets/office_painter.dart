import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/agent_status.dart';

// ── Grouped layout ───────────────────────────────────────────────────────────

/// Layout result for a group of agents.
class GroupLayout {
  final String provider;
  final String displayName;
  final double yOffset;
  final double height;
  final List<Offset> positions;

  const GroupLayout({
    required this.provider,
    required this.displayName,
    required this.yOffset,
    required this.height,
    required this.positions,
  });
}

/// Compute grouped layout for all agents.
List<GroupLayout> computeGroupedLayout(
    List<AgentStatusInfo> agents, double canvasWidth) {
  const slotW = 140.0;
  const slotH = 150.0;
  const headerH = 32.0;
  const groupPadding = 16.0;

  final grouped = <String, List<AgentStatusInfo>>{};
  for (final a in agents) {
    grouped.putIfAbsent(a.provider, () => []).add(a);
  }

  final layouts = <GroupLayout>[];
  double currentY = groupPadding;

  for (final entry in grouped.entries) {
    final count = entry.value.length;
    final cols = (canvasWidth / slotW).floor().clamp(1, count);
    final rows = (count / cols).ceil();
    final groupHeight = headerH + rows * slotH;

    final positions = <Offset>[];
    for (var i = 0; i < count; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      positions.add(Offset(
        col * slotW + slotW / 2,
        currentY + headerH + row * slotH + slotH / 2,
      ));
    }

    layouts.add(GroupLayout(
      provider: entry.key,
      displayName: _providerDisplayName(entry.key),
      yOffset: currentY,
      height: groupHeight,
      positions: positions,
    ));

    currentY += groupHeight + groupPadding;
  }
  return layouts;
}

/// Total content height from grouped layout.
double computeGroupedContentHeight(List<GroupLayout> layouts) {
  if (layouts.isEmpty) return 0;
  final last = layouts.last;
  return last.yOffset + last.height + 16;
}

String _providerDisplayName(String id) {
  switch (id) {
    case 'claude-code':
      return 'Claude Code';
    case 'codex':
      return 'Codex CLI';
    case 'gemini':
    case 'gemini-cli':
      return 'Gemini CLI';
    case 'opencode':
      return 'OpenCode';
    default:
      return id;
  }
}

// ── Provider helpers ──────────────────────────────────────────────────────────

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

/// Status ring / glow color.
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
  const slotW = 160.0;
  const slotH = 200.0;
  final cols = total <= 4 ? total : (total <= 8 ? 4 : (total / 3).ceil());
  final rows = (total / cols).ceil();
  final cellW = size.width / cols;
  final cellH = size.height / rows;
  // Centre each agent in its cell but respect minimum slot dimensions.
  final effectiveCellW = cellW < slotW ? slotW : cellW;
  final effectiveCellH = cellH < slotH ? slotH : cellH;
  final row = index ~/ cols;
  final col = index % cols;
  return Offset(
    col * effectiveCellW + effectiveCellW / 2,
    row * effectiveCellH + effectiveCellH / 2,
  );
}

// ── Background painter ────────────────────────────────────────────────────────

/// Paints the "Digital Workforce" office background with a subtle grid.
/// Accepts theme-aware colors so it works in both light and dark mode.
class OfficePainter extends CustomPainter {
  /// Background gradient start color (top-left).
  final Color backgroundColor;

  /// Background gradient end color (bottom-right).
  final Color backgroundColorEnd;

  /// Grid line color (should be very low opacity).
  final Color gridColor;

  /// Grouped layout sections to draw headers for.
  final List<GroupLayout> groups;

  const OfficePainter({
    required this.backgroundColor,
    required this.backgroundColorEnd,
    required this.gridColor,
    this.groups = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Gradient background
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [backgroundColor, backgroundColorEnd],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Very faint grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw group headers
    for (final group in groups) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: group.displayName,
          style: TextStyle(
            color: gridColor.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(12, group.yOffset + 8));
    }
  }

  @override
  bool shouldRepaint(covariant OfficePainter old) =>
      old.backgroundColor != backgroundColor ||
      old.backgroundColorEnd != backgroundColorEnd ||
      old.gridColor != gridColor ||
      old.groups.length != groups.length;
}

// ── Agent painter ─────────────────────────────────────────────────────────────

/// Paints a single "Digital Employee": face, name badge, desk, status label,
/// and an optional activity speech bubble.
class AgentPainter extends CustomPainter {
  final AgentStatusInfo agent;

  /// 0.0–1.0, driven by the continuous 2-second animation controller.
  final double animationValue;

  /// True for 150 ms every ~3 s — used to render closed eyes.
  final bool isBlinking;

  /// Whether the activity bubble should show its full text or be truncated.
  final bool isBubbleExpanded;

  /// Color for text labels (name badge, status label, bubble text).
  /// Defaults to white for dark backgrounds, should be dark for light themes.
  final Color labelColor;

  AgentPainter({
    required this.agent,
    required this.animationValue,
    required this.isBlinking,
    required this.isBubbleExpanded,
    this.labelColor = Colors.white,
  });

  // Layout constants
  static const double _faceW = 54.0;
  static const double _faceH = 48.0;
  static const double _faceRadius = 10.0;

  static const double _badgeH = 18.0;
  static const double _badgeRadius = 5.0;

  static const double _deskW = 72.0;
  static const double _deskEndH = 8.0;

  // Vertical offsets from a logical "top" of the slot (y=0 of the widget)
  // We place the face centred around y=70 in the slot (slot height = 200).
  static const double _faceCY = 80.0; // face centre Y
  static const double _badgeTopOffset = _faceH / 2 + 6;
  static const double _deskTopOffset = _faceH / 2 + 6 + _badgeH + 8;
  static const double _statusLabelOffset = _deskTopOffset + _deskEndH + 12;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = _faceCY;

    final pColor = providerColor(agent.provider);
    final sColor = statusColor(agent.status);

    _drawGlow(canvas, cx, cy, sColor);
    _drawFace(canvas, cx, cy, pColor);
    _drawEyes(canvas, cx, cy);
    _drawMouth(canvas, cx, cy);
    _drawNameBadge(canvas, cx, cy, pColor);
    _drawDesk(canvas, cx, cy);
    _drawStatusLabel(canvas, cx, cy, sColor);
    if (agent.activity.isNotEmpty) {
      _drawActivityBubble(canvas, cx, cy, pColor);
    }
  }

  // ── Glow behind face ──────────────────────────────────────────────────────

  void _drawGlow(Canvas canvas, double cx, double cy, Color sColor) {
    double glowRadius = 48.0;
    double glowAlpha = 0.18;

    switch (agent.status) {
      case 'idle':
        glowAlpha = 0.10;
        glowRadius = 42;
      case 'working':
        glowAlpha = 0.35;
        glowRadius = 54;
      case 'thinking':
        // Pulsing alpha
        glowAlpha = 0.15 + 0.20 * ((math.sin(animationValue * math.pi * 2) + 1) / 2);
        glowRadius = 52;
      case 'tool_calling':
        glowAlpha = 0.28;
        glowRadius = 50;
      case 'error':
        // Blinking glow
        glowAlpha = animationValue > 0.5 ? 0.40 : 0.10;
        glowRadius = 50;
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          sColor.withValues(alpha: glowAlpha),
          sColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowRadius));
    canvas.drawCircle(Offset(cx, cy), glowRadius, glowPaint);
  }

  // ── Face rectangle ────────────────────────────────────────────────────────

  void _drawFace(Canvas canvas, double cx, double cy, Color pColor) {
    final faceRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: _faceW,
        height: _faceH,
      ),
      const Radius.circular(_faceRadius),
    );

    final fillPaint = Paint()
      ..color = pColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(faceRect, fillPaint);

    final borderPaint = Paint()
      ..color = pColor.withValues(alpha: 0.60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(faceRect, borderPaint);
  }

  // ── Eyes ──────────────────────────────────────────────────────────────────

  void _drawEyes(Canvas canvas, double cx, double cy) {
    const eyeOffsetX = 11.0;
    const eyeOffsetY = -6.0;
    const eyeR = 4.0;

    final eyePaint = Paint()
      ..color = labelColor.withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;

    if (isBlinking) {
      // Closed eyes: thin horizontal lines
      final linePaint = Paint()
        ..color = labelColor.withValues(alpha: 0.80)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(cx - eyeOffsetX - eyeR * 0.7, cy + eyeOffsetY),
        Offset(cx - eyeOffsetX + eyeR * 0.7, cy + eyeOffsetY),
        linePaint,
      );
      canvas.drawLine(
        Offset(cx + eyeOffsetX - eyeR * 0.7, cy + eyeOffsetY),
        Offset(cx + eyeOffsetX + eyeR * 0.7, cy + eyeOffsetY),
        linePaint,
      );
    } else {
      canvas.drawCircle(Offset(cx - eyeOffsetX, cy + eyeOffsetY), eyeR, eyePaint);
      canvas.drawCircle(Offset(cx + eyeOffsetX, cy + eyeOffsetY), eyeR, eyePaint);

      // Pupils
      final pupilPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.50)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx - eyeOffsetX + 1, cy + eyeOffsetY + 1), 1.8, pupilPaint);
      canvas.drawCircle(Offset(cx + eyeOffsetX + 1, cy + eyeOffsetY + 1), 1.8, pupilPaint);
    }
  }

  // ── Mouth ─────────────────────────────────────────────────────────────────

  void _drawMouth(Canvas canvas, double cx, double cy) {
    const mouthW = 16.0;
    const mouthOffsetY = 8.0;

    final mouthPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final path = Path();
    switch (agent.status) {
      case 'working':
        // Flat focused line
        path.moveTo(cx - mouthW / 2, cy + mouthOffsetY);
        path.lineTo(cx + mouthW / 2, cy + mouthOffsetY);

      case 'thinking':
        // Wavy "hmm..."
        final wave = math.sin(animationValue * math.pi * 2) * 2.0;
        path.moveTo(cx - mouthW / 2, cy + mouthOffsetY + wave);
        path.cubicTo(
          cx - mouthW / 4,
          cy + mouthOffsetY - wave,
          cx + mouthW / 4,
          cy + mouthOffsetY + wave,
          cx + mouthW / 2,
          cy + mouthOffsetY - wave,
        );

      case 'tool_calling':
        // Small "O" circle
        canvas.drawCircle(
          Offset(cx, cy + mouthOffsetY),
          4.0,
          mouthPaint,
        );
        return;

      case 'error':
        // Frown — downward arc
        path.moveTo(cx - mouthW / 2, cy + mouthOffsetY + 2);
        path.quadraticBezierTo(
          cx,
          cy + mouthOffsetY - 5,
          cx + mouthW / 2,
          cy + mouthOffsetY + 2,
        );

      default:
        // Idle / unknown: gentle smile
        path.moveTo(cx - mouthW / 2, cy + mouthOffsetY);
        path.quadraticBezierTo(
          cx,
          cy + mouthOffsetY + 7,
          cx + mouthW / 2,
          cy + mouthOffsetY,
        );
    }
    canvas.drawPath(path, mouthPaint);
  }

  // ── Name badge ────────────────────────────────────────────────────────────

  void _drawNameBadge(Canvas canvas, double cx, double cy, Color pColor) {
    final badgeTop = cy + _badgeTopOffset;

    // Measure the text first to size the badge
    final tp = TextPainter(
      text: TextSpan(
        text: agent.name,
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);

    final badgeW = (tp.width + 16).clamp(50.0, 120.0);

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, badgeTop + _badgeH / 2),
        width: badgeW,
        height: _badgeH,
      ),
      const Radius.circular(_badgeRadius),
    );

    final bgPaint = Paint()..color = pColor.withValues(alpha: 0.55);
    canvas.drawRRect(badgeRect, bgPaint);

    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, badgeTop + (_badgeH - tp.height) / 2),
    );
  }

  // ── Desk ──────────────────────────────────────────────────────────────────

  void _drawDesk(Canvas canvas, double cx, double cy) {
    final deskY = cy + _deskTopOffset;
    final paint = Paint()
      ..color = labelColor.withValues(alpha: 0.18)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square;

    // Horizontal surface
    canvas.drawLine(
      Offset(cx - _deskW / 2, deskY),
      Offset(cx + _deskW / 2, deskY),
      paint,
    );
    // Left leg
    canvas.drawLine(
      Offset(cx - _deskW / 2, deskY),
      Offset(cx - _deskW / 2, deskY + _deskEndH),
      paint,
    );
    // Right leg
    canvas.drawLine(
      Offset(cx + _deskW / 2, deskY),
      Offset(cx + _deskW / 2, deskY + _deskEndH),
      paint,
    );
  }

  // ── Status label ──────────────────────────────────────────────────────────

  void _drawStatusLabel(Canvas canvas, double cx, double cy, Color sColor) {
    final labelY = cy + _statusLabelOffset;

    String label;
    switch (agent.status) {
      case 'idle':
        label = 'idle';
      case 'working':
        label = 'working';
      case 'thinking':
        label = 'thinking...';
      case 'tool_calling':
        label = 'tool call';
      case 'error':
        label = 'error';
      default:
        label = agent.status;
    }

    // Small dot
    final dotPaint = Paint()..color = sColor.withValues(alpha: 0.90);
    canvas.drawCircle(Offset(cx - 22, labelY + 4), 3.0, dotPaint);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: sColor.withValues(alpha: 0.90),
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(cx - tp.width / 2 + 4, labelY));
  }

  // ── Activity speech bubble ────────────────────────────────────────────────

  void _drawActivityBubble(Canvas canvas, double cx, double cy, Color pColor) {
    // Position bubble above the face
    const bubbleBottomGap = _faceH / 2 + 12;

    final rawText = agent.activity;
    const maxChars = 30;
    final displayText = (!isBubbleExpanded && rawText.length > maxChars)
        ? '${rawText.substring(0, maxChars)}...'
        : rawText;

    final tp = TextPainter(
      text: TextSpan(
        text: displayText,
        style: TextStyle(
          color: labelColor.withValues(alpha: 0.92),
          fontSize: 9.5,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: isBubbleExpanded ? 4 : 1,
      ellipsis: isBubbleExpanded ? null : '...',
    )..layout(maxWidth: 130);

    const hPad = 10.0;
    const vPad = 7.0;
    final bubbleW = tp.width + hPad * 2;
    final bubbleH = tp.height + vPad * 2;
    const tailH = 5.0;

    final bubbleCY = cy - bubbleBottomGap - bubbleH / 2 - tailH;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, bubbleCY),
        width: bubbleW,
        height: bubbleH,
      ),
      const Radius.circular(8),
    );

    // Bubble background
    canvas.drawRRect(
      bgRect,
      Paint()..color = pColor.withValues(alpha: 0.18),
    );
    // Bubble border
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = pColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Small tail pointing downward
    final tailPath = Path()
      ..moveTo(cx - 4, bubbleCY + bubbleH / 2)
      ..lineTo(cx, bubbleCY + bubbleH / 2 + tailH)
      ..lineTo(cx + 4, bubbleCY + bubbleH / 2)
      ..close();
    canvas.drawPath(
      tailPath,
      Paint()..color = pColor.withValues(alpha: 0.18),
    );

    // Text
    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, bubbleCY - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant AgentPainter old) {
    return old.agent.status != agent.status ||
        old.agent.activity != agent.activity ||
        old.agent.name != agent.name ||
        old.animationValue != animationValue ||
        old.isBlinking != isBlinking ||
        old.isBubbleExpanded != isBubbleExpanded ||
        old.labelColor != labelColor;
  }
}
