import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Controllo €/litro su benzina e gasolio in fase di inserimento giustificativo.
abstract final class CarburanteEuroLitroGuard {
  CarburanteEuroLitroGuard._();

  static const maxEuroLitroBenzinaGasolio = 4.0;

  static final NumberFormat _euroLitroFmt = NumberFormat('#,##0.000', 'it_IT');
  static final NumberFormat _numFmt = NumberFormat('#,##0.##', 'it_IT');

  static bool isBenzinaOrGasolio(String? tipoCarburante) {
    final t = (tipoCarburante ?? '').trim().toLowerCase();
    if (t.isEmpty) return false;
    if (t.contains('benz')) return true;
    if (t.contains('gasol') || t.contains('diesel') || t.contains('hvo')) {
      return true;
    }
    return false;
  }

  static double? euroLitro({
    required double? litri,
    required double? euro,
  }) {
    if (litri == null || euro == null || litri <= 0) return null;
    return euro / litri;
  }

  /// Messaggio di blocco se supera la soglia; altrimenti `null` (salvataggio ok).
  static String? blockMessage({
    required String tipoCarburante,
    required double? litri,
    required double? euro,
  }) {
    if (!isBenzinaOrGasolio(tipoCarburante)) return null;
    final el = euroLitro(litri: litri, euro: euro);
    if (el == null || el <= maxEuroLitroBenzinaGasolio) return null;

    final tipo = tipoCarburante.trim();
    return 'Il costo calcolato per $tipo è '
        '€ ${_euroLitroFmt.format(el)}/L '
        '(litri: ${_numFmt.format(litri)}, euro: ${_numFmt.format(euro)}), '
        'superiore a € ${_euroLitroFmt.format(maxEuroLitroBenzinaGasolio)}/L.\n\n'
        'È molto probabile un errore nei litri o nell\'importo: '
        'verificare i dati prima di salvare.';
  }

  /// Mostra il dialog di verifica e restituisce `true` se il salvataggio va bloccato.
  static Future<bool> confirmBlockIfNeeded({
    required BuildContext context,
    required String tipoCarburante,
    required double? litri,
    required double? euro,
  }) async {
    final message = blockMessage(
      tipoCarburante: tipoCarburante,
      litri: litri,
      euro: euro,
    );
    if (message == null) return false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verifica costo al litro'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Correggo i dati'),
          ),
        ],
      ),
    );
    return true;
  }
}
