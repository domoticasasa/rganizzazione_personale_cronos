import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/employee_programmazione_service.dart';
import '../services/visite_mediche_service.dart';
import 'mobile_navigation.dart';

class DipendenteChooserOption {
  const DipendenteChooserOption({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.page,
    this.onSelect,
    this.accent,
    this.alertBlink = false,
  }) : assert(page != null || onSelect != null);

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function()? page;
  /// Se valorizzato, viene usato al posto del push pagina (es. dialog).
  final Future<void> Function()? onSelect;
  final Color? accent;
  /// Lampeggio rosso (es. programmazione da aprire).
  final bool alertBlink;
}

/// Popup Area dipendente: un tap sulla riga apre subito la pagina.
Future<void> showDipendentePageChooser(
  BuildContext context, {
  required String title,
  required List<DipendenteChooserOption> options,
  IconData headerIcon = Icons.apps_outlined,
  Color? headerAccent,
}) async {
  if (options.isEmpty) return;
  final choice = useMobileUi(context)
      ? await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.45),
          builder: (ctx) => _ChooserSheet(
            title: title,
            headerIcon: headerIcon,
            headerAccent: headerAccent,
            options: options,
          ),
        )
      : await showGeneralDialog<String>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Chiudi',
          barrierColor: Colors.black.withValues(alpha: 0.42),
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (ctx, _, _) => _ChooserDialog(
            title: title,
            headerIcon: headerIcon,
            headerAccent: headerAccent,
            options: options,
          ),
          transitionBuilder: (ctx, anim, _, child) {
            final curved = CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                child: child,
              ),
            );
          },
        );
  if (choice == null || !context.mounted) return;
  for (final o in options) {
    if (o.id != choice) continue;
    if (o.onSelect != null) {
      await o.onSelect!();
      return;
    }
    final page = o.page;
    if (page == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page()),
    );
    return;
  }
}

Future<void> showDipendenteRifornimentoChooser(
  BuildContext context, {
  required Widget Function() rccPage,
  required Widget Function() mdoPage,
  required Widget Function() multicardPage,
  Widget Function()? mancantiPage,
  bool alertMancanti = false,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Rifornimento',
    headerIcon: Icons.local_gas_station_outlined,
    headerAccent: const Color(0xFF2F6FED),
    options: [
      if (mancantiPage != null)
        DipendenteChooserOption(
          id: 'mancanti',
          icon: Icons.receipt_long_outlined,
          title: 'Da giustificare',
          subtitle: 'Rifornimenti in fattura QT ancora senza scontrino RCC',
          page: mancantiPage,
          accent: const Color(0xFFC62828),
          alertBlink: alertMancanti,
        ),
      DipendenteChooserOption(
        id: 'rcc',
        icon: Icons.local_shipping_outlined,
        title: 'Registro Carburante Mezzi Stradali',
        subtitle: 'Mod. RCC — registro rifornimenti',
        page: rccPage,
        accent: const Color(0xFF2F6FED),
      ),
      DipendenteChooserOption(
        id: 'mdo',
        icon: Icons.train_outlined,
        title: 'Rifornimento MDO',
        subtitle: 'Giustificativo carburante · mezzo d’opera ferroviario',
        page: mdoPage,
        accent: const Color(0xFF1565C0),
      ),
      DipendenteChooserOption(
        id: 'multicard',
        icon: Icons.credit_card_outlined,
        title: 'Multicard',
        subtitle: 'Carte carburante associate',
        page: multicardPage,
        accent: const Color(0xFF00897B),
      ),
    ],
  );
}

Future<void> showDipendenteMezziChooser(
  BuildContext context, {
  required Widget Function() mdoPage,
  required Widget Function() stradaliMioMezzoPage,
  required Widget Function() officinePage,
  Widget Function()? mdoPerCommessaPage,
  Widget Function()? trasferimentiPage,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Mezzi',
    headerIcon: Icons.commute_outlined,
    headerAccent: const Color(0xFF1565C0),
    options: [
      DipendenteChooserOption(
        id: 'mdo',
        icon: Icons.train_outlined,
        title: 'MDO Ferroviari',
        subtitle: 'Check dotazioni DPI, posizione GPS e commessa',
        page: mdoPage,
        accent: const Color(0xFF1565C0),
      ),
      if (mdoPerCommessaPage != null)
        DipendenteChooserOption(
          id: 'mdo_per_commessa',
          icon: Icons.alt_route_outlined,
          title: 'MDO per commessa',
          subtitle: 'Mezzi raggruppati per cantiere / commessa',
          page: mdoPerCommessaPage,
          accent: const Color(0xFF00897B),
        ),
      if (trasferimentiPage != null)
        DipendenteChooserOption(
          id: 'trasferimenti',
          icon: Icons.swap_horiz,
          title: 'Trasferimenti in corso',
          subtitle: 'Spostamenti MDO tra commesse',
          page: trasferimentiPage,
          accent: const Color(0xFFE65100),
        ),
      DipendenteChooserOption(
        id: 'stradali',
        icon: Icons.local_shipping_outlined,
        title: 'Mezzi Stradali',
        subtitle: 'Il tuo mezzo, PDF assegnazione e gomme',
        page: stradaliMioMezzoPage,
        accent: const Color(0xFF2F6FED),
      ),
      DipendenteChooserOption(
        id: 'officine',
        icon: Icons.garage_outlined,
        title: 'Officine convenzionate',
        subtitle: 'Lista officine in sola lettura',
        page: officinePage,
        accent: const Color(0xFF00897B),
      ),
    ],
  );
}

Future<void> showDipendenteViaggiMezziChooser(
  BuildContext context, {
  required Widget Function() scanPage,
  required Widget Function() riepilogoPage,
  required Widget Function() assegnatarioPage,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Viaggi mezzi',
    headerIcon: Icons.route_outlined,
    headerAccent: const Color(0xFF1565C0),
    options: [
      DipendenteChooserOption(
        id: 'scan',
        icon: Icons.qr_code_scanner,
        title: 'Scansiona viaggio mezzo',
        subtitle: 'Apertura e chiusura viaggio con km e GPS',
        page: scanPage,
        accent: const Color(0xFF1565C0),
      ),
      DipendenteChooserOption(
        id: 'riepilogo',
        icon: Icons.route_outlined,
        title: 'I miei viaggi mezzo',
        subtitle: 'Storico mensile dei mezzi guidati',
        page: riepilogoPage,
        accent: const Color(0xFF2F6FED),
      ),
      DipendenteChooserOption(
        id: 'assegnatario',
        icon: Icons.local_shipping_outlined,
        title: 'Viaggi sui miei mezzi',
        subtitle: 'Chi ha guidato i mezzi a te assegnati',
        page: assegnatarioPage,
        accent: const Color(0xFF00897B),
      ),
    ],
  );
}

Future<void> showDipendenteSicurezzaChooser(
  BuildContext context, {
  required Widget Function() dpiPage,
  required Future<void> Function() openMisureVestiario,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Sicurezza',
    headerIcon: Icons.health_and_safety_outlined,
    headerAccent: const Color(0xFFC62828),
    options: [
      DipendenteChooserOption(
        id: 'dpi',
        icon: Icons.shield_outlined,
        title: 'Dotazioni DPI',
        subtitle: 'Dispositivi di protezione individuale assegnati',
        page: dpiPage,
        accent: const Color(0xFFC62828),
      ),
      DipendenteChooserOption(
        id: 'misure',
        icon: Icons.straighten,
        title: 'Misure vestiario',
        subtitle: 'Taglie T‑shirt, pantaloni, scarpe…',
        onSelect: openMisureVestiario,
        accent: const Color(0xFF6A4C9C),
      ),
    ],
  );
}

/// Popup Visita medica: normale oppure RFI (con PDF struttura).
Future<void> showDipendenteVisiteMedicheChooser(
  BuildContext context, {
  required Widget Function() standardPage,
  required Widget Function() rfiPage,
  String? employeeFullName,
  bool? alertStandard,
  bool? alertRfi,
}) async {
  var alertStd = alertStandard;
  var alertRfiFlag = alertRfi;
  final name = (employeeFullName ?? '').trim();
  if ((alertStd == null || alertRfiFlag == null) && name.isNotEmpty) {
    try {
      alertStd ??= await VisiteMedicheService.hasUpcomingStandardForCurrentUser(
        employeeFullName: name,
      );
      alertRfiFlag ??= await VisiteMedicheService.hasUpcomingRfiForCurrentUser(
        employeeFullName: name,
      );
    } catch (_) {
      alertStd ??= false;
      alertRfiFlag ??= false;
    }
  }
  alertStd ??= false;
  alertRfiFlag ??= false;

  return showDipendentePageChooser(
    context,
    title: 'Visita medica',
    headerIcon: Icons.medical_services_outlined,
    headerAccent: const Color(0xFFC62828),
    options: [
      DipendenteChooserOption(
        id: 'standard',
        icon: Icons.medical_services_outlined,
        title: 'Visita medica',
        subtitle: 'Data, ora e luogo della visita programmata',
        page: standardPage,
        accent: const Color(0xFF00897B),
        alertBlink: alertStd,
      ),
      DipendenteChooserOption(
        id: 'rfi',
        icon: Icons.medical_information_outlined,
        title: 'Visita medica RFI',
        subtitle: 'Visite RFI con PDF da scaricare',
        page: rfiPage,
        accent: const Color(0xFF1565C0),
        alertBlink: alertRfiFlag,
      ),
    ],
  );
}

Future<void> showDipendenteBuoniPastoChooser(
  BuildContext context, {
  required Widget Function() scanPage,
  required Widget Function() riepilogoPage,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Buoni Pasto',
    headerIcon: Icons.restaurant_outlined,
    headerAccent: const Color(0xFF1565C0),
    options: [
      DipendenteChooserOption(
        id: 'scan',
        icon: Icons.qr_code_scanner_outlined,
        title: 'Scansiona buono pasto',
        subtitle: 'Fotocamera o QR struttura (anche fuori dall\'app)',
        page: scanPage,
        accent: const Color(0xFF1565C0),
      ),
      DipendenteChooserOption(
        id: 'riepilogo',
        icon: Icons.restaurant_outlined,
        title: 'I miei buoni pasto',
        subtitle: 'Storico registrazioni del mese',
        page: riepilogoPage,
        accent: const Color(0xFF2F6FED),
      ),
    ],
  );
}

Future<void> showDipendenteFormazioneChooser(
  BuildContext context, {
  required Widget Function() scadenzePage,
  required Widget Function() rfiScadenzePage,
  required Widget Function() programmazionePage,
  required Widget Function() programmazioneRfiPage,
  required Widget Function() attestatiPage,
  String? employeeFullName,
  bool? alertProgrammazione,
  bool? alertProgrammazioneRfi,
}) async {
  var alert81 = alertProgrammazione;
  var alertRfi = alertProgrammazioneRfi;
  final name = (employeeFullName ?? '').trim();
  if ((alert81 == null || alertRfi == null) && name.isNotEmpty) {
    try {
      alert81 ??= await EmployeeProgrammazioneService.hasScheduledForCurrentUser(
        employeeFullName: name,
      );
      alertRfi ??=
          await EmployeeProgrammazioneService.hasRfiScheduledForCurrentUser(
        employeeFullName: name,
      );
    } catch (_) {
      alert81 ??= false;
      alertRfi ??= false;
    }
  }
  alert81 ??= false;
  alertRfi ??= false;

  return showDipendentePageChooser(
    context,
    title: 'Formazione',
    headerIcon: Icons.school_outlined,
    headerAccent: const Color(0xFF6A4C9C),
    options: [
      DipendenteChooserOption(
        id: 'scadenze',
        icon: Icons.school_outlined,
        title: 'Formazione e Scadenze',
        subtitle: 'Corsi fatti, ultima data e scadenze',
        page: scadenzePage,
        accent: const Color(0xFF6A4C9C),
      ),
      DipendenteChooserOption(
        id: 'rfi_scadenze',
        icon: Icons.train_outlined,
        title: 'Formazione RFI',
        subtitle: 'Corsi RFI e relative scadenze',
        page: rfiScadenzePage,
        accent: const Color(0xFF1565C0),
      ),
      DipendenteChooserOption(
        id: 'programmazione',
        icon: Icons.event_note_outlined,
        title: 'Programmazione Formazioni',
        subtitle: 'Corsi D.Lgs. 81/08 programmati a tuo nome',
        page: programmazionePage,
        accent: const Color(0xFF00897B),
        alertBlink: alert81,
      ),
      DipendenteChooserOption(
        id: 'programmazione_rfi',
        icon: Icons.event_available_outlined,
        title: 'Programmazioni corsi RFI',
        subtitle: 'Corsi RFI programmati a tuo nome (dal/al)',
        page: programmazioneRfiPage,
        accent: const Color(0xFF3949AB),
        alertBlink: alertRfi,
      ),
      DipendenteChooserOption(
        id: 'attestati',
        icon: Icons.workspace_premium_outlined,
        title: 'I miei Attestati',
        subtitle: 'Scarica attestati RFI e D.Lgs. 81/08',
        page: attestatiPage,
        accent: const Color(0xFFC62828),
      ),
    ],
  );
}

Future<void> showDipendenteTreniChooser(
  BuildContext context, {
  required Widget Function() nuovaPage,
  required Future<void> Function() elenco,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Le mie richieste treno',
    headerIcon: Icons.train_outlined,
    headerAccent: const Color(0xFF1565C0),
    options: [
      DipendenteChooserOption(
        id: 'nuova',
        icon: Icons.add_circle_outline,
        title: 'Nuova richiesta',
        subtitle: 'Compila e invia al DT',
        page: nuovaPage,
        accent: const Color(0xFF2E7D32),
      ),
      DipendenteChooserOption(
        id: 'elenco',
        icon: Icons.list_alt_outlined,
        title: 'Elenco richieste',
        subtitle: 'Stato delle tue prenotazioni treno',
        onSelect: elenco,
        accent: const Color(0xFF1565C0),
      ),
    ],
  );
}

Future<void> showDipendenteAereiChooser(
  BuildContext context, {
  required Widget Function() nuovaPage,
  required Future<void> Function() elenco,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Le mie richieste aerei',
    headerIcon: Icons.flight_takeoff_outlined,
    headerAccent: const Color(0xFF0277BD),
    options: [
      DipendenteChooserOption(
        id: 'nuova',
        icon: Icons.add_circle_outline,
        title: 'Nuova richiesta',
        subtitle: 'Compila e invia al DT',
        page: nuovaPage,
        accent: const Color(0xFF2E7D32),
      ),
      DipendenteChooserOption(
        id: 'elenco',
        icon: Icons.list_alt_outlined,
        title: 'Elenco richieste',
        subtitle: 'Stato delle tue prenotazioni aereo',
        onSelect: elenco,
        accent: const Color(0xFF0277BD),
      ),
    ],
  );
}

class _ChooserDialog extends StatelessWidget {
  const _ChooserDialog({
    required this.title,
    required this.headerIcon,
    required this.headerAccent,
    required this.options,
  });

  final String title;
  final IconData headerIcon;
  final Color? headerAccent;
  final List<DipendenteChooserOption> options;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Material(
            color: Colors.transparent,
            child: _ChooserPanel(
              title: title,
              headerIcon: headerIcon,
              headerAccent: headerAccent,
              options: options,
              asSheet: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChooserSheet extends StatelessWidget {
  const _ChooserSheet({
    required this.title,
    required this.headerIcon,
    required this.headerAccent,
    required this.options,
  });

  final String title;
  final IconData headerIcon;
  final Color? headerAccent;
  final List<DipendenteChooserOption> options;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: _ChooserPanel(
          title: title,
          headerIcon: headerIcon,
          headerAccent: headerAccent,
          options: options,
          asSheet: true,
        ),
      ),
    );
  }
}

class _ChooserPanel extends StatelessWidget {
  const _ChooserPanel({
    required this.title,
    required this.headerIcon,
    required this.headerAccent,
    required this.options,
    required this.asSheet,
  });

  final String title;
  final IconData headerIcon;
  final Color? headerAccent;
  final List<DipendenteChooserOption> options;
  final bool asSheet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = headerAccent ?? scheme.primary;
    final radius = asSheet
        ? const BorderRadius.vertical(top: Radius.circular(28))
        : BorderRadius.circular(26);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  accent.withValues(alpha: 0.10),
                  scheme.surface,
                ),
                scheme.surface,
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, asSheet ? 10 : 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (asSheet)
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent,
                            Color.lerp(accent, Colors.black, 0.18)!,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(headerIcon, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Tocca una voce per aprire',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Chiudi',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ChooserCard(
                      option: options[i],
                      fallbackAccent: accent,
                      onTap: () => Navigator.pop(context, options[i].id),
                    ),
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

class _ChooserCard extends StatefulWidget {
  const _ChooserCard({
    required this.option,
    required this.fallbackAccent,
    required this.onTap,
  });

  final DipendenteChooserOption option;
  final Color fallbackAccent;
  final VoidCallback onTap;

  @override
  State<_ChooserCard> createState() => _ChooserCardState();
}

class _ChooserCardState extends State<_ChooserCard> {
  bool _pressed = false;
  bool _blinkOn = true;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    if (widget.option.alertBlink) {
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        if (!mounted) return;
        setState(() => _blinkOn = !_blinkOn);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ChooserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.option.alertBlink == widget.option.alertBlink) return;
    _blinkTimer?.cancel();
    _blinkTimer = null;
    if (widget.option.alertBlink) {
      _blinkOn = true;
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        if (!mounted) return;
        setState(() => _blinkOn = !_blinkOn);
      });
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final baseAccent = widget.option.accent ?? widget.fallbackAccent;
    final alert = widget.option.alertBlink;
    final blinkRed = alert && _blinkOn;
    final accent = blinkRed ? Colors.red : baseAccent;
    final titleColor = blinkRed ? Colors.red : null;
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 90),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: blinkRed ? 0.22 : 0.14),
                    scheme.surface,
                  ),
                  scheme.surface,
                ],
              ),
              border: Border.all(
                color: accent.withValues(alpha: blinkRed ? 0.75 : 0.22),
                width: blinkRed ? 1.6 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: blinkRed ? 0.28 : 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: blinkRed ? 0.22 : 0.14),
                    ),
                    child: Icon(widget.option.icon, color: accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.option.title,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.option.subtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: blinkRed
                                ? Colors.red.shade700
                                : scheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: blinkRed ? 0.22 : 0.12),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
