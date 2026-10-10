import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/dislocazione_personale_service.dart';
import '../services/dislocazione_riepilogo_excel_export.dart';
import '../services/supabase_service.dart';
import '../utils/dislocazione_period_utils.dart';
import '../utils/excel_export_helper.dart';
import '../utils/personale_name_matcher.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';

const List<String> _kStati = <String>[
  'FERIE',
  'MALATTIA',
  'RIPOSO',
  'PERMESSO',
  'INFORTUNIO',
  'ASPETTATIVA',
  'SEDE',
  'CANTIERE',
  'CORSO',
  'MAGAZZINO',
  'LOGISTICA',
  'AMMINISTRAZIONE',
  'DIREZIONE',
  'QSA',
  'ACQUISTI',
  'ASSENTE',
  'ALTRO',
  'CESSATO',
];

const List<String> _kAttivita = <String>[
  'LFM',
  'IS',
  'TE',
  'OP. CIVILI',
  'PM',
  'DT',
];

/// Voci assenza / fuori forza da evidenziare nel riepilogo sintetico.
const List<String> _kAssenzeRiepilogo = <String>[
  'FERIE',
  'MALATTIA',
  'PERMESSO',
  'INFORTUNIO',
  'RIPOSO',
  'ASPETTATIVA',
  'CORSO',
  'ASSENTE',
  'CESSATO',
  'ALTRO',
];

/// Riepilogo dislocazione a pagina intera, multi-giorno.
class AdminDislocazioneRiepilogoPage extends StatefulWidget {
  const AdminDislocazioneRiepilogoPage({
    super.key,
    required this.persone,
    required this.cacheGiorni,
    required this.commesse,
    required this.dal,
    required this.al,
  });

  final List<PersonaRiga> persone;
  final Map<String, Map<DateTime, DislocazioneGiornoValore>> cacheGiorni;
  final Map<String, String> commesse;
  final DateTime dal;
  final DateTime al;

  @override
  State<AdminDislocazioneRiepilogoPage> createState() =>
      _AdminDislocazioneRiepilogoPageState();
}

class _AdminDislocazioneRiepilogoPageState
    extends State<AdminDislocazioneRiepilogoPage> {
  static const _statiSede = <String>{
    'SEDE',
    'LOGISTICA',
    'AMMINISTRAZIONE',
    'DIREZIONE',
    'QSA',
    'ACQUISTI',
    'MAGAZZINO',
  };

  final _dateFmt = DateFormat('dd/MM');
  final _weekdayFmt = DateFormat('E', 'it_IT');
  final _cercaCtrl = TextEditingController();
  late DateTime _dal;
  late DateTime _al;

  List<_MezzoAnagrafica> _mezziAnagrafica = const [];
  Map<String, List<_MezzoAnagrafica>> _mezziPerNominativo = const {};
  bool _mezziLoading = true;
  String? _mezziError;
  String _cerca = '';
  bool _exportExcelInCorso = false;

  static const double _labelW = 220;
  static const double _dayW = 64;
  static const double _rowH = 36;

  @override
  void initState() {
    super.initState();
    _dal = dateOnly(widget.dal);
    _al = dateOnly(widget.al);
    if (_al.isBefore(_dal)) {
      final t = _dal;
      _dal = _al;
      _al = t;
    }
    _cercaCtrl.addListener(() {
      final next = _cercaCtrl.text.trim().toLowerCase();
      if (next == _cerca) return;
      setState(() => _cerca = next);
    });
    _loadMezziAnagrafica();
  }

  @override
  void dispose() {
    _cercaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMezziAnagrafica() async {
    setState(() {
      _mezziLoading = true;
      _mezziError = null;
    });
    try {
      final res = await SupabaseService.client
          .from('logistica_mezzi_stradali')
          .select(
            'id_uuid,numerazione,targa,marca,modello,tipologia_mezzo,assegnatario_attuale',
          )
          .eq('active', true);
      final rows = <_MezzoAnagrafica>[];
      for (final raw in res as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final numRaw = m['numerazione'];
        rows.add(
          _MezzoAnagrafica(
            id: id,
            numerazione: numRaw is int ? numRaw : int.tryParse('$numRaw'),
            targa: (m['targa'] ?? '').toString().trim(),
            marca: (m['marca'] ?? '').toString().trim(),
            modello: (m['modello'] ?? '').toString().trim(),
            tipologia: (m['tipologia_mezzo'] ?? '').toString().trim(),
            assegnatario: (m['assegnatario_attuale'] ?? '').toString().trim(),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _mezziAnagrafica = rows;
        _mezziPerNominativo = _indiceMezziPerNominativo(rows);
        _mezziLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mezziError = e.toString();
        _mezziLoading = false;
      });
    }
  }

  /// Abbina mezzi (assegnatario_attuale) ai nominativi in dislocazione.
  Map<String, List<_MezzoAnagrafica>> _indiceMezziPerNominativo(
    List<_MezzoAnagrafica> mezzi,
  ) {
    final byAssigneeNorm = <String, List<_MezzoAnagrafica>>{};
    for (final m in mezzi) {
      if (m.assegnatario.isEmpty) continue;
      final k = PersonaleNameMatcher.normalize(m.assegnatario);
      if (k.isEmpty) continue;
      byAssigneeNorm.putIfAbsent(k, () => []).add(m);
    }

    final out = <String, List<_MezzoAnagrafica>>{};
    for (final p in widget.persone) {
      final nom = p.nominativo;
      final k = PersonaleNameMatcher.normalize(nom);
      final found = <_MezzoAnagrafica>[];
      final seen = <String>{};

      void addAll(Iterable<_MezzoAnagrafica> list) {
        for (final m in list) {
          if (seen.add(m.id)) found.add(m);
        }
      }

      addAll(byAssigneeNorm[k] ?? const []);
      if (found.isEmpty) {
        final tokP = PersonaleNameMatcher.tokens(nom).toSet();
        if (tokP.isNotEmpty) {
          for (final e in byAssigneeNorm.entries) {
            final tokA = PersonaleNameMatcher.tokens(e.key).toSet();
            if (tokA.isEmpty) continue;
            if (tokP.length == tokA.length && tokP.containsAll(tokA)) {
              addAll(e.value);
            }
          }
        }
      }
      if (found.isNotEmpty) out[nom] = found;
    }
    return out;
  }

  bool _matchCerca(String raw) {
    if (_cerca.isEmpty) return true;
    return raw.toLowerCase().contains(_cerca);
  }

  String _nomeCommessa(String commessaId) {
    final n = (widget.commesse[commessaId] ?? '').trim();
    return n.isEmpty ? commessaId : n;
  }

  /// Mezzi del giorno collegati alla dislocazione.
  /// [soloSuCommessa]: solo dipendenti con cella su commessa.
  /// Altrimenti: in forza (commessa / cantiere / sede) + mezzi assegnati
  /// in anagrafica non abbinati a un nominativo (es. «SEDE»).
  _MezziGiornoConteggi _conteggiMezziGiorno(
    DateTime giorno, {
    bool soloSuCommessa = false,
  }) {
    final dettagli = _dettaglioMezziGiorno(
      giorno,
      soloSuCommessa: soloSuCommessa,
    );
    final byCommessa = <String, int>{};
    final byTipologia = <String, int>{};
    for (final d in dettagli) {
      byCommessa[d.commessaLabel] = (byCommessa[d.commessaLabel] ?? 0) + 1;
      byTipologia[d.tipologia] = (byTipologia[d.tipologia] ?? 0) + 1;
    }
    return _MezziGiornoConteggi(
      totale: dettagli.length,
      byCommessa: byCommessa,
      byTipologia: byTipologia,
    );
  }

  /// Destinazione «in forza» per collegare il mezzo: commessa, cantiere o sede.
  String? _labelDislocazioneMezzo(
    DislocazioneGiornoValore v, {
    required bool soloSuCommessa,
  }) {
    final cid = (v.commessaId ?? '').trim();
    if (cid.isNotEmpty) return _nomeCommessa(cid);
    if (soloSuCommessa) return null;
    final st = (v.stato ?? '').trim().toUpperCase();
    if (st == 'CANTIERE') return 'CANTIERE';
    if (_statiSede.contains(st)) return st;
    return null;
  }

  List<_MezzoDettaglioRiga> _dettaglioMezziGiorno(
    DateTime giorno, {
    String? tipologia,
    String? commessaLabel,
    bool soloSuCommessa = false,
  }) {
    final seenMezzo = <String>{};
    final out = <_MezzoDettaglioRiga>[];

    for (final p in widget.persone) {
      final v = _valore(p.nominativo, giorno);
      if (v == null || v.isEmpty) continue;
      final label = _labelDislocazioneMezzo(v, soloSuCommessa: soloSuCommessa);
      if (label == null) continue;

      final mezzi = _mezziPerNominativo[p.nominativo] ?? const [];
      if (mezzi.isEmpty) continue;

      if (commessaLabel != null && label != commessaLabel) continue;

      for (final m in mezzi) {
        if (!seenMezzo.add(m.id)) continue;
        final tip = m.tipologia.isEmpty ? 'Senza tipologia' : m.tipologia;
        if (tipologia != null && tip != tipologia) continue;
        out.add(
          _MezzoDettaglioRiga(
            nominativo: p.nominativo,
            commessaLabel: label,
            mezzo: m,
            tipologia: tip,
          ),
        );
      }
    }

    // Mezzi con assegnatario in anagrafica non abbinati a un nominativo
    // (es. «SEDE», pool, etichette organizzative): nel totale per tipologia.
    if (!soloSuCommessa && commessaLabel == null) {
      final matchedIds = <String>{
        for (final list in _mezziPerNominativo.values)
          for (final m in list) m.id,
      };
      for (final m in _mezziAnagrafica) {
        if (m.assegnatario.isEmpty) continue;
        if (matchedIds.contains(m.id)) continue;
        if (!seenMezzo.add(m.id)) continue;
        final tip = m.tipologia.isEmpty ? 'Senza tipologia' : m.tipologia;
        if (tipologia != null && tip != tipologia) continue;
        out.add(
          _MezzoDettaglioRiga(
            nominativo: m.assegnatario,
            commessaLabel: m.assegnatario,
            mezzo: m,
            tipologia: tip,
          ),
        );
      }
    }

    out.sort((a, b) {
      final c = a.commessaLabel.toLowerCase().compareTo(b.commessaLabel.toLowerCase());
      if (c != 0) return c;
      return a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase());
    });
    return out;
  }

  Future<void> _mostraPopupListaMezzi({
    required DateTime giorno,
    required String voce,
    String? tipologia,
    String? commessaLabel,
    bool soloSuCommessa = false,
  }) async {
    final lista = _dettaglioMezziGiorno(
      giorno,
      tipologia: tipologia,
      commessaLabel: commessaLabel,
      soloSuCommessa: soloSuCommessa,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Mezzi · $voce'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_dateFmt.format(giorno)} · ${lista.length} '
                  '${lista.length == 1 ? 'mezzo' : 'mezzi'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                if (lista.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Nessun mezzo in elenco.')),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: lista.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = lista[i];
                        final m = r.mezzo;
                        final targa = m.targa.isEmpty ? '—' : m.targa;
                        final modello = m.modello.isEmpty
                            ? (m.marca.isEmpty ? '' : m.marca)
                            : (m.marca.isEmpty
                                ? m.modello
                                : '${m.marca} ${m.modello}');
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.local_shipping_outlined,
                            color: Colors.amber.shade800,
                          ),
                          title: Text(
                            '$targa${modello.isEmpty ? '' : ' · $modello'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              r.nominativo,
                              r.commessaLabel,
                              r.tipologia,
                            ].join(' · '),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _mostraPopupListaPersonale({
    required DateTime giorno,
    required String voce,
    required _PersonaleFiltro filtro,
  }) async {
    final lista = _dettaglioPersonaleGiorno(giorno, filtro);
    if (!mounted || lista.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Personale · $voce'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_dateFmt.format(giorno)} · ${lista.length} '
                  '${lista.length == 1 ? 'nominativo' : 'nominativi'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = lista[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.person_outline,
                          color: Colors.blue.shade800,
                        ),
                        title: Text(
                          r.nominativo,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            r.assegnazione,
                            if (r.attivita.isNotEmpty) 'Attività: ${r.attivita}',
                          ].join(' · '),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  List<_PersonaleDettaglioRiga> _dettaglioPersonaleGiorno(
    DateTime giorno,
    _PersonaleFiltro filtro,
  ) {
    final out = <_PersonaleDettaglioRiga>[];
    for (final p in widget.persone) {
      final at = _normAttivita(p.attivita);
      final v = _valore(p.nominativo, giorno);

      var suCommessa = false;
      var suCantiere = false;
      var suSede = false;
      var nonAssegnato = false;
      var assenzaKey = '';
      var altreVoci = false;
      var voceLabel = '';

      if (v == null || v.isEmpty) {
        nonAssegnato = true;
        voceLabel = 'Non assegnato';
      } else if (v.commessaId != null && v.commessaId!.isNotEmpty) {
        suCommessa = true;
        voceLabel = (widget.commesse[v.commessaId!] ?? '').trim();
        if (voceLabel.isEmpty) voceLabel = v.commessaId!;
      } else {
        final st = (v.stato ?? '').trim().toUpperCase();
        if (st.isEmpty) {
          nonAssegnato = true;
          voceLabel = 'Non assegnato';
        } else {
          voceLabel = st;
          if (st == 'CANTIERE') {
            suCantiere = true;
          } else if (_statiSede.contains(st)) {
            suSede = true;
          } else if (_kAssenzeRiepilogo.contains(st)) {
            assenzaKey = st;
          } else {
            altreVoci = true;
          }
        }
      }

      final inForza = suCommessa || suCantiere || suSede;
      final attivitaKey = at.isEmpty
          ? ((v != null && !v.isEmpty && !nonAssegnato)
              ? '(senza attività)'
              : '')
          : at;

      var match = false;
      switch (filtro.tipo) {
        case _PersonaleFiltroTipo.suCommessa:
          match = suCommessa;
        case _PersonaleFiltroTipo.suCantiere:
          match = suCantiere;
        case _PersonaleFiltroTipo.suSede:
          match = suSede;
        case _PersonaleFiltroTipo.inForza:
          match = inForza;
        case _PersonaleFiltroTipo.assenza:
          match = assenzaKey == filtro.key;
        case _PersonaleFiltroTipo.assenti:
          match = assenzaKey.isNotEmpty || altreVoci;
        case _PersonaleFiltroTipo.altreVoci:
          match = altreVoci;
        case _PersonaleFiltroTipo.nonAssegnati:
          match = nonAssegnato;
        case _PersonaleFiltroTipo.tutti:
          match = true;
        case _PersonaleFiltroTipo.attivita:
          match = attivitaKey == filtro.key;
        case _PersonaleFiltroTipo.voce:
          match = !nonAssegnato && voceLabel == filtro.key;
      }
      if (!match) continue;

      out.add(
        _PersonaleDettaglioRiga(
          nominativo: p.nominativo,
          assegnazione: voceLabel,
          attivita: at,
        ),
      );
    }
    out.sort(
      (a, b) => a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase()),
    );
    return out;
  }

  void Function(int dayIndex)? _tapPersonale({
    required List<DateTime> giorni,
    required String voce,
    required _PersonaleFiltro filtro,
    required int Function(DateTime g) countOf,
  }) {
    return (dayIndex) {
      if (dayIndex < 0 || dayIndex >= giorni.length) return;
      final g = giorni[dayIndex];
      if (countOf(g) <= 0) return;
      _mostraPopupListaPersonale(giorno: g, voce: voce, filtro: filtro);
    };
  }

  List<DateTime> get _giorni {
    final out = <DateTime>[];
    var d = _dal;
    while (!d.isAfter(_al)) {
      out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  DislocazioneGiornoValore? _valore(String nominativo, DateTime giorno) {
    final d = dateOnly(giorno);
    final direct = widget.cacheGiorni[nominativo]?[d];
    if (direct != null && !direct.isEmpty) return direct;
    final key = nominativo.trim().toUpperCase();
    for (final e in widget.cacheGiorni.entries) {
      if (e.key.trim().toUpperCase() == key) {
        final v = e.value[d];
        if (v != null && !v.isEmpty) return v;
      }
    }
    // Match senza spazi multipli / punteggiatura leggera.
    final keyLoose = key.replaceAll(RegExp(r'\s+'), ' ');
    for (final e in widget.cacheGiorni.entries) {
      final ek = e.key.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (ek == keyLoose) {
        final v = e.value[d];
        if (v != null && !v.isEmpty) return v;
      }
    }
    return null;
  }

  static String _normAttivita(String? raw) {
    final t = (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty || t == '-' || t == '—') return '';
    if (t == 'OP CIVILI' || t == 'OP.CIVILI' || t.startsWith('OP.')) {
      return 'OP. CIVILI';
    }
    final compact = t.replaceAll('.', '').replaceAll(' ', '');
    if (compact == 'DT' || t == 'D.T.' || t.startsWith('DT')) return 'DT';
    if (compact == 'PM' || t == 'P.M.' || t.startsWith('PM')) return 'PM';
    return t;
  }

  static String _pct(int n, int tot) {
    if (tot <= 0) return '0,00%';
    final p = (n * 10000 / tot).round() / 100;
    return '${p.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  /// Ordine A–Z / 1–999 (numeri confrontati numericamente, es. TE-02 prima di TE-26).
  static int _confrontaVoceAlfanumerica(String a, String b) {
    final pa = _tokenAlfanumerici(a);
    final pb = _tokenAlfanumerici(b);
    final n = pa.length < pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final ta = pa[i];
      final tb = pb[i];
      final na = int.tryParse(ta);
      final nb = int.tryParse(tb);
      if (na != null && nb != null) {
        final c = na.compareTo(nb);
        if (c != 0) return c;
      } else {
        final c = ta.compareTo(tb);
        if (c != 0) return c;
      }
    }
    return pa.length.compareTo(pb.length);
  }

  static List<String> _tokenAlfanumerici(String raw) {
    final out = <String>[];
    final re = RegExp(r'\d+|[a-zA-Zàèéìòù]+', caseSensitive: false);
    for (final m in re.allMatches(raw.toLowerCase())) {
      out.add(m.group(0)!);
    }
    return out;
  }

  static Color _coloreAttivita(String key) {
    switch (key) {
      case 'LFM':
        return const Color(0xFF5B9BD5);
      case 'IS':
        return const Color(0xFFF4B183);
      case 'OP. CIVILI':
        return const Color(0xFF9DC3E6);
      case 'TE':
        return const Color(0xFFA9D08E);
      case 'PM':
        return const Color(0xFFC5A0D8);
      case 'DT':
        return const Color(0xFFFFD966);
      default:
        return Colors.grey.shade200;
    }
  }

  _GiornoConteggi _conteggiGiorno(DateTime giorno) {
    var suCommessa = 0;
    var suCantiere = 0;
    var suSede = 0;
    var nonAssegnati = 0;
    var altreVoci = 0;
    final byAttivita = <String, int>{
      for (final a in _kAttivita) a: 0,
    };
    final byVoce = <String, int>{};
    final byAssenza = <String, int>{
      for (final s in _kAssenzeRiepilogo) s: 0,
    };

    for (final p in widget.persone) {
      final at = _normAttivita(p.attivita);
      final v = _valore(p.nominativo, giorno);
      if (v == null || v.isEmpty) {
        nonAssegnati++;
        // Attività è sul nominativo: conta anche senza cella giorno (es. DT).
        if (at.isNotEmpty) {
          byAttivita[at] = (byAttivita[at] ?? 0) + 1;
        }
        continue;
      }

      void contaAttivita() {
        if (at.isEmpty) {
          byAttivita['(senza attività)'] =
              (byAttivita['(senza attività)'] ?? 0) + 1;
        } else {
          byAttivita[at] = (byAttivita[at] ?? 0) + 1;
        }
      }

      if (v.commessaId != null && v.commessaId!.isNotEmpty) {
        suCommessa++;
        contaAttivita();
        var label = (widget.commesse[v.commessaId!] ?? '').trim();
        if (label.isEmpty) label = v.commessaId!;
        byVoce[label] = (byVoce[label] ?? 0) + 1;
      } else {
        final st = (v.stato ?? '').trim().toUpperCase();
        if (st.isEmpty) {
          nonAssegnati++;
          if (at.isNotEmpty) {
            byAttivita[at] = (byAttivita[at] ?? 0) + 1;
          }
          continue;
        }
        byVoce[st] = (byVoce[st] ?? 0) + 1;
        contaAttivita();
        if (st == 'CANTIERE') {
          suCantiere++;
        } else if (_statiSede.contains(st)) {
          suSede++;
        } else if (byAssenza.containsKey(st)) {
          byAssenza[st] = (byAssenza[st] ?? 0) + 1;
        } else {
          altreVoci++;
        }
      }
    }

    return _GiornoConteggi(
      suCommessa: suCommessa,
      suCantiere: suCantiere,
      suSede: suSede,
      nonAssegnati: nonAssegnati,
      altreVoci: altreVoci,
      totaleDipendenti: widget.persone.length,
      byAttivita: byAttivita,
      byVoce: byVoce,
      byAssenza: byAssenza,
    );
  }

  static String _excelHex(Color c) =>
      DislocazioneRiepilogoExcelExport.hexFromArgb(c.toARGB32());

  Future<void> _exportExcel() async {
    if (_exportExcelInCorso) return;
    setState(() => _exportExcelInCorso = true);
    try {
      final giorni = _giorni;
      final perGiorno = <DateTime, _GiornoConteggi>{
        for (final g in giorni) g: _conteggiGiorno(g),
      };
      final perMezziTipologia = <DateTime, _MezziGiornoConteggi>{
        for (final g in giorni) g: _conteggiMezziGiorno(g),
      };
      final perMezziCommessa = <DateTime, _MezziGiornoConteggi>{
        for (final g in giorni)
          g: _conteggiMezziGiorno(g, soloSuCommessa: true),
      };

      final vociKeys = <String>{};
      for (final c in perGiorno.values) {
        vociKeys.addAll(c.byVoce.keys);
      }
      for (final nome in widget.commesse.values) {
        final t = nome.trim();
        if (t.isNotEmpty) vociKeys.add(t);
      }
      for (final s in _kStati) {
        vociKeys.add(s);
      }
      final vociOrdinate = vociKeys.toList()
        ..sort((a, b) {
          final aStato = _kStati.contains(a.toUpperCase());
          final bStato = _kStati.contains(b.toUpperCase());
          if (aStato != bStato) return aStato ? 1 : -1;
          return _confrontaVoceAlfanumerica(a, b);
        });
      final vociConDati = vociOrdinate
          .where(
            (k) => giorni.any((g) => (perGiorno[g]!.byVoce[k] ?? 0) > 0),
          )
          .toList();

      final attivitaKeys = <String>[
        ..._kAttivita,
        ...{
          for (final c in perGiorno.values) ...c.byAttivita.keys,
        }.where((k) => !_kAttivita.contains(k)),
      ];

      List<int> vals(int Function(_GiornoConteggi c) f) =>
          [for (final g in giorni) f(perGiorno[g]!)];
      List<int> tots() =>
          [for (final g in giorni) perGiorno[g]!.totaleDipendenti];

      final sezioneForza = DislocazioneRiepilogoExcelSection(
        title: 'Personale in forza',
        rows: [
          DislocazioneRiepilogoExcelRow(
            label: 'PERSONALE SU COMMESSA',
            values: vals((c) => c.suCommessa),
            totaliGiorno: tots(),
            showPct: true,
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'PERSONALE SU CANTIERE (INDIRETTI)',
            values: vals((c) => c.suCantiere),
            totaliGiorno: tots(),
            showPct: true,
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'PERSONALE SU SEDE',
            values: vals((c) => c.suSede),
            totaliGiorno: tots(),
            showPct: true,
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'TOTALE PERSONALE CRONOS IN FORZA',
            values: vals((c) => c.totaleInForza),
            totaliGiorno: tots(),
            showPct: true,
            emphasize: true,
            bgHex: 'A9D08E',
          ),
          for (final st in _kAssenzeRiepilogo)
            if (giorni.any((g) => (perGiorno[g]!.byAssenza[st] ?? 0) > 0))
              DislocazioneRiepilogoExcelRow(
                label: st,
                values: vals((c) => c.byAssenza[st] ?? 0),
                totaliGiorno: tots(),
                showPct: true,
                isStato: true,
                bgHex: _excelHex(Colors.orange.shade50),
              ),
          if (giorni.any((g) => perGiorno[g]!.altreVoci > 0))
            DislocazioneRiepilogoExcelRow(
              label: 'ALTRE VOCI',
              values: vals((c) => c.altreVoci),
              totaliGiorno: tots(),
              showPct: true,
              isStato: true,
            ),
          DislocazioneRiepilogoExcelRow(
            label: 'TOTALE ASSENTI (FERIE, CORSI, ECC.)',
            values: vals((c) => c.totaleAssenti),
            totaliGiorno: tots(),
            showPct: true,
            emphasize: true,
            bgHex: _excelHex(Colors.orange.shade200),
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'NON ASSEGNATI',
            values: vals((c) => c.nonAssegnati),
            totaliGiorno: tots(),
            showPct: true,
            isStato: true,
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'TOTALE DIPENDENTI AZIENDA',
            values: vals((c) => c.totaleDipendenti),
            totaliGiorno: tots(),
            showPct: true,
            emphasize: true,
            bgHex: _excelHex(Colors.blue.shade100),
          ),
        ],
      );

      final sezioneAttivita = DislocazioneRiepilogoExcelSection(
        title: 'Personale per attività (commessa / cantiere / sede)',
        rows: [
          for (final key in attivitaKeys)
            DislocazioneRiepilogoExcelRow(
              label: key,
              values: vals((c) => c.byAttivita[key] ?? 0),
              totaliGiorno: tots(),
              showPct: true,
              bgHex: _excelHex(_coloreAttivita(key)),
            ),
          DislocazioneRiepilogoExcelRow(
            label: 'Totale su commessa',
            values: vals((c) => c.suCommessa),
            totaliGiorno: tots(),
            showPct: true,
            emphasize: true,
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'PERSONALE SU CANTIERE (INDIRETTI)',
            values: vals((c) => c.suCantiere),
            totaliGiorno: tots(),
            showPct: true,
            isStato: true,
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'PERSONALE SU SEDE',
            values: vals((c) => c.suSede),
            totaliGiorno: tots(),
            showPct: true,
            isStato: true,
          ),
          for (final st in _kAssenzeRiepilogo)
            if (giorni.any((g) => (perGiorno[g]!.byAssenza[st] ?? 0) > 0))
              DislocazioneRiepilogoExcelRow(
                label: st,
                values: vals((c) => c.byAssenza[st] ?? 0),
                totaliGiorno: tots(),
                showPct: true,
                isStato: true,
                bgHex: _excelHex(Colors.orange.shade50),
              ),
          if (giorni.any((g) => perGiorno[g]!.altreVoci > 0))
            DislocazioneRiepilogoExcelRow(
              label: 'ALTRE VOCI',
              values: vals((c) => c.altreVoci),
              totaliGiorno: tots(),
              showPct: true,
              isStato: true,
            ),
          DislocazioneRiepilogoExcelRow(
            label: 'TOTALE ASSENTI (FERIE, CORSI, ECC.)',
            values: vals((c) => c.totaleAssenti),
            totaliGiorno: tots(),
            showPct: true,
            emphasize: true,
            bgHex: _excelHex(Colors.orange.shade200),
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'NON ASSEGNATI',
            values: vals((c) => c.nonAssegnati),
            totaliGiorno: tots(),
            showPct: true,
            isStato: true,
          ),
          DislocazioneRiepilogoExcelRow(
            label: 'TOTALE DIPENDENTI AZIENDA',
            values: vals((c) => c.totaleDipendenti),
            totaliGiorno: tots(),
            showPct: true,
            emphasize: true,
            bgHex: _excelHex(Colors.blue.shade100),
          ),
        ],
      );

      final sezioneDettaglio = DislocazioneRiepilogoExcelSection(
        title: 'Dettaglio per commessa / stato',
        rows: [
          for (final voce in vociConDati)
            DislocazioneRiepilogoExcelRow(
              label: voce,
              values: vals((c) => c.byVoce[voce] ?? 0),
              isStato: _kStati.contains(voce.toUpperCase()),
            ),
        ],
      );

      final tipKeys = <String>{};
      final commKeys = <String>{};
      for (final c in perMezziTipologia.values) {
        tipKeys.addAll(c.byTipologia.keys);
      }
      for (final c in perMezziCommessa.values) {
        commKeys.addAll(c.byCommessa.keys);
      }
      final tipOrdinate = tipKeys.toList()..sort(_confrontaVoceAlfanumerica);
      final tipConDati = tipOrdinate
          .where(
            (k) => giorni.any((g) => (perMezziTipologia[g]!.byTipologia[k] ?? 0) > 0),
          )
          .toList();
      final commOrdinate = commKeys.toList()..sort(_confrontaVoceAlfanumerica);
      final commConDati = commOrdinate
          .where(
            (k) => giorni.any((g) => (perMezziCommessa[g]!.byCommessa[k] ?? 0) > 0),
          )
          .toList();

      List<int> mTipVals(int Function(_MezziGiornoConteggi c) f) =>
          [for (final g in giorni) f(perMezziTipologia[g]!)];
      List<int> mCommVals(int Function(_MezziGiornoConteggi c) f) =>
          [for (final g in giorni) f(perMezziCommessa[g]!)];

      final sections = <DislocazioneRiepilogoExcelSection>[
        sezioneForza,
        sezioneAttivita,
        if (sezioneDettaglio.rows.isNotEmpty) sezioneDettaglio,
        if (tipConDati.isNotEmpty)
          DislocazioneRiepilogoExcelSection(
            title: 'Mezzi per tipologia (totale in forza + anagrafica)',
            rows: [
              for (final tip in tipConDati)
                DislocazioneRiepilogoExcelRow(
                  label: tip,
                  values: mTipVals((c) => c.byTipologia[tip] ?? 0),
                ),
              DislocazioneRiepilogoExcelRow(
                label: 'TOTALE MEZZI',
                values: mTipVals((c) => c.totale),
                emphasize: true,
                bgHex: 'FFF59D',
              ),
            ],
          ),
        if (commConDati.isNotEmpty)
          DislocazioneRiepilogoExcelSection(
            title: 'Mezzi per commessa',
            rows: [
              for (final c in commConDati)
                DislocazioneRiepilogoExcelRow(
                  label: c,
                  values: mCommVals((m) => m.byCommessa[c] ?? 0),
                ),
              DislocazioneRiepilogoExcelRow(
                label: 'TOTALE SU COMMESSA',
                values: mCommVals((c) => c.totale),
                emphasize: true,
                bgHex: _excelHex(Colors.blue.shade100),
              ),
            ],
          ),
      ];

      final bytes = DislocazioneRiepilogoExcelExport.build(
        dal: _dal,
        al: _al,
        nominativiCount: widget.persone.length,
        giorni: giorni,
        sections: sections,
      );
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Riepilogo_dislocazione',
        bytes: bytes,
      );
      if (!mounted) return;
      final path = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Excel esportato${path.isNotEmpty ? ': $path' : ''}'
                : 'Export Excel annullato',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export Excel non riuscito: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportExcelInCorso = false);
    }
  }

  Future<void> _scegliDal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dal = dateOnly(picked);
      if (_al.isBefore(_dal)) _al = _dal;
    });
  }

  Future<void> _scegliAl() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _al,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _al = dateOnly(picked);
      if (_al.isBefore(_dal)) _dal = _al;
    });
  }

  @override
  Widget build(BuildContext context) {
    final giorni = _giorni;
    final perGiorno = <DateTime, _GiornoConteggi>{
      for (final g in giorni) g: _conteggiGiorno(g),
    };

    final vociKeys = <String>{};
    for (final c in perGiorno.values) {
      vociKeys.addAll(c.byVoce.keys);
    }
    for (final nome in widget.commesse.values) {
      final t = nome.trim();
      if (t.isNotEmpty) vociKeys.add(t);
    }
    for (final s in _kStati) {
      vociKeys.add(s);
    }
    final vociOrdinate = vociKeys.toList()
      ..sort((a, b) {
        final aStato = _kStati.contains(a.toUpperCase());
        final bStato = _kStati.contains(b.toUpperCase());
        if (aStato != bStato) return aStato ? 1 : -1; // commesse prima
        return _confrontaVoceAlfanumerica(a, b);
      });
    final vociConDati = vociOrdinate
        .where(
          (k) => giorni.any((g) => (perGiorno[g]!.byVoce[k] ?? 0) > 0),
        )
        .toList();

    final attivitaKeys = <String>[
      ..._kAttivita,
      ...{
        for (final c in perGiorno.values) ...c.byAttivita.keys,
      }.where((k) => !_kAttivita.contains(k)),
    ];

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Riepilogo dislocazione'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _exportExcelInCorso ? null : _exportExcel,
                icon: _exportExcelInCorso
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: Text(_exportExcelInCorso ? 'Export…' : 'Export Excel'),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 1,
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Periodo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.blueGrey.shade800,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _scegliDal,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text('Dal ${_dateFmt.format(_dal)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _scegliAl,
                    icon: const Icon(Icons.event, size: 16),
                    label: Text('Al ${_dateFmt.format(_al)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportExcelInCorso ? null : _exportExcel,
                    icon: const Icon(Icons.table_view_outlined, size: 16),
                    label: const Text('Export Excel'),
                  ),
                  Text(
                    '${giorni.length} giorni · ${widget.persone.length} nominativi · clicca un numero per la lista',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _cercaCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Cerca voce / mezzo…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _cerca.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _cercaCtrl.clear();
                                },
                              ),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _sectionTitle('Personale in forza'),
                const SizedBox(height: 8),
                _matrixCard(
                  rows: [
                    _MatrixRow(
                      label: 'PERSONALE SU COMMESSA',
                      values: [for (final g in giorni) perGiorno[g]!.suCommessa],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'PERSONALE SU COMMESSA',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.suCommessa),
                        countOf: (g) => perGiorno[g]!.suCommessa,
                      ),
                    ),
                    _MatrixRow(
                      label: 'PERSONALE SU CANTIERE (INDIRETTI)',
                      values: [for (final g in giorni) perGiorno[g]!.suCantiere],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'PERSONALE SU CANTIERE (INDIRETTI)',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.suCantiere),
                        countOf: (g) => perGiorno[g]!.suCantiere,
                      ),
                    ),
                    _MatrixRow(
                      label: 'PERSONALE SU SEDE',
                      values: [for (final g in giorni) perGiorno[g]!.suSede],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'PERSONALE SU SEDE',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.suSede),
                        countOf: (g) => perGiorno[g]!.suSede,
                      ),
                    ),
                    _MatrixRow(
                      label: 'TOTALE PERSONALE CRONOS IN FORZA',
                      values: [
                        for (final g in giorni) perGiorno[g]!.totaleInForza,
                      ],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      emphasize: true,
                      bg: const Color(0xFFA9D08E),
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'TOTALE PERSONALE CRONOS IN FORZA',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.inForza),
                        countOf: (g) => perGiorno[g]!.totaleInForza,
                      ),
                    ),
                    for (final st in _kAssenzeRiepilogo)
                      if (giorni.any((g) => (perGiorno[g]!.byAssenza[st] ?? 0) > 0))
                        _MatrixRow(
                          label: st,
                          values: [
                            for (final g in giorni) perGiorno[g]!.byAssenza[st] ?? 0,
                          ],
                          totaliGiorno: [
                            for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                          ],
                          showPct: true,
                          isStato: true,
                          bg: Colors.orange.shade50,
                          onDayTap: _tapPersonale(
                            giorni: giorni,
                            voce: st,
                            filtro: _PersonaleFiltro(_PersonaleFiltroTipo.assenza, st),
                            countOf: (g) => perGiorno[g]!.byAssenza[st] ?? 0,
                          ),
                        ),
                    if (giorni.any((g) => perGiorno[g]!.altreVoci > 0))
                      _MatrixRow(
                        label: 'ALTRE VOCI',
                        values: [for (final g in giorni) perGiorno[g]!.altreVoci],
                        totaliGiorno: [
                          for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                        ],
                        showPct: true,
                        isStato: true,
                        onDayTap: _tapPersonale(
                          giorni: giorni,
                          voce: 'ALTRE VOCI',
                          filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.altreVoci),
                          countOf: (g) => perGiorno[g]!.altreVoci,
                        ),
                      ),
                    _MatrixRow(
                      label: 'TOTALE ASSENTI (FERIE, CORSI, ECC.)',
                      values: [
                        for (final g in giorni) perGiorno[g]!.totaleAssenti,
                      ],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      emphasize: true,
                      bg: Colors.orange.shade200,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'TOTALE ASSENTI (FERIE, CORSI, ECC.)',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.assenti),
                        countOf: (g) => perGiorno[g]!.totaleAssenti,
                      ),
                    ),
                    _MatrixRow(
                      label: 'NON ASSEGNATI',
                      values: [for (final g in giorni) perGiorno[g]!.nonAssegnati],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      isStato: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'NON ASSEGNATI',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.nonAssegnati),
                        countOf: (g) => perGiorno[g]!.nonAssegnati,
                      ),
                    ),
                    _MatrixRow(
                      label: 'TOTALE DIPENDENTI AZIENDA',
                      values: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      emphasize: true,
                      bg: Colors.blue.shade100,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'TOTALE DIPENDENTI AZIENDA',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.tutti),
                        countOf: (g) => perGiorno[g]!.totaleDipendenti,
                      ),
                    ),
                  ].where((r) => _matchCerca(r.label)).toList(),
                  giorni: giorni,
                ),
                const SizedBox(height: 22),
                _sectionTitle('Personale per attività (commessa / cantiere / sede)'),
                const SizedBox(height: 8),
                _matrixCard(
                  rows: [
                    for (final key in attivitaKeys)
                      _MatrixRow(
                        label: key,
                        values: [
                          for (final g in giorni) perGiorno[g]!.byAttivita[key] ?? 0,
                        ],
                        totaliGiorno: [
                          for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                        ],
                        showPct: true,
                        bg: _coloreAttivita(key),
                        onDayTap: _tapPersonale(
                          giorni: giorni,
                          voce: key,
                          filtro: _PersonaleFiltro(_PersonaleFiltroTipo.attivita, key),
                          countOf: (g) => perGiorno[g]!.byAttivita[key] ?? 0,
                        ),
                      ),
                    _MatrixRow(
                      label: 'Totale su commessa',
                      values: [for (final g in giorni) perGiorno[g]!.suCommessa],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      emphasize: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'Totale su commessa',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.suCommessa),
                        countOf: (g) => perGiorno[g]!.suCommessa,
                      ),
                    ),
                    _MatrixRow(
                      label: 'PERSONALE SU CANTIERE (INDIRETTI)',
                      values: [for (final g in giorni) perGiorno[g]!.suCantiere],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      isStato: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'PERSONALE SU CANTIERE (INDIRETTI)',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.suCantiere),
                        countOf: (g) => perGiorno[g]!.suCantiere,
                      ),
                    ),
                    _MatrixRow(
                      label: 'PERSONALE SU SEDE',
                      values: [for (final g in giorni) perGiorno[g]!.suSede],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      isStato: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'PERSONALE SU SEDE',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.suSede),
                        countOf: (g) => perGiorno[g]!.suSede,
                      ),
                    ),
                    for (final st in _kAssenzeRiepilogo)
                      if (giorni.any((g) => (perGiorno[g]!.byAssenza[st] ?? 0) > 0))
                        _MatrixRow(
                          label: st,
                          values: [
                            for (final g in giorni) perGiorno[g]!.byAssenza[st] ?? 0,
                          ],
                          totaliGiorno: [
                            for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                          ],
                          showPct: true,
                          isStato: true,
                          bg: Colors.orange.shade50,
                          onDayTap: _tapPersonale(
                            giorni: giorni,
                            voce: st,
                            filtro: _PersonaleFiltro(_PersonaleFiltroTipo.assenza, st),
                            countOf: (g) => perGiorno[g]!.byAssenza[st] ?? 0,
                          ),
                        ),
                    if (giorni.any((g) => perGiorno[g]!.altreVoci > 0))
                      _MatrixRow(
                        label: 'ALTRE VOCI',
                        values: [for (final g in giorni) perGiorno[g]!.altreVoci],
                        totaliGiorno: [
                          for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                        ],
                        showPct: true,
                        isStato: true,
                        onDayTap: _tapPersonale(
                          giorni: giorni,
                          voce: 'ALTRE VOCI',
                          filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.altreVoci),
                          countOf: (g) => perGiorno[g]!.altreVoci,
                        ),
                      ),
                    _MatrixRow(
                      label: 'TOTALE ASSENTI (FERIE, CORSI, ECC.)',
                      values: [
                        for (final g in giorni) perGiorno[g]!.totaleAssenti,
                      ],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      emphasize: true,
                      bg: Colors.orange.shade200,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'TOTALE ASSENTI (FERIE, CORSI, ECC.)',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.assenti),
                        countOf: (g) => perGiorno[g]!.totaleAssenti,
                      ),
                    ),
                    _MatrixRow(
                      label: 'NON ASSEGNATI',
                      values: [for (final g in giorni) perGiorno[g]!.nonAssegnati],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      isStato: true,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'NON ASSEGNATI',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.nonAssegnati),
                        countOf: (g) => perGiorno[g]!.nonAssegnati,
                      ),
                    ),
                    _MatrixRow(
                      label: 'TOTALE DIPENDENTI AZIENDA',
                      values: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      totaliGiorno: [
                        for (final g in giorni) perGiorno[g]!.totaleDipendenti,
                      ],
                      showPct: true,
                      emphasize: true,
                      bg: Colors.blue.shade100,
                      onDayTap: _tapPersonale(
                        giorni: giorni,
                        voce: 'TOTALE DIPENDENTI AZIENDA',
                        filtro: const _PersonaleFiltro(_PersonaleFiltroTipo.tutti),
                        countOf: (g) => perGiorno[g]!.totaleDipendenti,
                      ),
                    ),
                  ].where((r) => _matchCerca(r.label)).toList(),
                  giorni: giorni,
                ),
                const SizedBox(height: 22),
                _sectionTitle('Dettaglio per commessa / stato'),
                const SizedBox(height: 8),
                if (vociConDati.where(_matchCerca).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Nessuna assegnazione nel periodo.')),
                  )
                else
                  _matrixCard(
                    rows: [
                      for (final voce in vociConDati.where(_matchCerca))
                        _MatrixRow(
                          label: voce,
                          values: [
                            for (final g in giorni) perGiorno[g]!.byVoce[voce] ?? 0,
                          ],
                          isStato: _kStati.contains(voce.toUpperCase()),
                          onDayTap: _tapPersonale(
                            giorni: giorni,
                            voce: voce,
                            filtro: _PersonaleFiltro(_PersonaleFiltroTipo.voce, voce),
                            countOf: (g) => perGiorno[g]!.byVoce[voce] ?? 0,
                          ),
                        ),
                    ],
                    giorni: giorni,
                    maxBodyHeight: 420,
                  ),
                const SizedBox(height: 22),
                _sectionTitle('Mezzi stradali'),
                const SizedBox(height: 4),
                Text(
                  'Tipologia: totale mezzi di chi è in forza (commessa, cantiere, sede/DT/PM…) '
                  'più mezzi assegnati in anagrafica non legati a un nominativo. '
                  'La sezione «per commessa» resta solo su commessa.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                _buildMezziSection(giorni),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMezziSection(List<DateTime> giorni) {
    if (_mezziLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_mezziError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Errore caricamento mezzi: $_mezziError',
              style: TextStyle(color: Colors.red.shade800),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadMezziAnagrafica,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      );
    }

    final perTipologia = <DateTime, _MezziGiornoConteggi>{
      for (final g in giorni) g: _conteggiMezziGiorno(g),
    };
    final perCommessa = <DateTime, _MezziGiornoConteggi>{
      for (final g in giorni)
        g: _conteggiMezziGiorno(g, soloSuCommessa: true),
    };

    final tipKeys = <String>{};
    final commKeys = <String>{};
    for (final c in perTipologia.values) {
      tipKeys.addAll(c.byTipologia.keys);
    }
    for (final c in perCommessa.values) {
      commKeys.addAll(c.byCommessa.keys);
    }
    final tipOrdinate = tipKeys.toList()
      ..sort(_confrontaVoceAlfanumerica);
    final tipConDati = tipOrdinate
        .where(
          (k) =>
              _matchCerca(k) &&
              giorni.any((g) => (perTipologia[g]!.byTipologia[k] ?? 0) > 0),
        )
        .toList();
    final commOrdinate = commKeys.toList()
      ..sort(_confrontaVoceAlfanumerica);
    final commConDati = commOrdinate
        .where(
          (k) =>
              _matchCerca(k) &&
              giorni.any((g) => (perCommessa[g]!.byCommessa[k] ?? 0) > 0),
        )
        .toList();

    final conAssegnatario =
        _mezziAnagrafica.where((m) => m.assegnatario.isNotEmpty).length;

    if (tipConDati.isEmpty && commConDati.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _cerca.isEmpty
                ? 'Nessun mezzo collegato alla dislocazione in forza '
                    'né assegnato in anagrafica '
                    '($conAssegnatario mezzi con assegnatario in anagrafica).'
                : 'Nessun mezzo corrisponde alla ricerca.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CronosAppThemes.warnFillOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300.withValues(
              alpha: CronosAppThemes.isDarkOf(context) ? 0.4 : 1,
            )),
          ),
          child: Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: Colors.blue.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Clicca un numero per vedere la lista · '
                  '${_mezziPerNominativo.length} dipendenti con mezzo · '
                  '$conAssegnatario mezzi assegnati in anagrafica',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('Mezzi per tipologia (totale)'),
        const SizedBox(height: 8),
        _matrixCard(
          rows: [
            for (final tip in tipConDati)
              _MatrixRow(
                label: tip,
                values: [
                  for (final g in giorni) perTipologia[g]!.byTipologia[tip] ?? 0,
                ],
                onDayTap: (dayIndex) {
                  if (dayIndex < 0 || dayIndex >= giorni.length) return;
                  final n = perTipologia[giorni[dayIndex]]!.byTipologia[tip] ?? 0;
                  if (n <= 0) return;
                  _mostraPopupListaMezzi(
                    giorno: giorni[dayIndex],
                    voce: tip,
                    tipologia: tip,
                  );
                },
              ),
            _MatrixRow(
              label: 'TOTALE MEZZI',
              values: [for (final g in giorni) perTipologia[g]!.totale],
              emphasize: true,
              bg: const Color(0xFFFFF59D),
              onDayTap: (dayIndex) {
                if (dayIndex < 0 || dayIndex >= giorni.length) return;
                if (perTipologia[giorni[dayIndex]]!.totale <= 0) return;
                _mostraPopupListaMezzi(
                  giorno: giorni[dayIndex],
                  voce: 'Tutti i mezzi',
                );
              },
            ),
          ].where((r) => r.emphasize || _matchCerca(r.label)).toList(),
          giorni: giorni,
        ),
        const SizedBox(height: 18),
        _sectionTitle('Mezzi per commessa'),
        const SizedBox(height: 8),
        if (commConDati.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nessuna commessa con mezzi nel periodo.'),
          )
        else
          _matrixCard(
            rows: [
              for (final c in commConDati)
                _MatrixRow(
                  label: c,
                  values: [
                    for (final g in giorni) perCommessa[g]!.byCommessa[c] ?? 0,
                  ],
                  onDayTap: (dayIndex) {
                    if (dayIndex < 0 || dayIndex >= giorni.length) return;
                    final n = perCommessa[giorni[dayIndex]]!.byCommessa[c] ?? 0;
                    if (n <= 0) return;
                    _mostraPopupListaMezzi(
                      giorno: giorni[dayIndex],
                      voce: c,
                      commessaLabel: c,
                      soloSuCommessa: true,
                    );
                  },
                ),
              _MatrixRow(
                label: 'TOTALE SU COMMESSA',
                values: [for (final g in giorni) perCommessa[g]!.totale],
                emphasize: true,
                bg: Colors.blue.shade100,
                onDayTap: (dayIndex) {
                  if (dayIndex < 0 || dayIndex >= giorni.length) return;
                  if (perCommessa[giorni[dayIndex]]!.totale <= 0) return;
                  _mostraPopupListaMezzi(
                    giorno: giorni[dayIndex],
                    voce: 'Mezzi su commessa',
                    soloSuCommessa: true,
                  );
                },
              ),
            ],
            giorni: giorni,
            maxBodyHeight: 420,
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Colors.blueGrey.shade900,
      ),
    );
  }

  Widget _matrixCard({
    required List<_MatrixRow> rows,
    required List<DateTime> giorni,
    double? maxBodyHeight,
  }) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _cerca.isEmpty ? 'Nessun dato.' : 'Nessuna voce corrisponde alla ricerca.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }
    final oggi = dateOnly(DateTime.now());
    final tableW = _labelW + giorni.length * _dayW + _dayW;
    final header = SizedBox(
      height: _rowH + 18,
      width: tableW,
      child: Row(
        children: [
          SizedBox(
            width: _labelW,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Voce',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ),
          for (final g in giorni)
            SizedBox(
              width: _dayW,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
                decoration: dateOnly(g) == oggi
                    ? BoxDecoration(
                        color: Colors.amber.shade200,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.shade800, width: 2),
                      )
                    : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _weekdayFmt.format(g).toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: dateOnly(g) == oggi
                            ? Colors.brown.shade900
                            : Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      _dateFmt.format(g),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        decoration: dateOnly(g) == oggi
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationThickness: 2,
                        color: dateOnly(g) == oggi
                            ? Colors.brown.shade900
                            : Colors.black87,
                      ),
                    ),
                    if (dateOnly(g) == oggi)
                      Text(
                        'OGGI',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.brown.shade800,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          SizedBox(
            width: _dayW,
            child: Center(
              child: Text(
                'Media',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey.shade800,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows) _buildMatrixRow(row, giorni, oggi),
      ],
    );
    if (maxBodyHeight != null) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxBodyHeight),
        child: SingleChildScrollView(child: body),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: CronosAppThemes.hairlineOf(context)),
        borderRadius: BorderRadius.circular(8),
        color: CronosAppThemes.cardOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ColoredBox(color: Colors.blueGrey.shade50, child: header),
                const Divider(height: 1),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatrixRow(_MatrixRow row, List<DateTime> giorni, DateTime oggi) {
    final dayCount = giorni.length;
    final somma = row.values.fold<int>(0, (a, b) => a + b);
    final media = dayCount == 0 ? 0.0 : somma / dayCount;
    final mediaTxt = media == media.roundToDouble()
        ? media.toInt().toString()
        : media.toStringAsFixed(1);

    return Container(
      height: row.showPct ? _rowH + 10 : _rowH,
      color: row.bg ?? (row.emphasize ? Colors.grey.shade100 : null),
      child: Row(
        children: [
          SizedBox(
            width: _labelW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    row.isStato
                        ? Icons.event_busy_outlined
                        : Icons.construction_outlined,
                    size: 16,
                    color: row.isStato ? Colors.red.shade700 : Colors.blue.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      row.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: row.emphasize ? 12 : 11,
                        fontWeight:
                            row.emphasize ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < row.values.length; i++)
            SizedBox(
              width: _dayW,
              child: Container(
                decoration: i < giorni.length && dateOnly(giorni[i]) == oggi
                    ? BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.35),
                        border: Border.symmetric(
                          vertical: BorderSide(
                            color: Colors.amber.shade800,
                            width: 2,
                          ),
                        ),
                      )
                    : null,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: row.onDayTap != null &&
                            row.values[i] > 0 &&
                            i < giorni.length
                        ? () => row.onDayTap!(i)
                        : null,
                    child: Center(
                      child: row.showPct &&
                              row.totaliGiorno != null &&
                              i < row.totaliGiorno!.length
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${row.values[i]}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: row.emphasize ? 14 : 13,
                                    color: row.onDayTap != null &&
                                            row.values[i] > 0
                                        ? Colors.blue.shade900
                                        : null,
                                    decoration: row.onDayTap != null &&
                                            row.values[i] > 0
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                                Text(
                                  _pct(row.values[i], row.totaliGiorno![i]),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              '${row.values[i]}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: row.emphasize ? 14 : 13,
                                color: row.values[i] == 0
                                    ? Colors.grey.shade400
                                    : (row.onDayTap != null
                                        ? Colors.blue.shade900
                                        : null),
                                decoration: row.onDayTap != null &&
                                        row.values[i] > 0
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: _dayW,
            child: Center(
              child: Text(
                mediaTxt,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.blueGrey.shade900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiornoConteggi {
  const _GiornoConteggi({
    required this.suCommessa,
    required this.suCantiere,
    required this.suSede,
    required this.nonAssegnati,
    required this.altreVoci,
    required this.totaleDipendenti,
    required this.byAttivita,
    required this.byVoce,
    required this.byAssenza,
  });

  final int suCommessa;
  final int suCantiere;
  final int suSede;
  final int nonAssegnati;
  final int altreVoci;
  final int totaleDipendenti;
  final Map<String, int> byAttivita;
  final Map<String, int> byVoce;
  final Map<String, int> byAssenza;

  int get totaleInForza => suCommessa + suCantiere + suSede;

  /// Ferie, malattia, corso, permesso, ecc. (+ altre voci fuori forza).
  int get totaleAssenti {
    var n = altreVoci;
    for (final v in byAssenza.values) {
      n += v;
    }
    return n;
  }
}

class _MatrixRow {
  const _MatrixRow({
    required this.label,
    required this.values,
    this.totaliGiorno,
    this.showPct = false,
    this.emphasize = false,
    this.bg,
    this.isStato = false,
    this.onDayTap,
  });

  final String label;
  final List<int> values;
  final List<int>? totaliGiorno;
  final bool showPct;
  final bool emphasize;
  final Color? bg;
  final bool isStato;
  final void Function(int dayIndex)? onDayTap;
}

enum _PersonaleFiltroTipo {
  suCommessa,
  suCantiere,
  suSede,
  inForza,
  assenza,
  assenti,
  altreVoci,
  nonAssegnati,
  tutti,
  attivita,
  voce,
}

class _PersonaleFiltro {
  const _PersonaleFiltro(this.tipo, [this.key]);
  final _PersonaleFiltroTipo tipo;
  final String? key;
}

class _PersonaleDettaglioRiga {
  const _PersonaleDettaglioRiga({
    required this.nominativo,
    required this.assegnazione,
    required this.attivita,
  });

  final String nominativo;
  final String assegnazione;
  final String attivita;
}

class _MezzoAnagrafica {
  const _MezzoAnagrafica({
    required this.id,
    required this.targa,
    required this.marca,
    required this.modello,
    required this.tipologia,
    required this.assegnatario,
    this.numerazione,
  });

  final String id;
  final int? numerazione;
  final String targa;
  final String marca;
  final String modello;
  final String tipologia;
  final String assegnatario;
}

class _MezzoDettaglioRiga {
  const _MezzoDettaglioRiga({
    required this.nominativo,
    required this.commessaLabel,
    required this.mezzo,
    required this.tipologia,
  });

  final String nominativo;
  final String commessaLabel;
  final _MezzoAnagrafica mezzo;
  final String tipologia;
}

class _MezziGiornoConteggi {
  const _MezziGiornoConteggi({
    required this.totale,
    required this.byCommessa,
    required this.byTipologia,
  });

  final int totale;
  final Map<String, int> byCommessa;
  final Map<String, int> byTipologia;
}
