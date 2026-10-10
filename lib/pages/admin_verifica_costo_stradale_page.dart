import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/viaggio_stradale_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Verifica costo viaggio mezzo stradale (vs treno/aereo).
class AdminVerificaCostoStradalePage extends StatefulWidget {
  const AdminVerificaCostoStradalePage({
    super.key,
    this.forceMobileLayout = false,
  });

  final bool forceMobileLayout;

  @override
  State<AdminVerificaCostoStradalePage> createState() =>
      _AdminVerificaCostoStradalePageState();
}

class _AdminVerificaCostoStradalePageState
    extends State<AdminVerificaCostoStradalePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;

  ViaggioStradaleSettings _settings = const ViaggioStradaleSettings(
    costoOrarioEur: 25,
    prezzoCarburanteEurLitro: 1.8,
    tollEurPerKmEstimate: 0.08,
  );
  List<ViaggioStradaleLuogo> _luoghi = const [];
  List<ViaggioStradaleMezzoOpzione> _mezzi = const [];
  List<ViaggioStradaleTratta> _tratte = const [];

  ViaggioStradaleLuogo? _origine;
  ViaggioStradaleLuogo? _destinazione;
  ViaggioStradaleMezzoOpzione? _mezzo;
  final _l100Override = TextEditingController();
  final _dipendenteNote = TextEditingController();

  bool _calcoloBusy = false;
  ViaggioStradaleCosto? _costo;
  ViaggioStradaleTratta? _trattaUsata;
  String? _calcoloMsg;

  final _costoOrarioCtrl = TextEditingController();
  final _prezzoCarbCtrl = TextEditingController();
  final _tollPerKmCtrl = TextEditingController();
  bool _settingsSaving = false;

  String? _updatingTrattaId;

  final _eur = NumberFormat.currency(locale: 'it_IT', symbol: '€');
  final _kmFmt = NumberFormat('#,##0.0', 'it_IT');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _l100Override.dispose();
    _dipendenteNote.dispose();
    _costoOrarioCtrl.dispose();
    _prezzoCarbCtrl.dispose();
    _tollPerKmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await ViaggioStradaleService.loadSettings();
      final luoghi = await ViaggioStradaleService.loadLuoghi();
      final mezzi = await ViaggioStradaleService.loadMezziConConsumo();
      final tratte = await ViaggioStradaleService.listTratte();
      if (!mounted) return;
      _costoOrarioCtrl.text = settings.costoOrarioEur.toStringAsFixed(2);
      _prezzoCarbCtrl.text =
          settings.prezzoCarburanteEurLitro.toStringAsFixed(3);
      _tollPerKmCtrl.text =
          settings.tollEurPerKmEstimate.toStringAsFixed(4);
      setState(() {
        _settings = settings;
        _luoghi = luoghi;
        _mezzi = mezzi;
        _tratte = tratte;
        _loading = false;
        if (_mezzo == null && mezzi.isNotEmpty) {
          _mezzo = mezzi.firstWhere(
            (m) => m.consumoDaRcc,
            orElse: () => mezzi.first,
          );
          if (_mezzo!.consumoDaRcc && _mezzo!.litriPer100Km > 0) {
            _l100Override.text = _mezzo!.litriPer100Km.toStringAsFixed(1);
          }
        } else if (_mezzo != null) {
          final id = _mezzo!.id;
          final match = mezzi.cast<ViaggioStradaleMezzoOpzione?>().firstWhere(
                (m) => m?.id == id,
                orElse: () => null,
              );
          _mezzo = match;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  double get _litriPer100 {
    final o = double.tryParse(_l100Override.text.replaceAll(',', '.'));
    if (o != null && o > 0) return o;
    final m = _mezzo;
    if (m != null && m.consumoDaRcc && m.litriPer100Km > 0) {
      return m.litriPer100Km;
    }
    return 0;
  }

  String? _mezzoIdInList() {
    final id = _mezzo?.id;
    if (id == null) return null;
    for (final m in _mezzi) {
      if (m.id == id) return id;
    }
    return null;
  }

  Future<void> _calcola() async {
    final o = _origine;
    final d = _destinazione;
    if (o == null || d == null) {
      setState(() => _calcoloMsg = 'Seleziona partenza e arrivo.');
      return;
    }
    if (o.key == d.key) {
      setState(() => _calcoloMsg = 'Partenza e arrivo devono essere diversi.');
      return;
    }
    if (_litriPer100 <= 0) {
      setState(() => _calcoloMsg =
          'Inserisci il consumo L/100km (non trovato nei dati RCC).');
      return;
    }
    setState(() {
      _calcoloBusy = true;
      _calcoloMsg = null;
      _costo = null;
    });
    try {
      var tratta = await ViaggioStradaleService.findTratta(
        origineTipo: o.tipo,
        origineNome: o.nome,
        destinazioneTipo: d.tipo,
        destinazioneNome: d.nome,
      );
      tratta ??= await ViaggioStradaleService.resolveOrCreateTratta(
        origine: o,
        destinazione: d,
        settings: _settings,
      );
      final costo = ViaggioStradaleService.calcolaCosto(
        km: tratta.kmStradali,
        litriPer100Km: _litriPer100,
        settings: _settings,
        pedaggioEur: tratta.pedaggioEur,
        durataMinuti: tratta.durataMinuti,
      );
      final tratte = await ViaggioStradaleService.listTratte();
      if (!mounted) return;
      setState(() {
        _trattaUsata = tratta;
        _costo = costo;
        _tratte = tratte;
        _calcoloBusy = false;
        _calcoloMsg =
            'Tratta ${tratta!.kmStradali.toStringAsFixed(1)} km · '
            'pedaggio ${_eur.format(tratta.pedaggioEur)} '
            '(${tratta.pedaggioFonte})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _calcoloBusy = false;
        _calcoloMsg = '$e';
      });
    }
  }

  Future<void> _saveSettings() async {
    final co = double.tryParse(_costoOrarioCtrl.text.replaceAll(',', '.'));
    final pc = double.tryParse(_prezzoCarbCtrl.text.replaceAll(',', '.'));
    final tk = double.tryParse(_tollPerKmCtrl.text.replaceAll(',', '.'));
    if (co == null || pc == null || tk == null || co < 0 || pc < 0 || tk < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valori non validi')),
      );
      return;
    }
    setState(() => _settingsSaving = true);
    try {
      final s = ViaggioStradaleSettings(
        costoOrarioEur: co,
        prezzoCarburanteEurLitro: pc,
        tollEurPerKmEstimate: tk,
      );
      await ViaggioStradaleService.saveSettings(s);
      if (!mounted) return;
      setState(() {
        _settings = s;
        _settingsSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impostazioni salvate')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingsSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _aggiornaTratta(
    ViaggioStradaleTratta t, {
    bool forceToll = false,
  }) async {
    setState(() => _updatingTrattaId = t.idUuid);
    try {
      final updated = await ViaggioStradaleService.aggiornaPrezzoTratta(
        t,
        settings: _settings,
        forceTollEstimate: forceToll,
      );
      final tratte = await ViaggioStradaleService.listTratte();
      if (!mounted) return;
      setState(() {
        _tratte = tratte;
        if (_trattaUsata?.idUuid == t.idUuid) _trattaUsata = updated;
        _updatingTrattaId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aggiornato: ${updated.kmStradali.toStringAsFixed(1)} km, '
            'pedaggio ${_eur.format(updated.pedaggioEur)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingTrattaId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editTrattaDialog([ViaggioStradaleTratta? existing]) async {
    final isNew = existing == null;
    var origTipo = existing?.origineTipo ?? 'stazione';
    var destTipo = existing?.destinazioneTipo ?? 'stazione';
    final origNome = TextEditingController(text: existing?.origineNome ?? '');
    final destNome =
        TextEditingController(text: existing?.destinazioneNome ?? '');
    final kmCtrl = TextEditingController(
      text: existing != null ? existing.kmStradali.toStringAsFixed(1) : '',
    );
    final pedCtrl = TextEditingController(
      text: existing != null ? existing.pedaggioEur.toStringAsFixed(2) : '',
    );
    final durCtrl = TextEditingController(
      text: existing?.durataMinuti?.toString() ?? '',
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(isNew ? 'Nuova tratta' : 'Modifica tratta'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: origTipo,
                        decoration:
                            const InputDecoration(labelText: 'Tipo partenza'),
                        items: const [
                          DropdownMenuItem(
                              value: 'stazione', child: Text('Stazione')),
                          DropdownMenuItem(
                              value: 'aeroporto', child: Text('Aeroporto')),
                          DropdownMenuItem(
                              value: 'altro', child: Text('Altro')),
                        ],
                        onChanged: (v) =>
                            setLocal(() => origTipo = v ?? 'stazione'),
                      ),
                      TextField(
                        controller: origNome,
                        decoration:
                            const InputDecoration(labelText: 'Nome partenza'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: destTipo,
                        decoration:
                            const InputDecoration(labelText: 'Tipo arrivo'),
                        items: const [
                          DropdownMenuItem(
                              value: 'stazione', child: Text('Stazione')),
                          DropdownMenuItem(
                              value: 'aeroporto', child: Text('Aeroporto')),
                          DropdownMenuItem(
                              value: 'altro', child: Text('Altro')),
                        ],
                        onChanged: (v) =>
                            setLocal(() => destTipo = v ?? 'stazione'),
                      ),
                      TextField(
                        controller: destNome,
                        decoration:
                            const InputDecoration(labelText: 'Nome arrivo'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: kmCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Km stradali'),
                      ),
                      TextField(
                        controller: pedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Pedaggio autostrada (€)',
                        ),
                      ),
                      TextField(
                        controller: durCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Durata (minuti, opzionale)',
                        ),
                      ),
                      TextField(
                        controller: noteCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Note'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salva'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    if (!mounted) return;
    final km = double.tryParse(kmCtrl.text.replaceAll(',', '.'));
    final ped = double.tryParse(pedCtrl.text.replaceAll(',', '.')) ?? 0;
    if (origNome.text.trim().isEmpty ||
        destNome.text.trim().isEmpty ||
        km == null ||
        km < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compila partenza, arrivo e km')),
      );
      return;
    }
    try {
      final t = ViaggioStradaleTratta(
        idUuid: existing?.idUuid ?? '',
        origineTipo: origTipo,
        origineNome: origNome.text.trim(),
        destinazioneTipo: destTipo,
        destinazioneNome: destNome.text.trim(),
        kmStradali: km,
        pedaggioEur: ped,
        pedaggioFonte: 'manuale',
        durataMinuti: int.tryParse(durCtrl.text.trim()),
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        origineRefId: existing?.origineRefId,
        destinazioneRefId: existing?.destinazioneRefId,
        origineLat: existing?.origineLat,
        origineLon: existing?.origineLon,
        destinazioneLat: existing?.destinazioneLat,
        destinazioneLon: existing?.destinazioneLon,
        lastPriceCheckAt: existing?.lastPriceCheckAt,
      );
      await ViaggioStradaleService.upsertTratta(
        t,
        existingId: existing?.idUuid,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Verifica costo stradale';
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: pageTitle),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Calcolo', icon: Icon(Icons.calculate_outlined)),
              Tab(text: 'Tratte', icon: Icon(Icons.route_outlined)),
              Tab(text: 'Impostazioni', icon: Icon(Icons.tune)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Ricarica',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Errore: $_error\n\n'
                      'Se manca la tabella, esegui la migration '
                      'viaggio_stradale_verifica.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildCalcolo(),
                    _buildTratte(),
                    _buildImpostazioni(),
                  ],
                ),
    );
  }

  Widget _buildCalcolo() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Calcola quanto costerebbe far viaggiare il dipendente '
              'con mezzo stradale (carburante + autostrada + costo orario), '
              'per confrontarlo con treno/aereo.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dipendenteNote,
          decoration: const InputDecoration(
            labelText: 'Dipendente / riferimento (opzionale)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        _luogoSearchField(
          label: 'Partenza (stazione / aeroporto)',
          value: _origine,
          onChanged: (v) => setState(() => _origine = v),
        ),
        const SizedBox(height: 12),
        _luogoSearchField(
          label: 'Arrivo (stazione / aeroporto)',
          value: _destinazione,
          onChanged: (v) => setState(() => _destinazione = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _mezzoIdInList(),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Mezzo / modello (consumo L/100km)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final m in _mezzi)
              DropdownMenuItem(
                value: m.id,
                child: Text(m.label, maxLines: 2),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            final m = _mezzi.cast<ViaggioStradaleMezzoOpzione?>().firstWhere(
                  (e) => e?.id == id,
                  orElse: () => null,
                );
            setState(() {
              _mezzo = m;
              if (m != null && m.consumoDaRcc && m.litriPer100Km > 0) {
                _l100Override.text = m.litriPer100Km.toStringAsFixed(1);
              } else {
                _l100Override.clear();
              }
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _l100Override,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Consumo L/100km (modificabile)',
            border: const OutlineInputBorder(),
            helperText: _mezzo?.consumoDaRcc == true
                ? 'Da media RCC del modello (stesso calcolo del riepilogo carburante)'
                : 'Nessun dato RCC per questo modello: inserisci il consumo stimato',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _calcoloBusy ? null : _calcola,
          icon: _calcoloBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.calculate),
          label: Text(
            _calcoloBusy
                ? 'Calcolo in corso…'
                : 'Calcola costo mezzo stradale',
          ),
        ),
        if (_calcoloMsg != null) ...[
          const SizedBox(height: 10),
          Text(_calcoloMsg!, style: TextStyle(color: Colors.blueGrey.shade700)),
        ],
        if (_trattaUsata != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _updatingTrattaId == _trattaUsata!.idUuid
                  ? null
                  : () => _aggiornaTratta(_trattaUsata!),
              icon: const Icon(Icons.sync),
              label: const Text('Aggiorna km / pedaggio tratta'),
            ),
          ),
        ],
        if (_costo != null) ...[
          const SizedBox(height: 16),
          _costoCard(_costo!),
        ],
      ],
    );
  }

  Widget _luogoSearchField({
    required String label,
    required ViaggioStradaleLuogo? value,
    required ValueChanged<ViaggioStradaleLuogo?> onChanged,
  }) {
    String display(ViaggioStradaleLuogo? l) {
      if (l == null) return '';
      final tipo = l.tipo == 'aeroporto'
          ? 'Aeroporto'
          : (l.tipo == 'stazione' ? 'Stazione' : 'Luogo');
      return '$tipo: ${l.nome}';
    }

    return Autocomplete<ViaggioStradaleLuogo>(
      displayStringForOption: display,
      optionsBuilder: (text) {
        final q = text.text.trim().toLowerCase();
        // Se il testo è esattamente la selezione corrente, mostra tutto filtrabile.
        final current = display(value).toLowerCase();
        final query = (q == current) ? '' : q;
        final filtered = query.isEmpty
            ? _luoghi
            : _luoghi.where((l) {
                final hay =
                    '${l.tipo} ${l.nome}'.toLowerCase();
                return hay.contains(query);
              }).toList(growable: false);
        return filtered.take(80);
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        final want = display(value);
        if (controller.text != want && !focusNode.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.text != want) {
              controller.value = TextEditingValue(
                text: want,
                selection: TextSelection.collapsed(offset: want.length),
              );
            }
          });
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            hintText: 'Scrivi per cercare…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Pulisci',
              onPressed: () {
                controller.clear();
                onChanged(null);
              },
              icon: const Icon(Icons.clear),
            ),
          ),
          onChanged: (text) {
            if (text.trim().isEmpty) onChanged(null);
          },
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 520),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final opt = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      opt.tipo == 'aeroporto'
                          ? Icons.flight
                          : Icons.train,
                      size: 20,
                    ),
                    title: Text(display(opt)),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _costoCard(ViaggioStradaleCosto c) {
    final ore = (c.durataMinuti / 60).toStringAsFixed(1);
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Costo stimato mezzo stradale',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (_dipendenteNote.text.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Dipendente: ${_dipendenteNote.text.trim()}'),
            ],
            const SizedBox(height: 12),
            _row('Distanza', '${_kmFmt.format(c.km)} km'),
            _row('Consumo',
                '${c.litriPer100Km.toStringAsFixed(1)} L/100km'),
            _row(
              'Carburante',
              '${_eur.format(c.costoCarburante)} '
              '(${(c.km / 100 * c.litriPer100Km).toStringAsFixed(1)} L × '
              '${_eur.format(c.prezzoCarburante)}/L)',
            ),
            _row('Pedaggio autostrada', _eur.format(c.pedaggio)),
            _row(
              'Tempo persona',
              '${_eur.format(c.costoTempo)} '
              '($ore h × ${_eur.format(c.costoOrario)}/h)',
            ),
            const Divider(height: 20),
            _row(
              'TOTALE stradale',
              _eur.format(c.totale),
              bold: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Confronta questo totale con il prezzo del biglietto '
              'treno/aereo per decidere il mezzo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTratte() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Database tratte (${_tratte.length}): km stradali e pedaggio. '
                  '«Aggiorna» ricalcola km via OpenStreetMap/OSRM e stima pedaggio.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _editTrattaDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nuova'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _tratte.isEmpty
              ? const Center(
                  child: Text(
                    'Nessuna tratta. Calcola un percorso o aggiungine una.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _tratte.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = _tratte[i];
                    final busy = _updatingTrattaId == t.idUuid;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_kmFmt.format(t.kmStradali)} km · '
                              'pedaggio ${_eur.format(t.pedaggioEur)} '
                              '(${t.pedaggioFonte})'
                              '${t.durataMinuti != null ? ' · ${t.durataMinuti} min' : ''}',
                            ),
                            if (t.lastPriceCheckAt != null)
                              Text(
                                'Ultimo aggiornamento: '
                                '${DateFormat('dd/MM/yyyy HH:mm').format(t.lastPriceCheckAt!.toLocal())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _aggiornaTratta(t),
                                  icon: busy
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.sync, size: 18),
                                  label: const Text('Aggiorna prezzi'),
                                ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _aggiornaTratta(
                                            t,
                                            forceToll: true,
                                          ),
                                  child: const Text('Ricalcola anche pedaggio'),
                                ),
                                TextButton(
                                  onPressed: () => _editTrattaDialog(t),
                                  child: const Text('Modifica'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await ViaggioStradaleService
                                        .deactivateTratta(t.idUuid);
                                    await _reload();
                                  },
                                  child: Text(
                                    'Elimina',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildImpostazioni() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Costo orario e carburante',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Usati nel calcolo del totale stradale. '
                  'Il costo orario rappresenta il costo del tempo della persona in viaggio.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _costoOrarioCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Costo orario persona (€/h)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _prezzoCarbCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Prezzo carburante (€/L)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tollPerKmCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Stima pedaggio (€/km autostrada)',
                    border: OutlineInputBorder(),
                    helperText:
                        'Usata da «Aggiorna prezzi» se il pedaggio non è manuale. '
                        'Media Italia tipica ~0,07–0,10 €/km.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _settingsSaving ? null : _saveSettings,
                  icon: _settingsSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Salva impostazioni'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
