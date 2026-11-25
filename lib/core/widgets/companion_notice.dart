import 'dart:async';

import 'package:flutter/material.dart';
import 'package:join_app/core/theme/app_colors.dart';
import 'package:join_app/core/widgets/companion_view.dart';

void showCompanionNotice(
  BuildContext context, {
  required String message,
  required String companionAsset,
  IconData icon = Icons.check_rounded,
  Color color = const Color(0xFF16B981),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CompanionNotice(
      message: message,
      companionAsset: companionAsset,
      icon: icon,
      color: color,
      onDismiss: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _CompanionNotice extends StatefulWidget {
  final String message;
  final String companionAsset;
  final IconData icon;
  final Color color;
  final VoidCallback onDismiss;

  const _CompanionNotice({
    required this.message,
    required this.companionAsset,
    required this.icon,
    required this.color,
    required this.onDismiss,
  });

  @override
  State<_CompanionNotice> createState() => _CompanionNoticeState();
}

class _CompanionNoticeState extends State<_CompanionNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260),
    )..forward();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 14,
      right: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final eased = Curves.easeOutBack.transform(_controller.value);
          return Opacity(
            opacity: _controller.value,
            child: Transform.translate(
              offset: Offset(0, -36 * (1 - eased)),
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: widget.color.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF061539).withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: CompanionView(
                      asset: widget.companionAsset,
                      portrait: true,
                      motion: CompanionMotion.celebrate,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: widget.color,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(widget.icon,
                                color: Colors.white, size: 15),
                          ),
                          const SizedBox(width: 7),
                          const Text(
                            '¡Todo listo!',
                            style: TextStyle(
                              color: AppColors.navyBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _dismiss,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
