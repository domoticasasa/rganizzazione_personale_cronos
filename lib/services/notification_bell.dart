// lib/widgets/notification_bell.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/notifications_page.dart';
import '../services/data_cleanup_service.dart';
import '../Mobile/employee_mobile_pages.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/is_app_chat_notification.dart';
import '../utils/mobile_navigation.dart';

class NotificationBell extends StatefulWidget {
  final int userId;
  final Color iconColor;
  final double size;
  final EdgeInsets badgePadding;

  const NotificationBell({
    super.key,
    required this.userId,
    this.iconColor = Colors.white,
    this.size = 28,
    this.badgePadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _syncBlink(bool shouldBlink) {
    if (shouldBlink) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      if (_blinkController.isAnimating) {
        _blinkController.stop();
      }
      _blinkController.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final supa = Supabase.instance.client;

    final stream = supa
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', widget.userId);

    final retentionCutoff = DateTime.parse(
      DataCleanupService.notificationRetentionCutoffIso(),
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (_, snapshot) {
        final all = snapshot.data ?? const [];

        bool withinRetention(Map<String, dynamic> n) {
          final raw = n['created_at'];
          if (raw == null) return true;
          try {
            return !DateTime.parse(raw.toString()).toUtc().isBefore(retentionCutoff);
          } catch (_) {
            return true;
          }
        }

        // Escludi le notifiche tecniche di inserimento (creator/type/date = N/D, message contiene "inserita.")
        List<Map<String, dynamic>> filterTech(List<Map<String, dynamic>> list) {
          return list.where((n) {
            final rawMeta = n['meta'];
            Map<String, dynamic> m = {};
            if (rawMeta is Map) {
              m = Map<String, dynamic>.from(rawMeta);
            } else if (rawMeta is String) {
              // meta può essere JSON serializzato
              try {
                final decoded = jsonDecode(rawMeta);
                if (decoded is Map) {
                  m = Map<String, dynamic>.from(decoded);
                }
              } catch (_) {}
            }

            final creator = (m['creator'] ?? m['by_name'] ?? '').toString();
            final type = (m['type'] ?? m['tipo'] ?? '').toString();
            final date = (m['date'] ?? m['data'] ?? '').toString();
            final msg = (n['message'] ?? '').toString().toLowerCase();
            final isPlainInsertTech =
                creator == 'N/D' && type == 'N/D' && date == 'N/D' && msg.contains('inserita.');
            if (isPlainInsertTech) return false;
            if (isAppChatNotificationRow(n)) return false;
            return true;
          }).toList();
        }

        final filtered = filterTech(all.where(withinRetention).toList());
        final unread = filtered.where((n) => !(n['is_read'] ?? false)).toList();
        final count = unread.length;
        final hasUnread = count > 0;
        _syncBlink(hasUnread);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _blinkController,
              builder: (_, _) {
                final t = _blinkController.value;
                final bellColor = hasUnread
                    ? Color.lerp(widget.iconColor, Colors.red, 1 - t) ?? Colors.red
                    : widget.iconColor;
                final bgColor = hasUnread
                    ? Color.lerp(Colors.white24, Colors.red.withValues(alpha: 0.35), 1 - t) ??
                        Colors.white24
                    : Colors.white24;
                return IconButton(
                  icon: Icon(Icons.notifications, color: bellColor, size: widget.size),
                  style: IconButton.styleFrom(
                    backgroundColor: bgColor,
                  ),
                  onPressed: () async {
                    final page = useMobileUi(context)
                        ? NotificationsMobilePage(userId: widget.userId)
                        : NotificationsPage(userId: widget.userId);
                    await FuturisticNavigation.pushPage(
                      context,
                      page: page,
                      title: 'Notifiche',
                    );

                    // Facoltativo: marca tutte come lette al ritorno
                    // (scommenta se vuoi questa UX)
                    // await supa
                    //     .from('notifications')
                    //     .update({'is_read': true})
                    //     .eq('user_id', widget.userId)
                    //     .eq('is_read', false);

                    // Forza un refresh del widget dopo il ritorno
                    if (context.mounted) {
                      (context as Element).markNeedsBuild();
                    }
                  },
                  tooltip: 'Notifiche',
                );
              },
            ),

            // Badge conteggio non lette
            if (count > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: widget.badgePadding,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.shade700,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}