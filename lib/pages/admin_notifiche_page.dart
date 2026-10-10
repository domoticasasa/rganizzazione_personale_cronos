import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/confirm_sound_service.dart';
import '../services/notification_sender.dart';
import '../services/web_push_service.dart';
import '../utils/users_directory.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminNotifichePage extends StatefulWidget {
  final int adminId;
  const AdminNotifichePage({super.key, required this.adminId});

  @override
  State<AdminNotifichePage> createState() => _AdminNotifichePageState();
}

class _AdminNotifichePageState extends State<AdminNotifichePage> {
  final titoloController =
      TextEditingController(text: 'Test notifiche Cronos');
  final messaggioController = TextEditingController(
    text: 'Messaggio di test: verifica popup, audio e notifica mobile.',
  );

  bool loading = false;
  bool sendCopyToMe = true;
  bool _diagLoading = false;
  bool _forceRegistering = false;

  int? fromUserId;
  int? toUserId;
  List<Map<String, dynamic>> users = const [];
  Map<String, bool> _platformReady = const {};
  String _diagHint = 'Seleziona un destinatario per verificare i canali.';
  int _webSubCount = 0;
  int _myWebSubCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    titoloController.dispose();
    messaggioController.dispose();
    super.dispose();
  }

  String _userLabel(Map<String, dynamic> u) {
    final name = (u['full_name'] ?? '').toString().trim();
    final username = (u['username'] ?? '').toString().trim();
    final role = (u['role'] ?? '').toString().trim();
    final id = (u['id'] ?? '').toString().trim();
    final visible = name.isNotEmpty ? name : username;
    return '$visible ($role) #$id';
  }

  int _compareUsersByLabel(Map<String, dynamic> a, Map<String, dynamic> b) {
    final al = _userLabel(a).toLowerCase().trim();
    final bl = _userLabel(b).toLowerCase().trim();
    return al.compareTo(bl);
  }

  Future<void> _loadUsers() async {
    setState(() => loading = true);
    try {
      List res;
      try {
        res = await Supabase.instance.client
            .from('users')
            .select('id, full_name, username, role, active, hidden_from_directory')
            .eq('active', true)
            .order('full_name') as List;
      } catch (_) {
        res = await Supabase.instance.client
            .from('users')
            .select('id, full_name, username, role, active')
            .eq('active', true)
            .order('full_name') as List;
      }
      final all = res
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['id'] is int)
          .toList();
      // Nascosti fuori dalle liste, ma il gestore corrente resta selezionabile.
      final list = all
          .where(
            (u) =>
                UsersDirectory.isVisibleInDirectory(u) ||
                (u['id'] as int) == widget.adminId,
          )
          .toList()
        ..sort(_compareUsersByLabel);

      int? defaultFrom = fromUserId;
      if (defaultFrom == null) {
        final me = list.firstWhere(
          (u) => (u['id'] as int) == widget.adminId,
          orElse: () => <String, dynamic>{},
        );
        if (me.isNotEmpty) {
          defaultFrom = me['id'] as int;
        } else {
          defaultFrom = widget.adminId;
        }
      }

      setState(() {
        users = list;
        fromUserId = defaultFrom;
        // Sempre l'utente di QUESTO browser: altrimenti il test va su un altro
        // account (es. DT #2) e questo Chrome (#192) non riceve nulla.
        toUserId = widget.adminId;
        if (toUserId != null &&
            !users.any((u) => (u['id'] as int) == toUserId)) {
          toUserId = widget.adminId;
        }
      });
      await _loadDiagnostics();
      await _refreshMyWebPushStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore caricamento utenti: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadDiagnostics() async {
    final uid = toUserId;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _platformReady = const {};
        _webSubCount = 0;
        _diagHint = 'Seleziona un destinatario per verificare i canali.';
      });
      return;
    }
    setState(() => _diagLoading = true);
    try {
      final deviceRes = await Supabase.instance.client
          .from('device_tokens')
          .select('platform')
          .eq('user_id', uid);
      final webRes = await Supabase.instance.client
          .from('web_push_subscriptions')
          .select('user_agent, active')
          .eq('user_id', uid)
          .eq('active', true);

      final platforms = <String>{};
      for (final r in (deviceRes as List)) {
        final p = (r['platform'] ?? '').toString().toLowerCase().trim();
        if (p.isNotEmpty) platforms.add(p);
      }

      bool hasWindowsWeb = false;
      bool hasAndroidWeb = false;
      bool hasIphoneWeb = false;
      final webList = webRes as List;
      for (final r in webList) {
        final ua = (r['user_agent'] ?? '').toString().toLowerCase();
        if (ua.contains('android')) {
          hasAndroidWeb = true;
        } else if (ua.contains('iphone') ||
            ua.contains('ipad') ||
            ua.contains('ipod')) {
          hasIphoneWeb = true;
        } else {
          // Chrome/Edge desktop, UA vuoto, o generico → canale web desktop.
          hasWindowsWeb = true;
        }
      }

      final status = <String, bool>{
        'windows_exe': platforms.contains('windows'),
        'windows_web': hasWindowsWeb,
        'android_apk': platforms.contains('android'),
        'android_web': hasAndroidWeb,
        'iphone_web': hasIphoneWeb,
      };

      final missing = status.entries.where((e) => !e.value).map((e) => e.key).toList();
      final isSelf = uid == widget.adminId;
      String hint;
      if (missing.isEmpty) {
        hint =
            'Tutti i canali risultano registrati '
            '($_webSubCount dispositivi web push attivi).';
      } else if (!isSelf && !hasWindowsWeb && !hasAndroidWeb && !hasIphoneWeb) {
        hint =
            'Nessuna Web Push per questo destinatario. '
            'Ogni dispositivo (PC / telefono / tablet) deve registrarsi '
            'con l’utente loggato su QUEL device. '
            'Tu sei #${widget.adminId} su questo browser: seleziona te stesso '
            'oppure fai login come il destinatario su ciascun device.';
      } else {
        hint =
            'Canali mancanti: ${missing.join(', ')}. '
            'Web push attive: $_webSubCount (una per browser/dispositivo).';
      }

      if (!mounted) return;
      setState(() {
        _platformReady = status;
        _webSubCount = webList.length;
        _diagHint = hint;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _platformReady = const {};
        _webSubCount = 0;
        _diagHint = 'Diagnostica non disponibile: $e';
      });
    } finally {
      if (mounted) setState(() => _diagLoading = false);
    }
  }

  Future<int> _countMyWebPushSubs() async {
    try {
      final res = await Supabase.instance.client
          .from('web_push_subscriptions')
          .select('id')
          .eq('user_id', widget.adminId)
          .eq('active', true);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _refreshMyWebPushStatus() async {
    final count = await _countMyWebPushSubs();
    if (!mounted) return;
    setState(() => _myWebSubCount = count);
  }

  Future<void> _forceRegisterWebPushForCurrentUser() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Forzatura disponibile solo su Web.'),
        ),
      );
      return;
    }
    setState(() => _forceRegistering = true);
    try {
      // Assicura permesso + subscription sul browser corrente.
      if (!WebPushService.isBrowserNotificationGranted) {
        final granted = await WebPushService.requestBrowserPermissionFromUser();
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permesso notifiche non concesso. Abilitalo dal browser e riprova.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      final ok = await WebPushService.ensureRegisteredForCurrentUser(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final count = await _countMyWebPushSubs();
      if (!mounted) return;
      setState(() {
        toUserId = widget.adminId;
        _myWebSubCount = count;
      });
      await _loadDiagnostics();
      if (!mounted) return;
      ConfirmSoundService.play();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok && count > 0
                ? 'Web Push OK per utente #${widget.adminId} '
                    '($count dispositivi). Destinatario = te: invia il test. '
                    'Su altri device (stesso account) apri Cronos e registra lì.'
                : 'Registrazione non riuscita (permission=${WebPushService.notificationPermission}, '
                    'sub=$count). Usa «Abilita notifiche browser» se compare in basso a destra.',
          ),
          backgroundColor: ok && count > 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore forzatura Web Push: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _forceRegistering = false);
    }
  }

  Widget _platformChip(String key, String label) {
    final ready = _platformReady[key] == true;
    return Chip(
      avatar: Icon(
        ready ? Icons.check_circle : Icons.error_outline,
        color: ready ? Colors.green : Colors.red,
        size: 18,
      ),
      label: Text(label),
      side: BorderSide(
        color: ready ? Colors.green.shade300 : Colors.red.shade300,
      ),
      backgroundColor: ready ? Colors.green.withValues(alpha: 0.10) : Colors.red.withValues(alpha: 0.08),
    );
  }

  Future<void> _sendTestNotification() async {
    final titolo = titoloController.text.trim();
    final messaggio = messaggioController.text.trim();
    if (titolo.isEmpty || messaggio.isEmpty || toUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compila titolo, messaggio e destinatario.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Web Push è legato al browser loggato: evita test “ciechi” su un altro user_id.
    if (kIsWeb && toUserId != widget.adminId) {
      final switchToMe = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Destinatario diverso da questo Chrome'),
          content: Text(
            'Sei loggato come #${widget.adminId}, ma stai inviando a #$toUserId.\n\n'
            'Le push di QUESTO Chrome arrivano solo a #${widget.adminId}.\n'
            'Vuoi cambiare il destinatario a te (#${widget.adminId}) e inviare?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('No, invia a #$toUserId'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Sì, invia a me (#${widget.adminId})'),
            ),
          ],
        ),
      );
      if (switchToMe == true) {
        setState(() => toUserId = widget.adminId);
        await _loadDiagnostics();
      } else if (switchToMe == null) {
        return;
      }
    }

    setState(() => loading = true);
    try {
      final from = users
          .where((u) => (u['id'] as int?) == fromUserId)
          .cast<Map<String, dynamic>>()
          .toList();
      final to = users
          .where((u) => (u['id'] as int?) == toUserId)
          .cast<Map<String, dynamic>>()
          .toList();
      final fromLabel = from.isNotEmpty ? _userLabel(from.first) : 'N/D';
      final toLabel = to.isNotEmpty ? _userLabel(to.first) : 'N/D';

      final recipientIds = <int>{toUserId!};
      if (sendCopyToMe || kIsWeb) {
        recipientIds.add(widget.adminId);
      }

      final testBookingId =
          DateTime.now().millisecondsSinceEpoch.remainder(2000000000);
      final finalMessage = '[TEST NOTIFICA]\nDa: $fromLabel\nA: $toLabel\n\n$messaggio';

      final result = await NotificationSender.sendToUserIds(
        userIds: recipientIds.toList(),
        bookingId: testBookingId,
        action: 'test_manual',
        title: titolo,
        message: finalMessage,
      );

      if (!mounted) return;
      ConfirmSoundService.play();
      final webPushed = (result?['web_pushed'] as num?)?.toInt() ?? 0;
      final webSubs = (result?['web_subs_found'] as num?)?.toInt() ?? 0;
      final vapidOk = result?['vapid_configured'] == true;
      final vapidPrefix = (result?['vapid_public_prefix'] ?? '').toString();
      // Deve coincidere con window.CRONOS_VAPID_PUBLIC_KEY in web/index.html
      final vapidMismatch =
          vapidOk && vapidPrefix.isNotEmpty && vapidPrefix != 'BByADhgyYhVA';
      final errors = (result?['web_push_errors'] as List?) ?? const [];
      final errHint = errors.isEmpty
          ? ''
          : ' Err: ${errors.first}';
      final mismatchHint = vapidMismatch
          ? ' VAPID mismatch (server≠web)!'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Test → #$toUserId. Web push: $webPushed/$webSubs'
            '${vapidOk ? '' : ' (VAPID OFF)'}'
            '$mismatchHint'
            '.$errHint',
          ),
          backgroundColor: webPushed > 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 10),
        ),
      );
      await _loadDiagnostics();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invio test fallito: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: "Admin — Test Notifiche"),
        actions: [
          IconButton(
            tooltip: 'Ricarica utenti',
            onPressed: loading ? null : _loadUsers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: PageWithTopLogo(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
            const Text(
              'Invio notifica di test (popup desktop, audio, mobile).',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: fromUserId,
              decoration: const InputDecoration(
                labelText: "Da utente (solo etichetta test)",
              ),
              items: users
                  .map(
                    (u) => DropdownMenuItem<int>(
                      value: u['id'] as int,
                      child: Text(_userLabel(u)),
                    ),
                  )
                  .toList(),
              onChanged: loading ? null : (value) => setState(() => fromUserId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: toUserId,
              decoration: InputDecoration(
                labelText: "A utente (destinatario reale della push)",
                helperText:
                    "Questo Chrome è loggato come #${widget.adminId}. "
                    "Il test verso un altro account (es. DT) non fa suonare QUESTO PC.",
              ),
              items: users
                  .map(
                    (u) => DropdownMenuItem<int>(
                      value: u['id'] as int,
                      child: Text(_userLabel(u)),
                    ),
                  )
                  .toList(),
              onChanged: loading
                  ? null
                  : (value) async {
                      setState(() => toUserId = value);
                      await _loadDiagnostics();
                    },
            ),
            if (toUserId != null && toUserId != widget.adminId) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'Attenzione: stai inviando a #$toUserId, ma questo Chrome '
                    'registra Web Push sull’utente loggato #${widget.adminId}. '
                    'Per testare tab chiusa seleziona te stesso come destinatario.',
                    style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.health_and_safety_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Text(
                          'Diagnostica piattaforme',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Aggiorna diagnostica',
                          onPressed: _diagLoading ? null : _loadDiagnostics,
                          icon: _diagLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _platformChip('windows_exe', 'Windows EXE'),
                        _platformChip('windows_web', 'Windows Web Chrome'),
                        _platformChip('android_apk', 'Android APK'),
                        _platformChip('android_web', 'Android Web Chrome'),
                        _platformChip('iphone_web', 'iPhone Web Safari/PWA'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _diagHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_webSubCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Subscription Web Push attive sul destinatario: $_webSubCount',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (_myWebSubCount <= 0) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _forceRegistering
                              ? null
                              : _forceRegisterWebPushForCurrentUser,
                          icon: _forceRegistering
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.notification_add_outlined),
                          label: Text(
                            'Registra Web Push su questo Chrome (utente #${widget.adminId})',
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Web Push già registrata su questo Chrome (#${widget.adminId}).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade800,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titoloController,
              decoration: const InputDecoration(labelText: "Titolo"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: messaggioController,
              decoration: const InputDecoration(labelText: "Messaggio"),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: sendCopyToMe,
              onChanged: loading ? null : (v) => setState(() => sendCopyToMe = v),
              title: const Text('Invia copia a me (admin)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: loading ? null : _sendTestNotification,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text("Invia test notifica"),
            ),
            const SizedBox(height: 10),
            const Text(
              'Suggerimento: apri l\'app anche sul telefono del destinatario e verifica banner/suono.',
            ),
            ],
          ),
        ),
      ),
    );
  }
}
