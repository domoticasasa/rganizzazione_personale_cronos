import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/commessa_tesserino_modelli_service.dart';
import '../services/supabase_service.dart';
import '../services/tesserino_excel_import.dart';
import '../services/tesserino_foto.dart';
import '../services/tesserino_pdf_export.dart';
import '../utils/date_formatters.dart';
import '../utils/device.dart';
import '../utils/excel_export_helper.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/tesserino_helpers.dart';
import '../utils/users_directory.dart';
import '../widgets/commessa_tesserino_modelli_panel.dart';
import '../widgets/commessa_uuid_autocomplete_field.dart';
import '../widgets/cronos_tesserino_card.dart';
import '../widgets/tesserino_righe_extra_editor.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminTesseriniPage extends StatefulWidget {
  const AdminTesseriniPage({super.key});

  @override
  State<AdminTesseriniPage> createState() => _AdminTesseriniPageState();
}

class _AdminTesseriniPageState extends State<AdminTesseriniPage>
    with SingleTickerProviderStateMixin {
  static const _commessaPickCancelled = Object();
  final _supa = SupabaseService.client;
  final _search = TextEditingController();
  late final TabController _tabController;

  bool _loading = true;
  List<Map<String, dynamic>> _personale = const [];
  Map<String, String> _commesse = const {};
  List<CommessaTesserinoModello> _modelli = const [];

  @override
  void dispose() {
    _search.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('personale')
          .select(
            'id, id_uuid, full_name, active, email, user_id, matricola, telefono, '
            'data_assunzione, numero_tesserino, data_nascita, foto_tesserino_path, '
            'tesserino_extra_etichetta, tesserino_extra_testo, '
            'tesserino_righe_extra, tesserino_commessa_id_uuid',
          )
          .order('full_name', ascending: true);
      final commesse = await CommessaTesserinoModelliService.loadCommesseMap(_supa);
      List<CommessaTesserinoModello> modelli = const [];
      try {
        modelli = await CommessaTesserinoModelliService.loadModelli(_supa);
      } catch (_) {}
      _personale = await UsersDirectory.visiblePersonale(rows as List);
      _commesse = commesse;
      _modelli = modelli;
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Errore caricamento personale: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matches(Map<String, dynamic> p) {
    final q = _search.text.toLowerCase().trim();
    if (q.isEmpty) return true;
    final fn = (p['full_name'] ?? '').toString().toLowerCase();
    final nt = (p['numero_tesserino'] ?? '').toString().toLowerCase();
    return fn.contains(q) || nt.contains(q);
  }

  Future<void> _pickAndUploadFoto(Map<String, dynamic> p) async {
    TesserinoPickedImage? picked;
    try {
      picked = await pickTesserinoImageInteractive(context);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Elaborazione foto: $e');
      return;
    }
    if (picked == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessuna foto selezionata.')),
        );
      }
      return;
    }
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      await runWithTesserinoPhotoBusy(
        context,
        () => uploadTesserinoFotoForPersonale(
          supa: _supa,
          personaleId: p['id'] as int,
          personaleIdUuid: (p['id_uuid'] ?? '').toString(),
          image: picked!,
          existingStoragePath: (p['foto_tesserino_path'] ?? '').toString(),
        ),
        message: 'Caricamento foto…',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto aggiornata (sfondo bianco applicato)'),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Upload fallito: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadFoto(Map<String, dynamic> p) async {
    final path = (p['foto_tesserino_path'] ?? '').toString().trim();
    if (path.isEmpty) {
      if (mounted) {
        ModifyFeedback.hint(context, 'Nessuna foto per questo dipendente.');
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final bytes = await loadTesserinoFotoBytes(path);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Foto non disponibile in archivio.');
      }
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: tesserinoFotoExportBaseName(p),
        bytes: bytes,
        extension: 'jpg',
        openFile: true,
      );
      if (!mounted) return;
      final out = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved && out.isNotEmpty
                ? 'Foto salvata: $out'
                : 'Foto salvata',
          ),
        ),
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Download foto: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadAllFotos(List<Map<String, dynamic>> rows) async {
    final withFoto = rows
        .where(
          (p) => (p['foto_tesserino_path'] ?? '').toString().trim().isNotEmpty,
        )
        .toList();
    if (withFoto.isEmpty) {
      if (mounted) {
        ModifyFeedback.hint(context, 'Nessuna foto da scaricare.');
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final archive = Archive();
      final usedNames = <String>{};
      var added = 0;
      for (final p in withFoto) {
        final path = (p['foto_tesserino_path'] ?? '').toString().trim();
        final bytes = await loadTesserinoFotoBytes(path);
        if (bytes == null || bytes.isEmpty) continue;

        var fileName = '${tesserinoFotoExportBaseName(p)}.jpg';
        if (usedNames.contains(fileName)) {
          final id = (p['id'] ?? added).toString();
          fileName = '${tesserinoFotoExportBaseName(p)}_$id.jpg';
        }
        usedNames.add(fileName);
        archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        added++;
      }

      if (added == 0) {
        throw Exception('Impossibile scaricare le foto selezionate.');
      }

      if (added == 1) {
        final only = archive.files.first;
        final saved = await ExcelExportHelper.saveAndReveal(
          pageName: only.name.replaceAll('.jpg', ''),
          bytes: Uint8List.fromList(only.content as List<int>),
          extension: 'jpg',
          openFile: true,
        );
        if (!mounted) return;
        final out = ExcelExportHelper.lastSavedPath ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved && out.isNotEmpty ? 'Foto salvata: $out' : 'Foto salvata',
            ),
          ),
        );
        return;
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null || zipData.isEmpty) {
        throw Exception('Creazione archivio ZIP fallita.');
      }
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'foto_tesserini',
        bytes: Uint8List.fromList(zipData),
        extension: 'zip',
        openFile: true,
      );
      if (!mounted) return;
      final out = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved && out.isNotEmpty
                ? 'Scaricate $added foto in: $out'
                : 'Scaricate $added foto',
          ),
        ),
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Download foto: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importExcel() async {
    const group = XTypeGroup(
      label: 'Excel',
      extensions: ['xlsx', 'xls'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    List<int> raw;
    try {
      raw = await file.readAsBytes();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Lettura Excel fallita: $e');
      }
      return;
    }

    List<TesserinoExcelRow> excelRows;
    try {
      excelRows = parseTesseriniExcelBytes(raw);
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Excel non valido: $e');
      }
      return;
    }

    setState(() => _loading = true);
    var matched = 0;
    var skipped = 0;
    var errors = 0;
    try {
      for (final er in excelRows) {
        Map<String, dynamic>? hit;
        for (final p in _personale) {
          if (namesMatchPersonale(
            excelNome: er.nome,
            excelCognome: er.cognome,
            personaleFullName: (p['full_name'] ?? '').toString(),
          )) {
            hit = p;
            break;
          }
        }
        if (hit == null) {
          skipped++;
          continue;
        }
        final upd = <String, dynamic>{};
        if (er.numeroTesserino.trim().isNotEmpty) {
          upd['numero_tesserino'] = er.numeroTesserino.trim();
        }
        if (er.dataNascita != null) {
          upd['data_nascita'] =
              '${er.dataNascita!.year}-${er.dataNascita!.month.toString().padLeft(2, '0')}-${er.dataNascita!.day.toString().padLeft(2, '0')}';
        }
        if (er.dataAssunzione != null) {
          upd['data_assunzione'] =
              '${er.dataAssunzione!.year}-${er.dataAssunzione!.month.toString().padLeft(2, '0')}-${er.dataAssunzione!.day.toString().padLeft(2, '0')}';
        }
        if (upd.isEmpty) continue;
        try {
          await _supa.from('personale').update(upd).eq('id', hit['id']);
          matched++;
        } catch (_) {
          errors++;
        }
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import: aggiornati $matched, non trovati $skipped, errori $errors',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CommessaTesserinoOpzione> _opzioniAdminCommessa() {
    return CommessaTesserinoModelliService.modelliToOpzioni(
      _modelli,
      commesseByUuid: _commesse,
    );
  }

  Future<List<CommessaTesserinoOpzione>> _loadOpzioniCommessa(
    Map<String, dynamic> p, {
    List<CommessaTesserinoOpzione>? precaricate,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        precaricate != null &&
        precaricate.isNotEmpty) {
      return precaricate;
    }
    if (!forceRefresh) {
      final cached = _opzioniAdminCommessa();
      if (cached.isNotEmpty) return cached;
    }
    try {
      final opzioni =
          await CommessaTesserinoModelliService.loadTutteLeOpzioni(_supa);
      if (opzioni.isNotEmpty) {
        final modelli =
            await CommessaTesserinoModelliService.loadModelli(_supa);
        if (mounted) {
          setState(() {
            _modelli = modelli;
          });
        }
        return opzioni;
      }
    } catch (_) {}

    final personaleUuid = (p['id_uuid'] ?? '').toString().trim();
    if (personaleUuid.isNotEmpty) {
      try {
        final opzioni =
            await CommessaTesserinoModelliService.loadOpzioniPerPersonale(
          _supa,
          personaleUuid,
        );
        if (opzioni.isNotEmpty) return opzioni;
      } catch (_) {}
    }
    return const [];
  }

  String? _initialCommessaUuid(
    Map<String, dynamic> p,
    List<CommessaTesserinoOpzione> opzioni,
  ) {
    final saved =
        (p['tesserino_commessa_id_uuid'] ?? '').toString().trim();
    if (saved.isNotEmpty &&
        CommessaTesserinoModelliService.findOpzione(opzioni, saved) !=
            null) {
      return saved;
    }
    return null;
  }

  List<String>? _righeExtraForCommessa(
    List<CommessaTesserinoOpzione> opzioni,
    String? commessaUuid,
  ) {
    final opzione =
        CommessaTesserinoModelliService.findOpzione(opzioni, commessaUuid);
    if (opzione == null || opzione.righeExtra.isEmpty) return null;
    return opzione.righeExtra;
  }

  Future<Object?> _pickCommessaForExport(
    Map<String, dynamic> p,
    List<CommessaTesserinoOpzione> opzioni,
  ) async {
    if (opzioni.isEmpty) return null;
    if (opzioni.length == 1) {
      return _initialCommessaUuid(p, opzioni);
    }

    String? selected = _initialCommessaUuid(p, opzioni);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Commessa per il PDF'),
          content: DropdownButtonFormField<String?>(
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Commessa (opzionale)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— Nessuna commessa —'),
              ),
              for (final o in opzioni)
                DropdownMenuItem<String?>(
                  value: o.commessaIdUuid,
                  child: Text(o.commessaNome),
                ),
            ],
            onChanged: (v) => setLocal(() => selected = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Scarica PDF'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return _commessaPickCancelled;
    return selected;
  }

  Future<void> _exportPdf(
    Map<String, dynamic> p, {
    String? commessaUuid,
    List<CommessaTesserinoOpzione>? opzioniPrecaricate,
    bool promptCommessaIfNeeded = false,
    bool commessaExplicit = false,
  }) async {
    final personaleUuid = (p['id_uuid'] ?? '').toString().trim();
    List<CommessaTesserinoOpzione> opzioni =
        await _loadOpzioniCommessa(p, precaricate: opzioniPrecaricate);
    if (opzioni.isEmpty && personaleUuid.isNotEmpty) {
      try {
        opzioni = await CommessaTesserinoModelliService.loadOpzioniPerPersonale(
          _supa,
          personaleUuid,
        );
      } catch (_) {}
    }

    String? commessa;
    var explicit = commessaExplicit;
    if (promptCommessaIfNeeded && opzioni.length > 1) {
      final picked = await _pickCommessaForExport(p, opzioni);
      if (picked == _commessaPickCancelled) return;
      commessa = picked as String?;
      explicit = true;
    } else {
      commessa = explicit
          ? commessaUuid
          : (commessaUuid ?? _initialCommessaUuid(p, opzioni));
    }

    setState(() => _loading = true);
    try {
      Uint8List? fotoBytes;
      final path = (p['foto_tesserino_path'] ?? '').toString().trim();
      if (path.isNotEmpty) {
        fotoBytes = await loadTesserinoFotoBytes(path);
      }
      final view = cronosTesserinoDataFromPersonale(
        p,
        righeExtraOverride: _righeExtraForCommessa(opzioni, commessa),
      );
      final pdf = await buildTesserinoPdfBytes(data: view, fotoBytes: fotoBytes);
      final safeName = (p['full_name'] ?? 'tesserino')
          .toString()
          .replaceAll(RegExp(r'[^\w\-]+'), '_');
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'tesserino_$safeName',
        bytes: pdf,
        extension: 'pdf',
        openFile: true,
      );
      if (mounted) {
        final path = ExcelExportHelper.lastSavedPath ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved && path.isNotEmpty
                  ? 'PDF salvato e aperto: $path'
                  : 'PDF salvato',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Export PDF: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showPreview(Map<String, dynamic> p) async {
    if (!mounted) return;
    final opzioni = await _loadOpzioniCommessa(p, forceRefresh: true);
    var selCommessa = _initialCommessaUuid(p, opzioni);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final view = cronosTesserinoDataFromPersonale(
            p,
            righeExtraOverride:
                _righeExtraForCommessa(opzioni, selCommessa),
          );
          return AlertDialog(
        title: Text((p['full_name'] ?? '').toString()),
        content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (opzioni.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue: selCommessa,
                      decoration: const InputDecoration(
                        labelText: 'Commessa (opzionale)',
                        border: OutlineInputBorder(),
                        helperText:
                            'Opzionale: righe del modello commessa. '
                            'Senza selezione restano le righe salvate sul dipendente.',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('— Nessuna commessa —'),
                        ),
                        for (final o in opzioni)
                          DropdownMenuItem<String?>(
                            value: o.commessaIdUuid,
                            child: Text(o.commessaNome),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => selCommessa = v),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Nessun modello commessa configurato. '
                        'Aggiungine uno nella scheda «Modelli commessa».',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  if (opzioni.isNotEmpty) const SizedBox(height: 12),
                  CronosTesserinoCard(
            width: isMobileDevice()
                        ? (MediaQuery.sizeOf(ctx).width - 64)
                            .clamp(260.0, 360.0)
                : 380,
            data: view,
                  ),
                ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
          if ((p['foto_tesserino_path'] ?? '').toString().trim().isNotEmpty)
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _downloadFoto(p);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Scarica foto'),
            ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
                  await _exportPdf(
                    p,
                    commessaUuid: selCommessa,
                    opzioniPrecaricate: opzioni,
                    commessaExplicit: true,
                  );
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Scarica PDF'),
          ),
        ],
          );
        },
      ),
    );
  }

  Future<void> _editRecord(Map<String, dynamic> p) async {
    final sp = splitPersonaleFullName((p['full_name'] ?? '').toString());
    final nomeCtrl = TextEditingController(text: sp.nome);
    final cognomeCtrl = TextEditingController(text: sp.cognome);
    final tessCtrl =
        TextEditingController(text: (p['numero_tesserino'] ?? '').toString());
    final nascitaCtrl = TextEditingController(
      text: formatDateDdMmYyyy(p['data_nascita']),
    );
    final assunzioneCtrl = TextEditingController(
      text: formatDateDdMmYyyy(p['data_assunzione']),
    );
    String? commessaUuid =
        (p['tesserino_commessa_id_uuid'] ?? '').toString().trim();
    if (commessaUuid.isEmpty) commessaUuid = null;
    final righeControllers = tesserinoRigheControllersFromLines(
      tesserinoRigheExtraFromPersonale(p),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void applyModello(String? uuid) {
            if (uuid == null || uuid.isEmpty) return;
            CommessaTesserinoModello? modello;
            for (final m in _modelli) {
              if (m.commessaIdUuid == uuid) {
                modello = m;
                break;
              }
            }
            if (modello == null) return;
            disposeTesserinoRigheControllers(righeControllers);
            righeControllers
              ..clear()
              ..addAll(
                tesserinoRigheControllersFromLines(modello.righeExtra),
              );
            if (righeControllers.isEmpty) {
              righeControllers.add(TextEditingController());
            }
            setLocal(() => commessaUuid = uuid);
          }

          final modelliItems = _modelli
              .map(
                (m) => DropdownMenuItem<String?>(
                  value: m.commessaIdUuid,
                  child: Text(m.commessaNome ?? m.commessaIdUuid),
                ),
              )
              .toList();

          return AlertDialog(
        title: const Text('Modifica tesserino'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cognomeCtrl,
                decoration: const InputDecoration(labelText: 'Cognome'),
              ),
              TextField(
                controller: nomeCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: tessCtrl,
                decoration: const InputDecoration(
                  labelText: 'N. tesserino',
                ),
              ),
              TextField(
                controller: nascitaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nato il (gg/mm/aaaa)',
                ),
              ),
              TextField(
                controller: assunzioneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Assunto dal (gg/mm/aaaa)',
                ),
              ),
              const SizedBox(height: 12),
                    if (modelliItems.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: commessaUuid != null &&
                                _modelli.any(
                                  (m) => m.commessaIdUuid == commessaUuid,
                                )
                            ? commessaUuid
                            : null,
                decoration: const InputDecoration(
                          labelText: 'Applica modello commessa',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('— Nessun modello —'),
                          ),
                          ...modelliItems,
                        ],
                        onChanged: (v) {
                          if (v == null) {
                            setLocal(() => commessaUuid = null);
                            return;
                          }
                          applyModello(v);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    CommessaUuidAutocompleteField(
                      commesseByUuid: _commesse,
                      selectedUuid: commessaUuid,
                      labelText: 'Commessa di riferimento',
                      onSelected: (v) => setLocal(() => commessaUuid = v),
                    ),
                    const SizedBox(height: 8),
                    TesserinoRigheExtraEditor(
                      controllers: righeControllers,
                      onChanged: () => setLocal(() {}),
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
      ),
    );

    if (ok != true) {
      nomeCtrl.dispose();
      cognomeCtrl.dispose();
      tessCtrl.dispose();
      nascitaCtrl.dispose();
      assunzioneCtrl.dispose();
      disposeTesserinoRigheControllers(righeControllers);
      return;
    }

    final full =
        '${cognomeCtrl.text.trim()} ${nomeCtrl.text.trim()}'.trim();
    final tess = tessCtrl.text.trim();
    final isoNascita = parseFlexibleDateToIsoDate(nascitaCtrl.text);
    final isoAss = parseFlexibleDateToIsoDate(assunzioneCtrl.text);
    final righe = normalizeTesserinoRigheExtra(
      linesFromTesserinoRigheControllers(righeControllers),
    );

    nomeCtrl.dispose();
    cognomeCtrl.dispose();
    tessCtrl.dispose();
    nascitaCtrl.dispose();
    assunzioneCtrl.dispose();
    disposeTesserinoRigheControllers(righeControllers);

    setState(() => _loading = true);
    try {
      await _supa.from('personale').update({
        'full_name': full.isEmpty ? p['full_name'] : full,
        'numero_tesserino': tess.isEmpty ? null : tess,
        'data_nascita': isoNascita,
        'data_assunzione': isoAss,
        'tesserino_extra_etichetta': null,
        'tesserino_extra_testo': null,
        'tesserino_righe_extra': righe.isEmpty ? null : righe,
        'tesserino_commessa_id_uuid':
            (commessaUuid ?? '').trim().isEmpty ? null : commessaUuid,
      }).eq('id', p['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salvato')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Salvataggio: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = useMobileUi(context);
    final filtered = _personale.where(_matches).toList();
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: Text(narrow ? 'Tesserini' : 'Tesserini dipendenti'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Dipendenti'),
            Tab(text: 'Modelli commessa'),
          ],
        ),
        actions: [
          if (_tabController.index == 0) ...[
            if (!narrow) ...[
          IconButton(
            tooltip: 'Scarica foto elenco (ZIP se più di una)',
            onPressed: _loading ? null : () => _downloadAllFotos(filtered),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Importa da Excel',
            onPressed: _loading ? null : _importExcel,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'Ricarica',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
              ),
            ] else
              PopupMenuButton<String>(
                tooltip: 'Altro',
                onSelected: (v) {
                  switch (v) {
                    case 'zip':
                      _downloadAllFotos(filtered);
                    case 'import':
                      _importExcel();
                    case 'refresh':
                      _load();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'zip',
                    child: ListTile(
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('Scarica foto (ZIP)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(Icons.upload_file_outlined),
                      title: Text('Importa Excel'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text('Ricarica'),
                      contentPadding: EdgeInsets.zero,
                    ),
          ),
        ],
      ),
          ] else
            IconButton(
              tooltip: 'Ricarica',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
        ],
      )),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDipendentiTab(filtered, narrow),
          CommessaTesserinoModelliPanel(supa: _supa),
        ],
      ),
    );
  }

  Widget _buildDipendentiTab(List<Map<String, dynamic>> filtered, bool narrow) {
    return _loading && _personale.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Cerca per nome o N. tesserino',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Nessun risultato'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            final hasFoto =
                                (p['foto_tesserino_path'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty;
                          if (narrow) {
                            return Card(
                              child: ListTile(
                                title: Text(
                                  (p['full_name'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'Tesserino: ${(p['numero_tesserino'] ?? '—')} · Foto: ${hasFoto ? 'sì' : 'no'}',
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    switch (v) {
                                      case 'preview':
                                        _showPreview(p);
                                      case 'edit':
                                        _editRecord(p);
                                      case 'foto':
                                        _pickAndUploadFoto(p);
                                      case 'download':
                                        _downloadFoto(p);
                                      case 'pdf':
                                        _exportPdf(p, promptCommessaIfNeeded: true);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'preview',
                                      child: Text('Anteprima'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Modifica dati'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'foto',
                                      child: Text('Carica / cambia foto'),
                                    ),
                                    PopupMenuItem(
                                      value: 'download',
                                      enabled: hasFoto,
                                      child: const Text('Scarica foto'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'pdf',
                                      child: Text('PDF stampa'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                            return Card(
                              child: ListTile(
                                title: Text(
                                  (p['full_name'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'Tesserino: ${(p['numero_tesserino'] ?? '—')} · Foto: ${hasFoto ? 'sì' : 'no'}',
                                ),
                                isThreeLine: false,
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Anteprima',
                                    icon: const Icon(Icons.badge_outlined),
                                      onPressed: () => _showPreview(p),
                                    ),
                                    IconButton(
                                      tooltip: 'Modifica dati',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editRecord(p),
                                    ),
                                    IconButton(
                                      tooltip: 'Carica / cambia foto',
                                      icon: const Icon(Icons.photo_camera_outlined),
                                      onPressed: () => _pickAndUploadFoto(p),
                                    ),
                                    IconButton(
                                      tooltip: 'Scarica foto',
                                      icon: const Icon(Icons.download_outlined),
                                      onPressed:
                                          hasFoto ? () => _downloadFoto(p) : null,
                                    ),
                                    IconButton(
                                      tooltip: 'PDF stampa',
                                      icon: const Icon(Icons.picture_as_pdf),
                                    onPressed: () =>
                                        _exportPdf(p, promptCommessaIfNeeded: true),
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
}
