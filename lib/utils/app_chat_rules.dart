import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'app_navigator.dart';
import 'responsive.dart';

/// Regolamento chat GESTOPRO: obbligatorio al primo utilizzo.
/// Accettazione salvata su Supabase (`users.chat_rules_accepted_at`).
abstract final class AppChatRules {
  AppChatRules._();

  /// Incrementare se cambia il testo (ri-mostra il popup).
  static const String noticeVersion = 'v3';

  static const String _prefsPrefix = 'gestopro_chat_rules_accepted_';

  static String get fullNotice =>
      'REGOLAMENTO CHAT GESTOPRO\n\n'
      'La chat è uno strumento aziendale a scopo esclusivamente lavorativo.\n\n'
      '1. Uso corretto\n'
      'Usa la chat solo per comunicazioni inerenti al lavoro '
      '(organizzazione, sicurezza, logistica, informazioni operative).\n\n'
      '2. Chat di gruppo\n'
      'I gruppi sono su invito: li crea un amministratore e sono visibili '
      'solo ai membri invitati, non a tutti gli utenti. '
      'Puoi inviare testo e, se necessario, foto o documenti di lavoro '
      '(anche screenshot incollati dagli appunti).\n\n'
      '3. Chat privata (individuale)\n'
      'I messaggi privati sono visibili solo a te e al destinatario. '
      'Di norma solo messaggi di testo. '
      'Gli amministratori possono inviare anche foto, documenti e '
      'screenshot (anche incollati con Ctrl+V / Incolla).\n\n'
      '4. Contenuti vietati\n'
      'È vietato inviare contenuti offensivi, discriminatori, diffamatori, '
      'illegali, o dati sensibili non necessari al lavoro.\n\n'
      '5. Riservatezza\n'
      'Non condividere password, dati personali di terzi o informazioni '
      'confidenziali oltre quanto richiesto dall\'attività lavorativa.\n\n'
      '6. Conservazione\n'
      'Messaggi e allegati vengono eliminati automaticamente dopo 7 giorni.\n\n'
      '7. Responsabilità\n'
      'Sei responsabile di quanto invii con il tuo account. '
      'L\'uso improprio può comportare provvedimenti secondo le policy aziendali.';

  static String _keyForUser(int userId) =>
      '$_prefsPrefix${noticeVersion}_$userId';

  static Future<bool> _localAccepted(int userId) async {
    if (userId <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyForUser(userId)) ?? false;
  }

  static Future<void> _setLocalAccepted(int userId, bool value) async {
    if (userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyForUser(userId), value);
  }

  static bool _isSchemaMissing(PostgrestException e) {
    return e.code == 'PGRST202' ||
        e.code == 'PGRST204' ||
        e.code == '42883' ||
        e.code == '42703';
  }

  static Future<int?> resolveCurrentUserId() async {
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId == null) return null;
    try {
      final row = await SupabaseService.client
          .from('users')
          .select('id')
          .or('auth_id.eq.$authId,id_uuid.eq.$authId')
          .maybeSingle();
      return (row?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasAccepted(int userId) async {
    if (userId <= 0) return false;

    try {
      final raw = await SupabaseService.client.rpc(
        'has_accepted_app_chat_rules',
        params: {'p_notice_version': noticeVersion},
      );
      final ok = raw == true;
      await _setLocalAccepted(userId, ok);
      return ok;
    } on PostgrestException catch (e) {
      if (!_isSchemaMissing(e)) {
        // continua con fallback
      } else {
        return false;
      }
    } catch (_) {}

    try {
      final row = await SupabaseService.client
          .from('users')
          .select('chat_rules_accepted_at, chat_rules_notice_version')
          .eq('id', userId)
          .maybeSingle();
      if (row != null) {
        final at = row['chat_rules_accepted_at'];
        final ver = (row['chat_rules_notice_version'] ?? '').toString().trim();
        final ok = at != null && ver == noticeVersion;
        await _setLocalAccepted(userId, ok);
        return ok;
      }
      await _setLocalAccepted(userId, false);
      return false;
    } on PostgrestException catch (e) {
      if (_isSchemaMissing(e)) return false;
    } catch (_) {}

    return _localAccepted(userId);
  }

  static Future<void> markAccepted(int userId) async {
    if (userId <= 0) return;

    var remoteOk = false;
    try {
      await SupabaseService.client.rpc(
        'accept_app_chat_rules',
        params: {'p_notice_version': noticeVersion},
      );
      remoteOk = true;
    } on PostgrestException catch (e) {
      if (!_isSchemaMissing(e)) {
        try {
          final authId = SupabaseService.client.auth.currentUser?.id;
          if (authId != null) {
            await SupabaseService.client.from('users').update({
              'chat_rules_accepted_at':
                  DateTime.now().toUtc().toIso8601String(),
              'chat_rules_notice_version': noticeVersion,
            }).eq('auth_id', authId);
            remoteOk = true;
          }
        } catch (_) {}
      }
    } catch (_) {}

    await _setLocalAccepted(userId, true);
    if (!remoteOk) {
      // ignore: avoid_print
      print(
        '⚠️ Regolamento chat accettato in locale ma non salvato su Supabase '
        '(eseguire migration app_chat_rules_acceptance).',
      );
    }
  }

  static Future<void> showNotice(
    BuildContext? context, {
    int? userId,
    bool requireAccept = false,
  }) async {
    final ctx = appNavigatorContext ?? context;
    if (ctx == null || !ctx.mounted) return;

    final mobile = useMobileUi(ctx);

    await showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: !requireAccept,
      builder: (dialogCtx) {
        var saving = false;

        return StatefulBuilder(
          builder: (dialogCtx, setLocal) {
            Future<void> onOk() async {
              if (saving) return;
              if (requireAccept && userId != null) {
                setLocal(() => saving = true);
                try {
                  await markAccepted(userId);
                } finally {
                  if (dialogCtx.mounted) setLocal(() => saving = false);
                }
              }
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
              }
            }

            final body = SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                mobile ? 20 : 8,
                mobile ? 8 : 0,
                mobile ? 20 : 8,
                8,
              ),
              child: Text(
                fullNotice,
                style: TextStyle(
                  height: 1.4,
                  fontSize: mobile ? 15 : 14,
                ),
              ),
            );

            final okButton = SizedBox(
              width: double.infinity,
              height: mobile ? 52 : 44,
              child: FilledButton(
                onPressed: saving ? null : onOk,
                style: FilledButton.styleFrom(
                  textStyle: TextStyle(
                    fontSize: mobile ? 17 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(requireAccept ? 'Sono d\'accordo' : 'OK'),
              ),
            );

            if (mobile) {
              return PopScope(
                canPop: !requireAccept,
                child: Dialog.fullscreen(
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 8, 0),
                          child: Row(
                            children: [
                              Icon(Icons.rule_folder_outlined, size: 26),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Regolamento chat',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (requireAccept)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: Text(
                              'Leggi il regolamento e premi «Sono d\'accordo» per usare la chat.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(dialogCtx)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        const Divider(height: 20),
                        Expanded(child: body),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: okButton,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return PopScope(
              canPop: !requireAccept,
              child: AlertDialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                title: const Row(
                  children: [
                    Icon(Icons.rule_folder_outlined, size: 22),
                    SizedBox(width: 8),
                    Expanded(child: Text('Regolamento chat')),
                  ],
                ),
                content: SizedBox(
                  width: 440,
                  height: (MediaQuery.sizeOf(dialogCtx).height * 0.55)
                      .clamp(280.0, 520.0),
                  child: body,
                ),
                actionsAlignment: MainAxisAlignment.center,
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                actions: [okButton],
              ),
            );
          },
        );
      },
    );
  }

  /// Mostra il regolamento obbligatorio se non ancora accettato su Supabase.
  /// Ritorna true se l'utente può usare la chat.
  static Future<bool> ensureAccepted(BuildContext? context) async {
    final userId = await resolveCurrentUserId();
    if (userId == null || userId <= 0) return false;
    if (await hasAccepted(userId)) return true;
    await showNotice(context, userId: userId, requireAccept: true);
    return hasAccepted(userId);
  }
}
