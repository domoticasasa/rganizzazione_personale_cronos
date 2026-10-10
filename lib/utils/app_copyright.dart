import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../legal/privacy_termini_page.dart';

import '../services/app_branding_service.dart';
import '../services/supabase_service.dart';
import 'app_navigator.dart';
import 'responsive.dart';

/// Notice e regole prodotto: popup obbligatorio finché l'utente non conferma.
/// L'accettazione è salvata su Supabase (`users.copyright_accepted_at`) così
/// vale su tutti i dispositivi e resta come prova.
abstract final class AppCopyright {
  AppCopyright._();

  static String get productName => AppBrandingService.instance.productName;

  /// Incrementare quando cambia il testo delle regole (ri-mostra il popup).
  /// `v2` = prima accettazione obbligatoria salvata su Supabase (prova cross-device).
  static const String noticeVersion = 'v2';

  static const String _prefsPrefix = 'gestopro_copyright_accepted_';

  /// Riga corta per footer / login (senza glifo ©: su alcuni mobile non si vede).
  static String get shortNotice => AppBrandingService.instance.copyrightShort;

  /// Corpo regole (il simbolo © è un'icona Material nel dialog).
  static String get fullNotice => AppBrandingService.instance.copyrightFull;

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

  /// Fonte di verità: solo Supabase.
  /// L'OK fatto solo sul dispositivo (vecchia cache) non evita il popup:
  /// serve una nuova conferma registrata sul server.
  static Future<bool> hasAccepted(int userId) async {
    if (userId <= 0) return false;

    try {
      final raw = await SupabaseService.client.rpc(
        'has_accepted_gestopro_copyright',
        params: {'p_notice_version': noticeVersion},
      );
      final ok = raw == true;
      if (ok) {
        await _setLocalAccepted(userId, true);
      } else {
        // Non accettato su server: non usare il vecchio OK locale.
        await _setLocalAccepted(userId, false);
      }
      return ok;
    } on PostgrestException catch (e) {
      if (_isSchemaMissing(e)) {
        // Schema non disponibile: senza server non consideriamo accettato.
        return false;
      }
    } catch (_) {}

    try {
      final row = await SupabaseService.client
          .from('users')
          .select('copyright_accepted_at, copyright_notice_version')
          .eq('id', userId)
          .maybeSingle();
      if (row != null) {
        final at = row['copyright_accepted_at'];
        final ver = (row['copyright_notice_version'] ?? '').toString().trim();
        final ok = at != null && ver == noticeVersion;
        await _setLocalAccepted(userId, ok);
        return ok;
      }
      // Profilo letto ma senza accettazione server.
      await _setLocalAccepted(userId, false);
      return false;
    } on PostgrestException catch (e) {
      if (_isSchemaMissing(e)) return false;
    } catch (_) {}

    // Offline / errore rete: usa solo cache della *versione corrente*
    // (non quella del vecchio OK locale pre-Supabase).
    return _localAccepted(userId);
  }

  static Future<void> markAccepted(int userId) async {
    if (userId <= 0) return;

    var remoteOk = false;
    try {
      await SupabaseService.client.rpc(
        'accept_gestopro_copyright',
        params: {'p_notice_version': noticeVersion},
      );
      remoteOk = true;
    } on PostgrestException catch (e) {
      if (!_isSchemaMissing(e)) {
        // Prova update diretto sul proprio record.
        try {
          final authId = SupabaseService.client.auth.currentUser?.id;
          if (authId != null) {
            await SupabaseService.client.from('users').update({
              'copyright_accepted_at': DateTime.now().toUtc().toIso8601String(),
              'copyright_notice_version': noticeVersion,
            }).eq('auth_id', authId);
            remoteOk = true;
          }
        } catch (_) {}
      }
    } catch (_) {
      try {
        final authId = SupabaseService.client.auth.currentUser?.id;
        if (authId != null) {
          await SupabaseService.client.from('users').update({
            'copyright_accepted_at': DateTime.now().toUtc().toIso8601String(),
            'copyright_notice_version': noticeVersion,
          }).eq('auth_id', authId);
          remoteOk = true;
        }
      } catch (_) {}
    }

    // Cache locale sempre (anche se remote fallisce: non bloccare l'uso).
    await _setLocalAccepted(userId, true);
    if (!remoteOk) {
      // ignore: avoid_print
      print(
        '⚠️ Copyright accettato in locale ma non salvato su Supabase '
        '(eseguire migration users_copyright_acceptance).',
      );
    }
  }

  /// Dialogo regole. Su cellulare: quasi a schermo intero + pulsante grande.
  /// Con [requireAccept] non si chiude senza conferma e salva per [userId].
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.copyright,
                        size: mobile ? 22 : 18,
                        color: Theme.of(dialogCtx).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        productName,
                        style: TextStyle(
                          fontSize: mobile ? 18 : 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: mobile ? 12 : 10),
                  Text(
                    fullNotice,
                    style: TextStyle(
                      height: 1.4,
                      fontSize: mobile ? 15 : 14,
                    ),
                  ),
                ],
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
                    : Text(requireAccept ? 'Ho capito' : 'OK'),
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                          child: Row(
                            children: [
                              const Icon(Icons.gavel_outlined, size: 26),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Regole e copyright',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (!requireAccept)
                                IconButton(
                                  tooltip: 'Chiudi',
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                        ),
                        if (requireAccept)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: Text(
                              'Leggi le regole e premi «Ho capito» per continuare.',
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
                    Icon(Icons.gavel_outlined, size: 22),
                    SizedBox(width: 8),
                    Expanded(child: Text('Regole e copyright')),
                  ],
                ),
                content: SizedBox(
                  width: 420,
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

  /// Se l'utente non ha ancora accettato su Supabase, mostra il popup obbligatorio.
  static Future<void> ensureAccepted(
    BuildContext? context, {
    required int userId,
  }) async {
    if (userId <= 0) return;
    if (await hasAccepted(userId)) return;
    await showNotice(context, userId: userId, requireAccept: true);
  }
}

/// Footer legale: pulsante © + link «Privacy e termini» (audit legale A1).
/// Usato in login e sidebar, quindi la privacy è sempre raggiungibile.
class AppCopyrightFooter extends StatelessWidget {
  const AppCopyrightFooter({
    super.key,
    this.lightOnDark = false,
    this.compact = false,
  });

  final bool lightOnDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = lightOnDark
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF1E3A5F);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppCopyrightButton(lightOnDark: lightOnDark, compact: compact),
        TextButton(
          onPressed: () => PrivacyTerminiPage.open(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: const Size(0, 24),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: fg,
          ),
          child: Text(
            compact ? 'Privacy' : 'Privacy e termini',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppCopyrightButton extends StatelessWidget {
  const _AppCopyrightButton({
    this.lightOnDark = false,
    this.compact = false,
  });

  final bool lightOnDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = lightOnDark
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF1E3A5F);
    final border = lightOnDark
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0xFF1565C0).withValues(alpha: 0.35);
    final bg = lightOnDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF1565C0).withValues(alpha: 0.06);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => AppCopyright.showNotice(context),
        borderRadius: BorderRadius.circular(8),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.copyright,
                size: compact ? 13 : 14,
                color: fg,
              ),
              SizedBox(width: compact ? 4 : 5),
              Flexible(
                child: Text(
                  AppCopyright.shortNotice,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    color: fg,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
