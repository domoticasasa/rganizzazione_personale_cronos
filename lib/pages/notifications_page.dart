// NOTIFICATIONS PAGE — VERSIONE SENZA AUDIO (SUONA SOLO IL SERVICE)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/data_cleanup_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/futuristic/futuristic_inline_toolbar.dart';
import '../widgets/futuristic/futuristic_shell_scope.dart';
import '../utils/date_formatters.dart';
import '../utils/is_app_chat_notification.dart';
import '../widgets/classic_app_bar_chrome.dart';

class NotificationsPage extends StatefulWidget {
  final int userId;

  const NotificationsPage({super.key, required this.userId});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final supa = Supabase.instance.client;

  late RealtimeChannel _chan;
  bool _loading = true;
  bool _busyAll = false;

  final List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    try {
      supa.removeChannel(_chan);
    } catch (_) {}
    super.dispose();
  }

  // ------------------------------------------
  // INITIAL LOAD
  // ------------------------------------------
  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final res = await supa
          .from('notifications')
          .select('*')
          .eq('user_id', widget.userId)
          .gte('created_at', DataCleanupService.notificationRetentionCutoffIso())
          .order('created_at', ascending: false);

      final rows = (res as List)
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => !isAppChatNotificationRow(e))
          .toList();

      if (!mounted) return;

      setState(() {
        _items
          ..clear()
          ..addAll(rows);
      });
    } catch (e) {
      _toast("Errore: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------
  // REALTIME (NO AUDIO QUI!)
  // ------------------------------------------
  void _subscribeRealtime() {
    final channelName =
        'realtime:public:notifications:user_id=eq.${widget.userId}';

    _chan = supa.channel(channelName);

    _chan.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        final newRow = Map<String, dynamic>.from(payload.newRecord);
        final oldRow = Map<String, dynamic>.from(payload.oldRecord);

        setState(() {
          switch (payload.eventType) {
            case PostgresChangeEvent.insert:
              if (!isAppChatNotificationRow(newRow)) {
                _items.insert(0, newRow);
              }
              break;
            case PostgresChangeEvent.update:
              if (isAppChatNotificationRow(newRow)) {
                _items.removeWhere((n) => n['id'] == newRow['id']);
                break;
              }
              final idx = _items.indexWhere((n) => n['id'] == newRow['id']);
              if (idx >= 0) {
                _items[idx] = newRow;
              } else {
                _items.insert(0, newRow);
              }
              break;
            case PostgresChangeEvent.delete:
              _items.removeWhere((n) => n['id'] == oldRow['id']);
              break;
            default:
              break;
          }
        });
      },
    );

    _chan.subscribe();
  }

  // ------------------------------------------
  // ACTIONS
  // ------------------------------------------
  Future<void> _confirmOne(int id) async {
    try {
      setState(() => _items.removeWhere((i) => i['id'] == id));
      await supa.from('notifications').delete().match({'id': id});
    } catch (e) {
      _toast("Errore: $e");
    }
  }

  Future<void> _confirmAll() async {
    setState(() => _busyAll = true);
    try {
      await supa.from('notifications').delete().eq('user_id', widget.userId);
      _items.clear();
      setState(() {});
    } catch (e) {
      _toast("Errore: $e");
    } finally {
      _busyAll = false;
      setState(() {});
    }
  }

  // ------------------------------------------
  // HELPERS
  // ------------------------------------------

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtDate(dynamic v) => formatDateTimeItFromSupabase(v);

  IconData tipoIcon(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'pernottamento':
        return Icons.bed_outlined;
      case 'aereo':
        return Icons.flight_takeoff;
      case 'treno':
        return Icons.train;
      default:
        return Icons.notifications;
    }
  }

  Color tipoColor(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'pernottamento':
        return Colors.blue.shade600;
      case 'aereo':
        return Colors.purple.shade600;
      case 'treno':
        return Colors.green.shade600;
      default:
        return Colors.orange.shade600;
    }
  }

  // ------------------------------------------
  // UI
  // ------------------------------------------

  @override
  Widget build(BuildContext context) {
    final data = _items;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : data.isEmpty
            ? const Center(child: Text('Nessuna notifica'))
            : RefreshIndicator(
                onRefresh: _loadInitial,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: data.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: _buildItem,
                ),
              );

    final chromeless = FuturisticShellScope.hideChromeOf(context);
    if (chromeless) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FuturisticInlineToolbar(
            title: 'Notifiche',
            actions: [
              IconButton(
                tooltip: 'Elimina tutte',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: data.isEmpty || _busyAll ? null : _confirmAll,
              ),
            ],
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Notifiche'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: data.isEmpty || _busyAll ? null : _confirmAll,
          )
        ],
      )),
      body: PageWithTopLogo(child: body),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final n = _items[index];
    final id = n['id'];
    final title = n['title'] ?? 'Notifica';
    final message = n['message'] ?? '';
    final isRead = n['is_read'] ?? false;

    Map<String, dynamic> meta = {};
    try {
      if (n['meta'] is String) {
        meta = jsonDecode(n['meta']);
      } else if (n['meta'] is Map) {
        meta = Map<String, dynamic>.from(n['meta']);
      }
    } catch (_) {}

    // Se è una notifica tecnica "inserita" senza dettagli (date/type/creator = N/D),
    // la manteniamo per il motore di notifiche ma NON la mostriamo nella lista utente.
    final creatorMeta = (meta['creator'] ?? meta['by_name'] ?? '').toString();
    final typeMeta = (meta['type'] ?? meta['tipo'] ?? '').toString();
    final dateMeta = (meta['date'] ?? meta['data'] ?? '').toString();
    final msgLower = message.toString().toLowerCase();
    final isPlainInsertTech =
        creatorMeta == 'N/D' &&
        typeMeta == 'N/D' &&
        dateMeta == 'N/D' &&
        msgLower.contains('inserita.');
    if (isPlainInsertTech) {
      return const SizedBox.shrink();
    }

    // Mostra sempre la data di creazione notifica (non la data prenotazione).
    final createdAt = _fmtDate(n['created_at']);

    final tipo = meta['tipo'] ?? 'Generico';
    final byName = meta['by_name'] ?? '';

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      onDismissed: (_) => _confirmOne(id),
      child: Card(
        elevation: isRead ? 0 : 3,
        shadowColor: Colors.black26,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: tipoColor(tipo).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Icon(tipoIcon(tipo),
                        color: tipoColor(tipo), size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    createdAt,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                message,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
              ),

              if (byName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: tipoColor(tipo),
                      child: Text(
                        byName[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      byName,
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                )
              ],

              const SizedBox(height: 12),

              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _confirmOne(id),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text("Cancella"),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}