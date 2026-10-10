import 'dart:async';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/uqsa_attestati_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

enum _AttestatiFilter { all, rfi, l81, expired, expiring }

class AdminUqsaAttestatiPage extends StatefulWidget {
  const AdminUqsaAttestatiPage({
    super.key,
    this.role,
    this.readOnly = false,
  });

  final String? role;
  final bool readOnly;

  @override
  State<AdminUqsaAttestatiPage> createState() => _AdminUqsaAttestatiPageState();
}

class _AdminUqsaAttestatiPageState extends State<AdminUqsaAttestatiPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  String _search = '';
  _AttestatiFilter _filter = _AttestatiFilter.all;
  bool _onlyActive = true;
  String? _selectedPersonaleId;
  String? _corsiForPersonId;
  int _corsiLoadSeq = 0;
  bool _loadingCorsiPerson = false;
  List<UqsaCorsoFormazione> _corsiRfi = const [];
  List<UqsaCorsoFormazione> _corsiL81 = const [];

  List<Map<String, dynamic>> _people = const [];
  List<UqsaAttestato> _files = const [];

  bool get _canEdit {
    if (widget.readOnly) return false;
    final role = (widget.role ?? currentSessionRole() ?? '').trim();
    if (role.isEmpty) return !isCurrentUserAdminVista;
    return canManageUqsaAttestati(role);
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _search = _searchCtrl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await UqsaAttestatiService.loadPersonale();
      final files = await UqsaAttestatiService.loadAll();
      if (!mounted) return;
      setState(() {
        _people = people;
        _files = files;
        _loading = false;
        if (_selectedPersonaleId != null &&
            people.every((p) => _pid(p) != _selectedPersonaleId)) {
          _selectedPersonaleId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _pid(Map<String, dynamic> p) => (p['id_uuid'] ?? '').toString().trim();

  String _pname(Map<String, dynamic> p) =>
      (p['full_name'] ?? '').toString().trim();

  String _pmat(Map<String, dynamic> p) =>
      (p['matricola'] ?? '').toString().trim();

  bool _isActive(Map<String, dynamic> p) {
    final v = p['active'];
    if (v is bool) return v;
    final s = (v ?? '').toString().toLowerCase();
    if (s.isEmpty) return true;
    return s == 'true' || s == '1' || s == 't';
  }

  List<UqsaAttestato> _filesOf(String personaleId, {String? tipo}) {
    return _files
        .where((f) =>
            f.personaleId == personaleId && (tipo == null || f.tipo == tipo))
        .toList();
  }

  DateTime get _today {
    final n = italyNow();
    return DateTime(n.year, n.month, n.day);
  }

  bool _isExpired(UqsaAttestato f) {
    final d = f.dataScadenza;
    if (d == null) return false;
    return d.isBefore(_today);
  }

  bool _isExpiring(UqsaAttestato f) {
    final d = f.dataScadenza;
    if (d == null || _isExpired(f)) return false;
    return !d.isAfter(_today.add(const Duration(days: 30)));
  }

  /// Scaduti/in-scadenza in elenco: solo il tipo visibile (RFI o 81/08).
  Iterable<UqsaAttestato> _filesForListStatus(String id) {
    final files = _filesOf(id);
    switch (_filter) {
      case _AttestatiFilter.rfi:
        return files.where((f) => f.isRfi);
      case _AttestatiFilter.l81:
        return files.where((f) => f.isL81);
      case _AttestatiFilter.all:
      case _AttestatiFilter.expired:
      case _AttestatiFilter.expiring:
        return files;
    }
  }

  Color _scadenzaColor(UqsaAttestato f) {
    if (f.dataScadenza == null) return const Color(0xFF546E7A);
    if (_isExpired(f)) return const Color(0xFFC62828);
    if (_isExpiring(f)) return const Color(0xFFE65100);
    return const Color(0xFF2E7D32);
  }

  bool _personMatchesFilter(Map<String, dynamic> p) {
    final id = _pid(p);
    final files = _filesOf(id);
    switch (_filter) {
      case _AttestatiFilter.all:
        return true;
      case _AttestatiFilter.rfi:
        return files.any((f) => f.isRfi);
      case _AttestatiFilter.l81:
        return files.any((f) => f.isL81);
      case _AttestatiFilter.expired:
        return files.any(_isExpired);
      case _AttestatiFilter.expiring:
        return files.any(_isExpiring);
    }
  }

  List<Map<String, dynamic>> get _filteredPeople {
    final q = _search;
    final out = _people.where((p) {
      if (_onlyActive && !_isActive(p)) return false;
      if (!_personMatchesFilter(p)) return false;
      if (q.isEmpty) return true;
      return _pname(p).toLowerCase().contains(q) ||
          _pmat(p).toLowerCase().contains(q);
    }).toList();
    out.sort((a, b) {
      final an = _pname(a).toLowerCase();
      final bn = _pname(b).toLowerCase();
      return an.compareTo(bn);
    });
    return out;
  }

  Map<String, dynamic>? get _selectedPerson {
    if (_selectedPersonaleId == null) return null;
    for (final p in _people) {
      if (_pid(p) == _selectedPersonaleId) return p;
    }
    return null;
  }

  Future<bool> _guardWrite() async {
    if (!_canEdit) {
      ModifyFeedback.hint(context, 'Non hai i permessi per modificare gli attestati.');
      return false;
    }
    return ensureCanPersist(context, widget.role);
  }

  String _normCorso(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_./\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  bool _haFileCorso(String nome, List<UqsaAttestato> files) {
    final n = _normCorso(nome);
    return files.any((f) => _normCorso(f.titolo) == n);
  }

  List<UqsaAttestato> _filesOfCorso(String nome, List<UqsaAttestato> files) {
    final n = _normCorso(nome);
    return files.where((f) => _normCorso(f.titolo) == n).toList();
  }

  void _selectPerson(String? id) {
    setState(() => _selectedPersonaleId = id);
    if (id == null) return;
    Map<String, dynamic>? person;
    for (final p in _people) {
      if (_pid(p) == id) {
        person = p;
        break;
      }
    }
    if (person != null) unawaited(_loadCorsiPerson(person));
  }

  Future<void> _loadCorsiPerson(Map<String, dynamic> person) async {
    final id = _pid(person);
    if (id.isEmpty) return;
    final seq = ++_corsiLoadSeq;
    setState(() {
      _corsiForPersonId = id;
      _loadingCorsiPerson = true;
      _corsiRfi = const [];
      _corsiL81 = const [];
    });
    try {
      final personaleId = int.tryParse((person['id'] ?? '').toString());
      final results = await Future.wait([
        UqsaAttestatiService.loadCorsiAssegnati(
          tipo: kUqsaAttestatoTipoRfi,
          personaleUuid: id,
          personaleId: personaleId,
        ),
        UqsaAttestatiService.loadCorsiAssegnati(
          tipo: kUqsaAttestatoTipoL81,
          personaleUuid: id,
          personaleId: personaleId,
        ),
      ]);
      if (!mounted || seq != _corsiLoadSeq) return;
      setState(() {
        _corsiRfi = results[0];
        _corsiL81 = results[1];
        _loadingCorsiPerson = false;
      });
    } catch (_) {
      if (!mounted || seq != _corsiLoadSeq) return;
      setState(() {
        _corsiRfi = const [];
        _corsiL81 = const [];
        _loadingCorsiPerson = false;
      });
    }
  }

  Future<void> _openUpload({
    String? tipo,
    UqsaCorsoFormazione? corso,
  }) async {
    final person = _selectedPerson;
    if (person == null) {
      ModifyFeedback.hint(context, 'Seleziona un dipendente');
      return;
    }
    if (!await _guardWrite()) return;
    if (!mounted) return;
    final initialTipo = tipo ??
        (_filter == _AttestatiFilter.l81
            ? kUqsaAttestatoTipoL81
            : kUqsaAttestatoTipoRfi);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadAttestatoDialog(
        dipendenteNome: _pname(person),
        personaleUuid: _pid(person),
        personaleId: int.tryParse((person['id'] ?? '').toString()),
        initialTipo: initialTipo,
        initialCorso: corso,
        onSubmit: (tipoSel, titolo, scadenza, name, mime, bytes) {
          return UqsaAttestatiService.upload(
            personaleId: _pid(person),
            tipo: tipoSel,
            titolo: titolo,
            dataScadenza: scadenza,
            originalFileName: name,
            mimeType: mime,
            bytes: bytes,
          );
        },
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _editMeta(UqsaAttestato row) async {
    if (!await _guardWrite()) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _EditAttestatoDialog(
        row: row,
        personaleId: int.tryParse(
          (_selectedPerson?['id'] ?? '').toString(),
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _delete(UqsaAttestato row) async {
    if (!await _guardWrite()) return;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina attestato'),
        content: Text('Eliminare «${row.titolo}»? Il file verrà rimosso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await UqsaAttestatiService.delete(row);
      if (!mounted) return;
      ModifyFeedback.success(context, 'Attestato eliminato');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Eliminazione non riuscita: $e');
    }
  }

  Future<void> _view(UqsaAttestato row) async {
    try {
      if (row.isImage) {
        final bytes = await UqsaAttestatiService.downloadBytes(row);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
              child: Column(
                children: [
                  ListTile(
                    title: Text(row.titolo),
                    subtitle: Text(row.fileName),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: InteractiveViewer(
                      child: Center(child: Image.memory(bytes)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }
      final url = await UqsaAttestatiService.signedUrl(row);
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_blank' : null,
      );
      if (!launched && mounted) {
        ModifyFeedback.error(context, 'Impossibile aprire il file');
      }
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Apertura non riuscita: $e');
    }
  }

  Future<void> _download(UqsaAttestato row) async {
    try {
      final bytes = await UqsaAttestatiService.downloadBytes(row);
      final name = row.fileName;
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 && dot < name.length - 1
          ? name.substring(dot + 1)
          : (row.isPdf ? 'pdf' : 'bin');
      final base = dot >= 0 ? name.substring(0, dot) : name;
      await FileSaver.instance.saveFile(
        name: base.isEmpty ? row.titolo : base,
        bytes: bytes,
        ext: ext,
        mimeType: row.isPdf
            ? MimeType.pdf
            : (ext == 'png'
                ? MimeType.png
                : (ext == 'jpg' || ext == 'jpeg' ? MimeType.jpeg : MimeType.other)),
      );
      if (!mounted) return;
      ModifyFeedback.success(context, 'Download avviato');
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, 'Download non riuscito: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = useMobileUi(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(
            title: 'Formazione — Attestati',
          ),
          actions: [
            if (_canEdit && !compact)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _selectedPersonaleId == null ? null : _openUpload,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Carica'),
                ),
              ),
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      floatingActionButton: (_canEdit && compact && _selectedPersonaleId != null)
          ? FloatingActionButton.extended(
              onPressed: _openUpload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Carica'),
            )
          : null,
      body: PageWithTopLogo(
        showLogo: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Errore: $_error',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Riprova'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _toolbar(),
                      const Divider(height: 1),
                      Expanded(
                        child: compact ? _mobileBody() : _desktopBody(),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Cerca dipendente o matricola',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => _searchCtrl.clear(),
                      icon: const Icon(Icons.clear),
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Tutti'),
                selected: _filter == _AttestatiFilter.all,
                onSelected: (_) => setState(() => _filter = _AttestatiFilter.all),
              ),
              FilterChip(
                label: const Text('RFI'),
                selected: _filter == _AttestatiFilter.rfi,
                onSelected: (_) => setState(() => _filter = _AttestatiFilter.rfi),
              ),
              FilterChip(
                label: const Text('D.Lgs. 81/08'),
                selected: _filter == _AttestatiFilter.l81,
                onSelected: (_) => setState(() => _filter = _AttestatiFilter.l81),
              ),
              FilterChip(
                label: const Text('Scaduti'),
                selected: _filter == _AttestatiFilter.expired,
                onSelected: (_) =>
                    setState(() => _filter = _AttestatiFilter.expired),
              ),
              FilterChip(
                label: const Text('In scadenza ≤30gg'),
                selected: _filter == _AttestatiFilter.expiring,
                onSelected: (_) =>
                    setState(() => _filter = _AttestatiFilter.expiring),
              ),
              FilterChip(
                label: const Text('Solo attivi'),
                selected: _onlyActive,
                onSelected: (v) => setState(() => _onlyActive = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopBody() {
    final people = _filteredPeople;
    return Row(
      children: [
        SizedBox(
          width: 340,
          child: _peopleList(people),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _detailPane()),
      ],
    );
  }

  Widget _mobileBody() {
    if (_selectedPersonaleId != null) {
      return Column(
        children: [
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: Text(_pname(_selectedPerson ?? const {})),
            subtitle: const Text('Torna all\'elenco'),
            onTap: () => _selectPerson(null),
          ),
          const Divider(height: 1),
          Expanded(child: _detailPane()),
        ],
      );
    }
    return _peopleList(_filteredPeople);
  }

  Widget _peopleList(List<Map<String, dynamic>> people) {
    if (people.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nessun dipendente trovato'),
        ),
      );
    }
    return ListView.separated(
      itemCount: people.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = people[i];
        final id = _pid(p);
        final files = _filesOf(id);
        final rfi = files.where((f) => f.isRfi).length;
        final l81 = files.where((f) => f.isL81).length;
        final expired = _filesForListStatus(id).where(_isExpired).length;
        final selected = id == _selectedPersonaleId;
        final mat = _pmat(p);
        return ListTile(
          selected: selected,
          selectedTileColor: const Color(0xFFE3F2FD),
          leading: CircleAvatar(
            backgroundColor: expired > 0
                ? const Color(0xFFC62828)
                : (files.isEmpty ? Colors.blueGrey : const Color(0xFF1565C0)),
            foregroundColor: Colors.white,
            child: Text(
              _initials(_pname(p)),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          title: Text(
            _pname(p),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (mat.isNotEmpty) 'Matr. $mat',
              'RFI $rfi · 81/08 $l81',
              if (expired > 0) '$expired scaduti',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _selectPerson(id),
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Widget _detailPane() {
    final person = _selectedPerson;
    if (person == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Seleziona un dipendente per vedere e caricare gli attestati RFI e D.Lgs. 81/08.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final id = _pid(person);
    if (_corsiForPersonId != id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = _selectedPerson;
        if (current != null && _pid(current) == id) {
          unawaited(_loadCorsiPerson(current));
        }
      });
    }
    final rfiAll = _filesOf(id, tipo: kUqsaAttestatoTipoRfi);
    final l81All = _filesOf(id, tipo: kUqsaAttestatoTipoL81);
    var rfi = rfiAll;
    var l81 = l81All;
    final showRfi = _filter != _AttestatiFilter.l81;
    final showL81 = _filter != _AttestatiFilter.rfi;
    if (_filter == _AttestatiFilter.expired) {
      rfi = rfiAll.where(_isExpired).toList();
      l81 = l81All.where(_isExpired).toList();
    } else if (_filter == _AttestatiFilter.expiring) {
      rfi = rfiAll.where(_isExpiring).toList();
      l81 = l81All.where(_isExpiring).toList();
    }
    final showChecklist = _filter == _AttestatiFilter.all ||
        _filter == _AttestatiFilter.rfi ||
        _filter == _AttestatiFilter.l81;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        Text(
          _pname(person),
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (_pmat(person).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              'Matricola ${_pmat(person)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blueGrey.shade700,
                  ),
            ),
          )
        else
          const SizedBox(height: 8),
        if (showChecklist)
          _riepilogoCorsiBanner(
            showRfi: showRfi,
            showL81: showL81,
            rfiFiles: rfiAll,
            l81Files: l81All,
          ),
        const SizedBox(height: 12),
        if (showRfi &&
            (_filter == _AttestatiFilter.all ||
                _filter == _AttestatiFilter.rfi ||
                rfi.isNotEmpty ||
                (showChecklist && _corsiRfi.isNotEmpty))) ...[
          _section(
            title: 'Attestati RFI',
            color: const Color(0xFF1A237E),
            tipo: kUqsaAttestatoTipoRfi,
            files: rfi,
            filesForMatch: rfiAll,
            corsi: showChecklist ? _corsiRfi : const [],
            loadingCorsi: showChecklist && _loadingCorsiPerson,
          ),
          if (showL81) const SizedBox(height: 16),
        ],
        if (showL81 &&
            (_filter == _AttestatiFilter.all ||
                _filter == _AttestatiFilter.l81 ||
                l81.isNotEmpty ||
                (showChecklist && _corsiL81.isNotEmpty)))
          _section(
            title: 'Attestati D.Lgs. 81/08',
            color: const Color(0xFF004D40),
            tipo: kUqsaAttestatoTipoL81,
            files: l81,
            filesForMatch: l81All,
            corsi: showChecklist ? _corsiL81 : const [],
            loadingCorsi: showChecklist && _loadingCorsiPerson,
          ),
      ],
    );
  }

  Widget _riepilogoCorsiBanner({
    required bool showRfi,
    required bool showL81,
    required List<UqsaAttestato> rfiFiles,
    required List<UqsaAttestato> l81Files,
  }) {
    if (_loadingCorsiPerson && _corsiForPersonId == _selectedPersonaleId) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final corsiRfi = showRfi ? _corsiRfi : const <UqsaCorsoFormazione>[];
    final corsiL81 = showL81 ? _corsiL81 : const <UqsaCorsoFormazione>[];
    final tot = corsiRfi.length + corsiL81.length;
    int mancantiDi(List<UqsaCorsoFormazione> corsi, List<UqsaAttestato> files) =>
        corsi.where((c) => !_haFileCorso(c.nome, files)).length;
    final mancanti = mancantiDi(corsiRfi, rfiFiles) + mancantiDi(corsiL81, l81Files);
    final caricati = tot - mancanti;
    final parts = <String>[];
    if (showRfi && showL81) {
      parts.add('${corsiRfi.length} corsi RFI');
      parts.add('${corsiL81.length} corsi 81/08');
    } else if (showRfi) {
      parts.add('${corsiRfi.length} corsi RFI da Formazione');
    } else {
      parts.add('${corsiL81.length} corsi 81/08 da Formazione');
    }
    final hint = tot == 0
        ? 'Nessun corso in Formazione per questo dipendente. Puoi comunque caricare un file.'
        : mancanti == 0
            ? 'Documenti completi: $caricati/$tot corsi hanno già l\'attestato.'
            : 'Suggerimento: mancano $mancanti documenti su $tot corsi ($caricati già caricati).';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: mancanti > 0
            ? const Color(0xFFFFF8E1)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: mancanti > 0
              ? const Color(0xFFFFCC80)
              : const Color(0xFFA5D6A7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Riepilogo da Formazione · ${parts.join(' · ')}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(color: Colors.blueGrey.shade800)),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required Color color,
    required String tipo,
    required List<UqsaAttestato> files,
    List<UqsaCorsoFormazione> corsi = const [],
    List<UqsaAttestato>? filesForMatch,
    bool loadingCorsi = false,
  }) {
    final matchFiles = filesForMatch ?? files;
    final matchedIds = <String>{};
    final corsiRows = <Widget>[];
    var mancanti = 0;
    var coperti = 0;
    for (final corso in corsi) {
      final linked = _filesOfCorso(corso.nome, matchFiles);
      for (final f in linked) {
        matchedIds.add(f.id);
      }
      final shown = linked.where((f) => files.any((x) => x.id == f.id)).toList();
      if (linked.isEmpty) {
        mancanti++;
        corsiRows.add(_corsoDaCaricareTile(corso, tipo, color));
      } else {
        coperti++;
        corsiRows.add(_corsoHeader(corso, color, ok: true));
        if (shown.isEmpty) {
          corsiRows.add(
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 8),
              child: Text(
                'File già caricato (non in questo filtro)',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
              ),
            ),
          );
        } else {
          corsiRows.addAll(shown.map(_fileTile));
        }
      }
    }
    final extra = files.where((f) => !matchedIds.contains(f.id)).toList();
    final countLabel = corsi.isEmpty
        ? '${files.length}'
        : '$coperti/${corsi.length}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(countLabel),
                if (_canEdit) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _openUpload(tipo: tipo),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Carica'),
                  ),
                ],
              ],
            ),
            if (corsi.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  mancanti == 0
                      ? 'Tutti i corsi di Formazione hanno un documento'
                      : 'Da caricare ancora: $mancanti',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: mancanti == 0
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFE65100),
                  ),
                ),
              ),
            if (loadingCorsi && corsi.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (corsiRows.isEmpty && extra.isEmpty && files.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Nessun corso in Formazione e nessun file caricato',
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
              )
            else ...[
              ...corsiRows,
              if (extra.isNotEmpty) ...[
                if (corsiRows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Altri file (non in Formazione)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  ),
                ...extra.map(_fileTile),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _corsoHeader(
    UqsaCorsoFormazione corso,
    Color color, {
    required bool ok,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: ok ? const Color(0xFF2E7D32) : color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              corso.nome,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (corso.scadenzaDipendente != null)
            Text(
              'scad. ${formatDateDdMmYyyyFromDate(corso.scadenzaDipendente!)}',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
            ),
        ],
      ),
    );
  }

  Widget _corsoDaCaricareTile(
    UqsaCorsoFormazione corso,
    String tipo,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            children: [
              Icon(Icons.upload_file_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      corso.nome,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      corso.scadenzaDipendente == null
                          ? 'Da caricare · corso in Formazione'
                          : 'Da caricare · scad. ${formatDateDdMmYyyyFromDate(corso.scadenzaDipendente!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              if (_canEdit)
                TextButton(
                  onPressed: () => _openUpload(tipo: tipo, corso: corso),
                  child: const Text('Carica'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileTile(UqsaAttestato row) {
    final scadColor = _scadenzaColor(row);
    final scadText = row.dataScadenza == null
        ? 'Scadenza non impostata'
        : 'Scadenza ${formatDateDdMmYyyyFromDate(row.dataScadenza!)}';
    final uploadText =
        'Caricato ${formatDateTimeItFromSupabase(row.uploadedAt)}';
    final compact = useMobileUi(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                row.isPdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                color: row.isPdf ? Colors.red.shade700 : Colors.teal.shade700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.titolo,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.fileName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(uploadText, style: const TextStyle(fontSize: 12)),
                    Text(
                      scadText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scadColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (compact)
                PopupMenuButton<String>(
                  tooltip: 'Azioni',
                  onSelected: (v) {
                    switch (v) {
                      case 'view':
                        _view(row);
                      case 'download':
                        _download(row);
                      case 'edit':
                        _editMeta(row);
                      case 'delete':
                        _delete(row);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'view',
                      child: Text('Apri / vedi'),
                    ),
                    const PopupMenuItem(
                      value: 'download',
                      child: Text('Scarica'),
                    ),
                    if (_canEdit)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Modifica titolo/scadenza'),
                      ),
                    if (_canEdit)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Elimina'),
                      ),
                  ],
                )
              else ...[
                IconButton(
                  tooltip: 'Apri',
                  onPressed: () => _view(row),
                  icon: const Icon(Icons.visibility_outlined),
                ),
                IconButton(
                  tooltip: 'Scarica',
                  onPressed: () => _download(row),
                  icon: const Icon(Icons.download_outlined),
                ),
                if (_canEdit)
                  IconButton(
                    tooltip: 'Modifica titolo/scadenza',
                    onPressed: () => _editMeta(row),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (_canEdit)
                  IconButton(
                    tooltip: 'Elimina',
                    onPressed: () => _delete(row),
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade700,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _attestatoUploadError(Object e) {
  final raw = e.toString();
  if (e is StateError && e.message.trim().isNotEmpty) {
    return e.message;
  }
  if (raw.contains('InvalidKey') || raw.contains('Invalid key')) {
    return 'Caricamento non riuscito: il nome del file contiene spazi o caratteri '
        'non ammessi da Storage. Riprova: verrà rinominato automaticamente.';
  }
  return 'Caricamento non riuscito: $e';
}

class _UploadAttestatoDialog extends StatefulWidget {
  const _UploadAttestatoDialog({
    required this.dipendenteNome,
    required this.personaleUuid,
    required this.initialTipo,
    required this.onSubmit,
    this.personaleId,
    this.initialCorso,
  });

  final String dipendenteNome;
  final String personaleUuid;
  final int? personaleId;
  final String initialTipo;
  final UqsaCorsoFormazione? initialCorso;
  final Future<void> Function(
    String tipo,
    String titolo,
    DateTime? scadenza,
    String fileName,
    String? mime,
    Uint8List bytes,
  ) onSubmit;

  @override
  State<_UploadAttestatoDialog> createState() => _UploadAttestatoDialogState();
}

class _UploadAttestatoDialogState extends State<_UploadAttestatoDialog> {
  late String _tipo;
  UqsaCorsoFormazione? _corso;
  List<UqsaCorsoFormazione> _corsi = const [];
  bool _loadingCorsi = true;
  DateTime? _scadenza;
  String? _fileName;
  String? _mime;
  Uint8List? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tipo = widget.initialTipo;
    _loadCorsi();
  }

  Future<void> _loadCorsi() async {
    setState(() {
      _loadingCorsi = true;
      _corso = null;
    });
    try {
      final list = List<UqsaCorsoFormazione>.from(
        await UqsaAttestatiService.loadCorsiFormazione(
          tipo: _tipo,
          personaleUuid: widget.personaleUuid,
          personaleId: widget.personaleId,
        ),
      );
      if (!mounted) return;
      var selected = widget.initialCorso;
      if (selected != null && _tipo == widget.initialTipo) {
        UqsaCorsoFormazione? match;
        for (final c in list) {
          if (c.nome.trim().toLowerCase() ==
              selected.nome.trim().toLowerCase()) {
            match = c;
            break;
          }
        }
        if (match != null) {
          selected = match;
        } else {
          list.insert(0, selected);
        }
      } else {
        selected = null;
      }
      setState(() {
        _corsi = list;
        _corso = selected;
        if (selected?.scadenzaDipendente != null) {
          _scadenza = selected!.scadenzaDipendente;
        }
        _loadingCorsi = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _corsi = const [];
        _loadingCorsi = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Corsi formazione: $e')),
      );
    }
  }

  Future<void> _onTipoChanged(String tipo) async {
    setState(() => _tipo = tipo);
    await _loadCorsi();
  }

  void _onCorsoSelected(UqsaCorsoFormazione? corso) {
    setState(() {
      _corso = corso;
      if (corso?.scadenzaDipendente != null) {
        _scadenza = corso!.scadenzaDipendente;
      }
    });
  }

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Attestati',
          extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    if (!UqsaAttestatiService.isAllowedFileName(file.name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato non supportato. Usa PDF, JPG, PNG o WEBP.'),
        ),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > UqsaAttestatiService.maxFileBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il file supera i 20 MB')),
      );
      return;
    }
    setState(() {
      _fileName = file.name;
      _mime = file.mimeType;
      _bytes = bytes;
    });
  }

  Future<void> _pickScadenza() async {
    final now = italyNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scadenza ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    setState(() => _scadenza = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    if (_bytes == null || _fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un file')),
      );
      return;
    }
    final corso = (_corso?.nome ?? '').trim();
    if (corso.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona o inserisci il corso')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        _tipo,
        corso,
        _scadenza,
        _fileName!,
        _mime,
        _bytes!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_attestatoUploadError(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Carica attestato · ${widget.dipendenteNome}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: kUqsaAttestatoTipoRfi,
                  label: Text('RFI'),
                  icon: Icon(Icons.account_tree_outlined, size: 16),
                ),
                ButtonSegment(
                  value: kUqsaAttestatoTipoL81,
                  label: Text('D.Lgs. 81/08'),
                  icon: Icon(Icons.school_outlined, size: 16),
                ),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => _onTipoChanged(s.first),
            ),
            const SizedBox(height: 12),
            _CorsoFormazioneDropdown(
              tipo: _tipo,
              corsi: _corsi,
              selected: _corso,
              loading: _loadingCorsi,
              enabled: !_busy,
              onChanged: _onCorsoSelected,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickScadenza,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _scadenza == null
                    ? 'Data scadenza (facoltativa)'
                    : 'Scadenza ${formatDateDdMmYyyyFromDate(_scadenza!)}',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_fileName ?? 'Seleziona PDF o immagine'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Carica'),
        ),
      ],
    );
  }
}

class _EditAttestatoDialog extends StatefulWidget {
  const _EditAttestatoDialog({required this.row, this.personaleId});

  final UqsaAttestato row;
  final int? personaleId;

  @override
  State<_EditAttestatoDialog> createState() => _EditAttestatoDialogState();
}

class _EditAttestatoDialogState extends State<_EditAttestatoDialog> {
  UqsaCorsoFormazione? _corso;
  List<UqsaCorsoFormazione> _corsi = const [];
  bool _loadingCorsi = true;
  DateTime? _scadenza;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scadenza = widget.row.dataScadenza;
    _loadCorsi();
  }

  Future<void> _loadCorsi() async {
    setState(() => _loadingCorsi = true);
    try {
      final list = await UqsaAttestatiService.loadCorsiFormazione(
        tipo: widget.row.tipo,
        personaleUuid: widget.row.personaleId,
        personaleId: widget.personaleId,
      );
      final currentName = widget.row.titolo.trim();
      var selected = list.cast<UqsaCorsoFormazione?>().firstWhere(
            (c) => (c?.nome ?? '') == currentName,
            orElse: () => null,
          );
      if (selected == null && currentName.isNotEmpty) {
        selected = UqsaCorsoFormazione(nome: currentName, delDipendente: true);
        list.insert(0, selected);
      }
      if (!mounted) return;
      setState(() {
        _corsi = list;
        _corso = selected;
        _loadingCorsi = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _corsi = widget.row.titolo.trim().isEmpty
            ? const []
            : [UqsaCorsoFormazione(nome: widget.row.titolo.trim())];
        _corso = _corsi.isEmpty ? null : _corsi.first;
        _loadingCorsi = false;
      });
    }
  }

  Future<void> _pickScadenza() async {
    final now = italyNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scadenza ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    setState(() => _scadenza = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    final corso = (_corso?.nome ?? '').trim();
    if (corso.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona o inserisci il corso')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await UqsaAttestatiService.updateMeta(
        id: widget.row.id,
        titolo: corso,
        dataScadenza: _scadenza,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Salvataggio non riuscito: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifica attestato'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CorsoFormazioneDropdown(
              tipo: widget.row.tipo,
              corsi: _corsi,
              selected: _corso,
              loading: _loadingCorsi,
              enabled: !_busy,
              onChanged: (v) => setState(() {
                _corso = v;
                if (v?.scadenzaDipendente != null && _scadenza == null) {
                  _scadenza = v!.scadenzaDipendente;
                }
              }),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickScadenza,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _scadenza == null
                    ? 'Data scadenza (facoltativa)'
                    : 'Scadenza ${formatDateDdMmYyyyFromDate(_scadenza!)}',
              ),
            ),
            if (_scadenza != null)
              TextButton(
                onPressed: () => setState(() => _scadenza = null),
                child: const Text('Rimuovi scadenza'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Salva'),
        ),
      ],
    );
  }
}

class _CorsoFormazioneDropdown extends StatefulWidget {
  const _CorsoFormazioneDropdown({
    required this.tipo,
    required this.corsi,
    required this.selected,
    required this.loading,
    required this.onChanged,
    this.enabled = true,
  });

  final String tipo;
  final List<UqsaCorsoFormazione> corsi;
  final UqsaCorsoFormazione? selected;
  final bool loading;
  final bool enabled;
  final ValueChanged<UqsaCorsoFormazione?> onChanged;

  @override
  State<_CorsoFormazioneDropdown> createState() =>
      _CorsoFormazioneDropdownState();
}

class _CorsoFormazioneDropdownState extends State<_CorsoFormazioneDropdown> {
  final GlobalKey<DropdownSearchState<UqsaCorsoFormazione>> _ddKey =
      GlobalKey<DropdownSearchState<UqsaCorsoFormazione>>();
  final List<UqsaCorsoFormazione> _manuali = [];

  @override
  void didUpdateWidget(covariant _CorsoFormazioneDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tipo != widget.tipo) {
      _manuali.clear();
    }
  }

  bool _stessoNome(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _inElenco(String nome) =>
      widget.corsi.any((c) => _stessoNome(c.nome, nome));

  List<UqsaCorsoFormazione> get _items {
    final seen = <String>{};
    final out = <UqsaCorsoFormazione>[];
    void add(UqsaCorsoFormazione c) {
      final k = c.nome.trim().toLowerCase();
      if (k.isEmpty || !seen.add(k)) return;
      out.add(c);
    }

    for (final c in _manuali) {
      add(c);
    }
    for (final c in widget.corsi) {
      add(c);
    }
    final sel = widget.selected;
    if (sel != null) add(sel);
    return out;
  }

  void _applyManuale(String raw) {
    final nome = raw.trim();
    if (nome.isEmpty) return;
    _ddKey.currentState?.closeDropDownSearch();
    UqsaCorsoFormazione? existing;
    for (final c in widget.corsi) {
      if (_stessoNome(c.nome, nome)) {
        existing = c;
        break;
      }
    }
    final corso = existing ?? UqsaCorsoFormazione(nome: nome);
    if (existing == null &&
        !_manuali.any((c) => _stessoNome(c.nome, nome))) {
      _manuali.insert(0, corso);
    }
    widget.onChanged(corso);
    setState(() {});
  }

  Future<void> _inserisciManuale({String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Corso non in elenco'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nome corso',
            hintText: 'Scrivi il nome del corso',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Usa'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (nome == null || nome.trim().isEmpty) return;
    _applyManuale(nome);
  }

  @override
  Widget build(BuildContext context) {
    final isRfi = widget.tipo == kUqsaAttestatoTipoRfi;
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownSearch<UqsaCorsoFormazione>(
          key: _ddKey,
          enabled: widget.enabled,
          items: _items,
          selectedItem: widget.selected,
          itemAsString: (c) => c.nome,
          compareFn: (a, b) => _stessoNome(a.nome, b.nome),
          onChanged: widget.onChanged,
          popupProps: PopupProps.menu(
            showSearchBox: true,
            searchDelay: Duration.zero,
            searchFieldProps: const TextFieldProps(
              decoration: InputDecoration(
                hintText: 'Cerca o scrivi un corso nuovo',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            emptyBuilder: (ctx, search) {
              final q = search.trim();
              if (q.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nessun corso in elenco. Inseriscine uno con il pulsante sotto.',
                  ),
                );
              }
              return ListTile(
                dense: true,
                leading: const Icon(Icons.add),
                title: Text('Usa «$q»'),
                subtitle: const Text('Corso non in elenco'),
                onTap: () => _applyManuale(q),
              );
            },
            itemBuilder: (ctx, item, isSelected) {
              final manuale = !_inElenco(item.nome);
              return ListTile(
                dense: true,
                selected: isSelected,
                leading: manuale ? const Icon(Icons.edit_outlined, size: 18) : null,
                title: Text(item.nome),
                subtitle: manuale
                    ? const Text('Inserimento manuale')
                    : (item.delDipendente
                        ? Text(
                            item.scadenzaDipendente == null
                                ? 'Già in formazione di questo dipendente'
                                : 'In formazione · scad. ${formatDateDdMmYyyyFromDate(item.scadenzaDipendente!)}',
                          )
                        : null),
              );
            },
          ),
          dropdownDecoratorProps: DropDownDecoratorProps(
            dropdownSearchDecoration: InputDecoration(
              labelText: isRfi ? 'Corso RFI' : 'Corso D.Lgs. 81/08',
              hintText: 'Seleziona o inserisci il corso',
              border: const OutlineInputBorder(),
              helperText: widget.corsi.isEmpty
                  ? 'Nessun corso in anagrafica: inseriscilo a mano'
                  : 'Elenco da Formazione ${isRfi ? 'RFI' : 'D.Lgs. 81/08'} · puoi anche inserirlo a mano',
              helperMaxLines: 2,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.enabled ? () => _inserisciManuale() : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Inserisci corso non in elenco'),
          ),
        ),
      ],
    );
  }
}
