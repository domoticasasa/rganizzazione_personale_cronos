import 'package:flutter/material.dart';

import '../services/buoni_pasto_service.dart';
import '../services/supabase_service.dart';
import '../utils/buoni_pasto_export.dart';
import '../utils/excel_export_helper.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/modify_feedback.dart';
import '../widgets/buoni_pasto_qr_card.dart';
import '../widgets/app_logo.dart';
import 'admin_buoni_pasto_presenze_page.dart';
import 'admin_buoni_pasto_strutture_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminBuoniPastoPage extends StatefulWidget {
  const AdminBuoniPastoPage({super.key});

  @override
  State<AdminBuoniPastoPage> createState() => _AdminBuoniPastoPageState();
}

class _AdminBuoniPastoPageState extends State<AdminBuoniPastoPage>
    with SingleTickerProviderStateMixin, RouteAware {
  final _supa = SupabaseService.client;
  late final TabController _tabs;
  bool _loading = true;
  String _search = '';
  List<BuoniPastoRistoranteRow> _ristoranti = const [];
  List<Map<String, dynamic>> _registrazioni = const [];
  DateTime _reportDal = DateTime.now().subtract(const Duration(days: 30));
  DateTime _reportAl = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      logoLightSweepRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    logoLightSweepRouteObserver.unsubscribe(this);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _ristoranti = await BuoniPastoService.loadRistoranti(_supa);
      _registrazioni = await BuoniPastoService.loadRegistrazioni(
        supa: _supa,
        dal: _reportDal,
        al: _reportAl,
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore caricamento: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<BuoniPastoRistoranteRow> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _ristoranti;
    return _ristoranti
        .where(
          (r) =>
              r.nome.toLowerCase().contains(q) ||
              (r.indirizzo ?? '').toLowerCase().contains(q) ||
              (r.email ?? '').toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  Future<void> _showQrDialog(BuoniPastoRistoranteRow row) async {
    var token = row.qrToken ?? '';
    if (token.isEmpty) {
      token = await BuoniPastoService.ensureQrToken(_supa, row.structureIdUuid);
    }
    if (!mounted) return;
    final qrKey = GlobalKey();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('QR — ${row.nome}'),
        content: SingleChildScrollView(
          child: BuoniPastoQrCard(
            repaintBoundaryKey: qrKey,
            ristoranteNome: row.nome,
            qrToken: token,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              final bytes = await captureBuoniPastoQrPng(qrKey);
              if (bytes == null || bytes.isEmpty) {
                if (ctx.mounted) {
                  ModifyFeedback.error(ctx, 'Impossibile generare immagine QR.');
                }
                return;
              }
              final safeName = row.nome.replaceAll(RegExp(r'[^\w\-]+'), '_');
              final ok = await ExcelExportHelper.saveAndReveal(
                pageName: 'QR_$safeName',
                bytes: bytes,
                extension: 'png',
                openFile: true,
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'QR salvato.' : 'Salvataggio QR annullato.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Scarica PNG'),
          ),
        ],
      ),
    );
    await _load();
  }

  Future<void> _createOperatore(BuoniPastoRistoranteRow row) async {
    final emailCtrl = TextEditingController(text: row.email ?? '');
    final userCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: row.nome);
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Credenziali ristoratore — ${row.nome}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email *'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username (opzionale)',
                ),
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome visualizzato'),
              ),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password temporanea *',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crea accesso'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (emailCtrl.text.trim().isEmpty || passCtrl.text.trim().isEmpty) {
      if (mounted) {
        ModifyFeedback.error(context, 'Email e password obbligatorie.');
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await BuoniPastoService.createOperatore(
        supa: _supa,
        structureIdUuid: row.structureIdUuid,
        email: emailCtrl.text,
        password: passCtrl.text,
        username: userCtrl.text,
        fullName: nameCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Operatore creato: ${res['username'] ?? res['email'] ?? ''}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
      setState(() => _loading = false);
    }
    emailCtrl.dispose();
    userCtrl.dispose();
    nameCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _pickReportRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _reportDal, end: _reportAl),
    );
    if (picked == null) return;
    setState(() {
      _reportDal = picked.start;
      _reportAl = picked.end;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Buoni pasto';
    final actions = [
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
    ];
    return buildGestoproAwarePage(
      context: context,
      title: title,
      toolbarActions: actions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: const Text(title),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Ristoranti'),
            Tab(text: 'Report globale'),
          ],
        ),
        actions: actions,
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildRistorantiTab(),
                _buildReportTab(),
              ],
            ),
    );
  }

  Widget _buildRistorantiTab() {
    final theme = Theme.of(context);
    final filtered = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Material(
            color: theme.colorScheme.surface,
            elevation: 0,
            borderRadius: BorderRadius.circular(14),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cerca ristorante',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: theme.colorScheme.primary.withValues(alpha: 0.75),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Nome, indirizzo ed email sono letti in tempo reale da '
                      'Gestione Dati → Strutture (flag RISTORANTE). '
                      'Aggiorna con il pulsante in alto o tirando giù l\'elenco.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.35,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _search.trim().isEmpty
                        ? 'Nessun ristorante configurato.'
                        : 'Nessun risultato per la ricerca.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final r in filtered) ...[
              _buildRistoranteCard(r),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _buildRistoranteCard(BuoniPastoRistoranteRow r) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final displayName = r.nome.trim().isEmpty ? 'Senza nome' : r.nome.trim();

    return Material(
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface,
      child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.14),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.restaurant_rounded,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        if ((r.indirizzo ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  r.indirizzo!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if ((r.email ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.mail_outline_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  r.email!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    selected: r.qrAttivo,
                    label: Text(r.qrAttivo ? 'QR attivo' : 'QR disattivo'),
                    avatar: Icon(
                      r.qrAttivo
                          ? Icons.qr_code_2_rounded
                          : Icons.qr_code_2_outlined,
                      size: 16,
                    ),
                    onSelected: (v) async {
                      await BuoniPastoService.setQrAttivo(
                        _supa,
                        r.structureIdUuid,
                        v,
                      );
                      await _load();
                    },
                  ),
                ],
              ),
              if (!r.strutturaAttiva) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.orange.shade50,
                    side: BorderSide(color: Colors.orange.shade200),
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.orange.shade800,
                    ),
                    label: Text(
                      'Struttura disattivata in Gestione Dati',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Divider(
                height: 1,
                color: theme.colorScheme.outline.withValues(alpha: 0.12),
              ),
              const SizedBox(height: 12),
              if (narrow)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showQrDialog(r),
                      icon: const Icon(Icons.qr_code_2_outlined),
                      label: const Text('QR / Scarica'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _regenerateQr(r),
                      icon: const Icon(Icons.autorenew),
                      label: const Text('Rigenera QR'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _createOperatore(r),
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Credenziali ristoratore'),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showQrDialog(r),
                      icon: const Icon(Icons.qr_code_2_outlined),
                      label: const Text('QR / Scarica'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _regenerateQr(r),
                      icon: const Icon(Icons.autorenew),
                      label: const Text('Rigenera QR'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _createOperatore(r),
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Credenziali ristoratore'),
                    ),
                  ],
                ),
              if (r.operatori.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Operatori',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final o in r.operatori)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(
                          Icons.person_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        label: Text(
                          o.username.isNotEmpty ? o.username : o.email,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
    );
  }

  Future<void> _regenerateQr(BuoniPastoRistoranteRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rigenera QR'),
        content: const Text(
          'Il QR precedente non funzionerà più. Continuare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rigenera'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BuoniPastoService.regenerateQrToken(
      _supa,
      r.structureIdUuid,
    );
    await _load();
    if (!mounted) return;
    final updated = _ristoranti.firstWhere(
      (x) => x.structureIdUuid == r.structureIdUuid,
      orElse: () => r,
    );
    await _showQrDialog(updated);
  }

  Widget _buildReportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_view_week_outlined),
            title: const Text('Report presenze dipendenti'),
            subtitle: const Text(
              'Griglia settimanale o mensile: tutti i dipendenti con pranzo/cena per giorno.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminBuoniPastoPresenzePage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.store_outlined),
            title: const Text('Riepilogo per struttura'),
            subtitle: const Text(
              'Totali pranzo/cena per ristorante, con calendario e dettaglio giornaliero.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminBuoniPastoStrutturePage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Periodo: ${_reportDal.day.toString().padLeft(2, '0')}/${_reportDal.month.toString().padLeft(2, '0')}/${_reportDal.year}'
                ' — ${_reportAl.day.toString().padLeft(2, '0')}/${_reportAl.month.toString().padLeft(2, '0')}/${_reportAl.year}',
              ),
            ),
            OutlinedButton(
              onPressed: _pickReportRange,
              child: const Text('Cambia periodo'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _registrazioni.isEmpty
                  ? null
                  : () => exportBuoniPastoExcel(
                        context,
                        rows: _registrazioni,
                        pageName: 'Buoni_pasto_report',
                      ),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Export Excel'),
            ),
            OutlinedButton.icon(
              onPressed: _registrazioni.isEmpty
                  ? null
                  : () => exportBuoniPastoCsv(
                        context,
                        rows: _registrazioni,
                        pageName: 'Buoni_pasto_report',
                      ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('CSV'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('${_registrazioni.length} registrazioni'),
        const Divider(),
        for (final row in _registrazioni) _buildRegistrazioneTile(row),
      ],
    );
  }

  Widget _buildRegistrazioneTile(Map<String, dynamic> row) {
    final structure = row['structures'];
    final nomeRistorante = structure is Map
        ? (structure['name'] ?? '').toString()
        : '';
    final tipo = (row['tipo_pasto'] ?? '').toString();
    final data = (row['data_pasto'] ?? '').toString();
    final registrato = DateTime.tryParse(
      (row['registrato_at'] ?? '').toString(),
    );
    final ora = registrato != null
        ? '${registrato.hour.toString().padLeft(2, '0')}:${registrato.minute.toString().padLeft(2, '0')}'
        : '';
    return ListTile(
      title: Text((row['dipendente_nome'] ?? '').toString()),
      subtitle: Text('$nomeRistorante · $data · $ora · $tipo'),
    );
  }
}
