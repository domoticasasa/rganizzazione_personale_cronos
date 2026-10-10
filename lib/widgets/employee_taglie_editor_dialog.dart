import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../utils/vestiario_catalog.dart';

Future<void> showEmployeeTaglieEditorDialog(
  BuildContext context, {
  required String personaleIdUuid,
  required String dialogTitle,
  required void Function(String msg, {bool error}) messenger,
}) async {
  if (!context.mounted) return;

  final tshirtCtrl = TextEditingController();
  final pantaloneCtrl = TextEditingController();
  final felpaCtrl = TextEditingController();
  final giaccaCtrl = TextEditingController();
  final giletCtrl = TextEditingController();
  final scarpeCtrl = TextEditingController();
  final guantiCtrl = TextEditingController();

  bool loading = true;
  bool saving = false;
  String tshirt = '';
  String pantalone = '';
  String felpa = '';
  String giacca = '';
  String gilet = '';
  String scarpe = '';
  String guanti = '';

  final topSizes = VestiarioCatalog.topClothingSizes;
  final trouserSizes = VestiarioCatalog.trouserSizes;
  final shoeSizes = VestiarioCatalog.shoeSizes;
  final gloveSizes = VestiarioCatalog.gloveSizes;

  Future<void> loadCurrent() async {
    final row = await SupabaseService.client
        .from('personale_taglie')
        .select('taglia_tshirt, taglia_pantalone, taglia_felpa, taglia_giacca, taglia_gilet, taglia_scarpe, taglia_guanti')
        .eq('personale_id', personaleIdUuid)
        .maybeSingle();
    tshirtCtrl.text = (row?['taglia_tshirt'] ?? '').toString();
    pantaloneCtrl.text = (row?['taglia_pantalone'] ?? '').toString();
    felpaCtrl.text = (row?['taglia_felpa'] ?? '').toString();
    giaccaCtrl.text = (row?['taglia_giacca'] ?? '').toString();
    giletCtrl.text = (row?['taglia_gilet'] ?? '').toString();
    scarpeCtrl.text = (row?['taglia_scarpe'] ?? '').toString();
    guantiCtrl.text = (row?['taglia_guanti'] ?? '').toString();
    tshirt = _safeOrFirst(tshirtCtrl.text.trim(), topSizes);
    pantalone = _safeOrFirst(pantaloneCtrl.text.trim(), trouserSizes);
    felpa = _safeOrFirst(felpaCtrl.text.trim(), topSizes);
    giacca = _safeOrFirst(giaccaCtrl.text.trim(), topSizes);
    gilet = _safeOrFirst(giletCtrl.text.trim(), topSizes);
    scarpe = _safeOrFirst(scarpeCtrl.text.trim(), shoeSizes);
    guanti = _safeOrFirst(guantiCtrl.text.trim(), gloveSizes);
    tshirtCtrl.text = tshirt;
    pantaloneCtrl.text = pantalone;
    felpaCtrl.text = felpa;
    giaccaCtrl.text = giacca;
    giletCtrl.text = gilet;
    scarpeCtrl.text = scarpe;
    guantiCtrl.text = guanti;
  }

  Future<void> save() async {
    await SupabaseService.client.from('personale_taglie').upsert(
      {
        'personale_id': personaleIdUuid,
        'taglia_tshirt': tshirtCtrl.text.trim(),
        'taglia_pantalone': pantaloneCtrl.text.trim(),
        'taglia_felpa': felpaCtrl.text.trim(),
        'taglia_giacca': giaccaCtrl.text.trim(),
        'taglia_gilet': giletCtrl.text.trim(),
        'taglia_scarpe': scarpeCtrl.text.trim(),
        'taglia_guanti': guantiCtrl.text.trim(),
      },
      onConflict: 'personale_id',
    );
  }

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSt) {
        if (loading) {
          loadCurrent()
              .then((_) {
                if (ctx.mounted) setSt(() => loading = false);
              })
              .catchError((e) {
                loading = false;
                messenger('Errore caricamento taglie: $e', error: true);
                if (ctx.mounted) setSt(() {});
              });
        }

        Widget field(
          String label,
          String value,
          List<String> options,
          void Function(String v) onChanged,
        ) {
          final safeValue = options.contains(value) ? value : options.first;
          return DropdownButtonFormField<String>(
            initialValue: safeValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: options
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: s,
                    child: Text(s),
                  ),
                )
                .toList(),
            onChanged: (v) => onChanged((v ?? '').trim()),
          );
        }

        return AlertDialog(
          title: Text(dialogTitle),
          content: SizedBox(
            width: 520,
            child: loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        field(
                          'Taglia t-shirt (EU)',
                          tshirt,
                          topSizes,
                          (v) => setSt(() {
                            tshirt = v;
                            tshirtCtrl.text = v;
                          }),
                        ),
                        const SizedBox(height: 10),
                        field(
                          'Taglia pantalone (EU)',
                          pantalone,
                          trouserSizes,
                          (v) => setSt(() {
                            pantalone = v;
                            pantaloneCtrl.text = v;
                          }),
                        ),
                        const SizedBox(height: 10),
                        field(
                          'Taglia felpa (EU)',
                          felpa,
                          topSizes,
                          (v) => setSt(() {
                            felpa = v;
                            felpaCtrl.text = v;
                          }),
                        ),
                        const SizedBox(height: 10),
                        field(
                          'Taglia giacca / giacca leggera (EU)',
                          giacca,
                          topSizes,
                          (v) => setSt(() {
                            giacca = v;
                            giaccaCtrl.text = v;
                          }),
                        ),
                        const SizedBox(height: 10),
                        field(
                          'Taglia gilet (EU)',
                          gilet,
                          topSizes,
                          (v) => setSt(() {
                            gilet = v;
                            giletCtrl.text = v;
                          }),
                        ),
                        const SizedBox(height: 10),
                        field(
                          'Taglia scarpe (EU)',
                          scarpe,
                          shoeSizes,
                          (v) => setSt(() {
                            scarpe = v;
                            scarpeCtrl.text = v;
                          }),
                        ),
                        const SizedBox(height: 10),
                        field(
                          'Taglia guanti (EU)',
                          guanti,
                          gloveSizes,
                          (v) => setSt(() {
                            guanti = v;
                            guantiCtrl.text = v;
                          }),
                        ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: (loading || saving)
                  ? null
                  : () async {
                      setSt(() => saving = true);
                      try {
                        await save();
                        messenger('Taglie salvate');
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        messenger('Errore salvataggio taglie: $e', error: true);
                      } finally {
                        if (ctx.mounted) setSt(() => saving = false);
                      }
                    },
              child: const Text('Salva'),
            ),
          ],
        );
      },
    ),
  );

  tshirtCtrl.dispose();
  pantaloneCtrl.dispose();
  felpaCtrl.dispose();
  giaccaCtrl.dispose();
  giletCtrl.dispose();
  scarpeCtrl.dispose();
  guantiCtrl.dispose();
}

String _safeOrFirst(String value, List<String> options) {
  if (options.contains(value)) return value;
  return options.first;
}

