import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/carburante_giustificativi_stats_service.dart';
import '../services/deadline_nav_highlight.dart';
import '../pages/logistica_rcc_carburante_page.dart';
import '../pages/logistica_rcc_mdo_carburante_page.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../utils/date_formatters.dart';
import '../utils/gestopro_data_palette.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/modify_feedback.dart';

/// Verifica rifornimenti del mese con €/litro superiore alla soglia indicata.
class CarburanteSogliaLitroVerificaPanel extends StatefulWidget {
  const CarburanteSogliaLitroVerificaPanel({
    super.key,
    required this.loading,
    required this.selectedYear,
    required this.selectedMonth,
    required this.rccRows,
    required this.mdoRows,
  });

  final bool loading;
  final int? selectedYear;
  final int? selectedMonth;
  final List<Map<String, dynamic>> rccRows;
  final List<Map<String, dynamic>> mdoRows;

  @override
  State<CarburanteSogliaLitroVerificaPanel> createState() =>
      _CarburanteSogliaLitroVerificaPanelState();
}

class _CarburanteSogliaLitroVerificaPanelState
    extends State<CarburanteSogliaLitroVerificaPanel> {
  final _sogliaController = TextEditingController();
  double? _sogliaUsata;
  List<CarburanteRifornimentoSogliaVoce>? _risultati;
  bool _verificato = false;

  static final NumberFormat _numFmt = NumberFormat('#,##0.##', 'it_IT');
  static final NumberFormat _euroLitroFmt =
      NumberFormat('#,##0.000', 'it_IT');

  @override
  void didUpdateWidget(covariant CarburanteSogliaLitroVerificaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear != widget.selectedYear ||
        oldWidget.selectedMonth != widget.selectedMonth) {
      _risultati = null;
      _sogliaUsata = null;
      _verificato = false;
    }
  }

  @override
  void dispose() {
    _sogliaController.dispose();
    super.dispose();
  }

  double? _parseSoglia(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _verifica() {
    final year = widget.selectedYear;
    final month = widget.selectedMonth;
    if (year == null || month == null) {
      ModifyFeedback.hint(context, 'Seleziona un mese da verificare.');
      return;
    }

    final soglia = _parseSoglia(_sogliaController.text);
    if (soglia == null || soglia <= 0) {
      ModifyFeedback.hint(
        context,
        'Inserisci un costo al litro valido (es. 1,95).',
      );
      return;
    }

    final risultati = CarburanteGiustificativiStatsService.findRifornimentiOltreSoglia(
      rccRows: widget.rccRows,
      mdoRows: widget.mdoRows,
      year: year,
      month: month,
      sogliaEuroLitro: soglia,
    );

    setState(() {
      _sogliaUsata = soglia;
      _risultati = risultati;
      _verificato = true;
    });
  }

  void _apriGiustificativo(CarburanteRifornimentoSogliaVoce voce) {
    final id = voce.idUuid.trim();
    if (id.isEmpty) {
      ModifyFeedback.hint(
        context,
        'Impossibile aprire il giustificativo (identificativo mancante).',
      );
      return;
    }

    DeadlineNavHighlight.armUuid(id, flashCycles: 5);

    final year = widget.selectedYear;
    final month = widget.selectedMonth;
    final page = voce.fonte == CarburanteRifornimentoFonte.rcc
        ? LogisticaRccCarburantePage(
            initialFilterYear: year,
            initialFilterMonth: month,
          )
        : LogisticaRccMdoCarburantePage(
            initialFilterYear: year,
            initialFilterMonth: month,
          );

    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final palette = GestoproDataPalette.of(context);
    final gestopro = isGestoproFuturisticUi(context);
    final alertColor = gestopro
        ? CronosFuturisticTheme.neonRed
        : const Color(0xFFC62828);
    final okColor = gestopro
        ? CronosFuturisticTheme.neonGreen
        : const Color(0xFF2E7D32);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(palette.radius),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verifica costo al litro',
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTitle,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Confronta ogni rifornimento del mese con la soglia €/litro indicata.',
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTiny,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _sogliaController,
                  enabled: !widget.loading,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\s]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Soglia €/litro',
                    hintText: 'es. 1,95',
                    prefixText: '€ ',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    filled: palette.futuristic,
                    fillColor: palette.futuristic
                        ? CronosFuturisticTheme.deepSpace.withValues(alpha: 0.5)
                        : null,
                  ),
                  onSubmitted: (_) => _verifica(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: widget.loading ? null : _verifica,
                icon: const Icon(Icons.fact_check_outlined, size: 20),
                label: const Text('Verifica'),
              ),
            ],
          ),
          if (_verificato && _sogliaUsata != null && _risultati != null) ...[
            const SizedBox(height: 14),
            _buildEsito(
              palette: palette,
              alertColor: alertColor,
              okColor: okColor,
              soglia: _sogliaUsata!,
              risultati: _risultati!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEsito({
    required GestoproDataPalette palette,
    required Color alertColor,
    required Color okColor,
    required double soglia,
    required List<CarburanteRifornimentoSogliaVoce> risultati,
  }) {
    if (risultati.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: okColor.withValues(alpha: palette.futuristic ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(palette.radius),
          border: Border.all(color: okColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: okColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nessun rifornimento supera la soglia di '
                '€ ${_euroLitroFmt.format(soglia)}/L nel mese selezionato.',
                style: TextStyle(
                  fontSize: GestoproDataPalette.fsBody,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: alertColor.withValues(alpha: palette.futuristic ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(palette.radius),
            border: Border.all(color: alertColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: alertColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${risultati.length} riforniment${risultati.length == 1 ? 'o' : 'i'} '
                  'supera${risultati.length == 1 ? '' : 'no'} '
                  '€ ${_euroLitroFmt.format(soglia)}/L',
                  style: TextStyle(
                    fontSize: GestoproDataPalette.fsBody,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final voce in risultati) _voceCard(palette, alertColor, voce),
      ],
    );
  }

  Widget _voceCard(
    GestoproDataPalette palette,
    Color alertColor,
    CarburanteRifornimentoSogliaVoce voce,
  ) {
    final tipo = (voce.tipoCarburante ?? '').trim();
    final nome = (voce.nomeCognome ?? '').trim();
    final dettaglio = (voce.dettaglio ?? '').trim();
    final cantiere = (voce.cantiere ?? '').trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _apriGiustificativo(voce),
        borderRadius: BorderRadius.circular(palette.radius),
        child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: alertColor.withValues(alpha: palette.futuristic ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(palette.radius),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _fonteChip(palette, voce),
              const Spacer(),
              Text(
                '€ ${_euroLitroFmt.format(voce.euroLitro)}/L',
                style: TextStyle(
                  fontSize: GestoproDataPalette.fsNum,
                  fontWeight: FontWeight.w800,
                  color: alertColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _rigaInfo(
            palette,
            'Data',
            formatDateDdMmYyyy(voce.dataRifornimento),
          ),
          if (tipo.isNotEmpty)
            _rigaInfo(palette, 'Carburante', tipo),
          _rigaInfo(
            palette,
            'Litri / Euro',
            '${_numFmt.format(voce.litri)} L · € ${_numFmt.format(voce.euro)}',
          ),
          if (nome.isNotEmpty) _rigaInfo(palette, 'Nome', nome),
          if (dettaglio.isNotEmpty)
            _rigaInfo(
              palette,
              voce.fonte == CarburanteRifornimentoFonte.rcc
                  ? 'Carta'
                  : 'Mezzo MDO',
              dettaglio,
            ),
          if (cantiere.isNotEmpty)
            _rigaInfo(palette, 'Cantiere', cantiere),
          const SizedBox(height: 4),
          Text(
            'Tocca per aprire il giustificativo',
            style: TextStyle(
              fontSize: GestoproDataPalette.fsTiny,
              color: palette.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _fonteChip(
    GestoproDataPalette palette,
    CarburanteRifornimentoSogliaVoce voce,
  ) {
    final isRcc = voce.fonte == CarburanteRifornimentoFonte.rcc;
    final color = isRcc
        ? (palette.futuristic
            ? CronosFuturisticTheme.electricBright
            : const Color(0xFF1565C0))
        : (palette.futuristic
            ? CronosFuturisticTheme.neonPurple
            : const Color(0xFF6A1B9A));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        voce.fonteLabel,
        style: TextStyle(
          fontSize: GestoproDataPalette.fsTiny,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _rigaInfo(GestoproDataPalette palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: GestoproDataPalette.fsTiny,
                color: palette.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: GestoproDataPalette.fsLabel,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
