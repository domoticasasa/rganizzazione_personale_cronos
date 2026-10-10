import 'dart:async';

import 'package:flutter/material.dart';

/// Numero di tick lampeggio (on/off alternati): 20 ≈ 10 lampeggi in ~5 s.
const int kDeadlineFlashDefaultTickCount = 20;

/// Impostato dalla pagina Alert scadenze prima di aprire una lista dettaglio;
/// la pagina di destinazione consuma il valore e fa lampeggiare la riga ~5 secondi.
class DeadlineNavHighlight {
  DeadlineNavHighlight._();

  static String? _uuid;
  static int _uuidFlashTickCount = kDeadlineFlashDefaultTickCount;
  static String? _formazionePersonaleId;
  static String? _formazioneRowId;
  static int? _rfiPersonaleId;

  static void clear() {
    _uuid = null;
    _uuidFlashTickCount = kDeadlineFlashDefaultTickCount;
    _formazionePersonaleId = null;
    _formazioneRowId = null;
    _rfiPersonaleId = null;
  }

  /// [flashCycles]: lampeggi gialli in pagina destinazione (default 10).
  static void armUuid(String uuid, {int flashCycles = 10}) {
    clear();
    _uuid = uuid.trim();
    _uuidFlashTickCount = (flashCycles * 2).clamp(2, 40);
  }

  static void armFormazioneDlgs({
    required String personaleId,
    required String rowId,
  }) {
    clear();
    _formazionePersonaleId = personaleId.trim();
    _formazioneRowId = rowId.trim();
  }

  static void armRfiPersonRow(int personaleId) {
    clear();
    _rfiPersonaleId = personaleId;
  }

  static String? peekUuid() => _uuid;

  static String? consumeUuid() {
    final v = _uuid;
    _uuid = null;
    return v;
  }

  static int consumeUuidFlashTickCount() {
    final c = _uuidFlashTickCount;
    _uuidFlashTickCount = kDeadlineFlashDefaultTickCount;
    return c;
  }

  static ({String pid, String rowId})? consumeFormazioneDlgs() {
    final p = _formazionePersonaleId;
    final r = _formazioneRowId;
    _formazionePersonaleId = null;
    _formazioneRowId = null;
    if (p == null || p.isEmpty || r == null || r.isEmpty) return null;
    return (pid: p, rowId: r);
  }

  static int? consumeRfiPersonRow() {
    final v = _rfiPersonaleId;
    _rfiPersonaleId = null;
    return v;
  }
}

/// Porta la riga con [idUuid] in cima alla lista (entra subito in viewport
/// anche con liste lazy / DataTable2).
bool pinRowByUuidToFront(List<Map<String, dynamic>> rows, String idUuid) {
  final target = idUuid.trim().toLowerCase();
  if (target.isEmpty || rows.isEmpty) return false;
  final i = rows.indexWhere(
    (r) => (r['id_uuid'] ?? '').toString().trim().toLowerCase() == target,
  );
  if (i < 0) return false;
  if (i == 0) return true;
  final row = rows.removeAt(i);
  rows.insert(0, row);
  return true;
}

/// Durante la navigazione da highlight: mostra solo il record cercato così
/// non resta fuori viewport (DataTable2 / scroll annidati).
List<Map<String, dynamic>> rowsForDeadlineNavFocus(
  List<Map<String, dynamic>> rows,
  String? focusUuid,
) {
  final target = focusUuid?.trim().toLowerCase() ?? '';
  if (target.isEmpty) return rows;
  final hit = rows
      .where(
        (r) =>
            (r['id_uuid'] ?? '').toString().trim().toLowerCase() == target,
      )
      .toList(growable: false);
  return hit.isEmpty ? rows : hit;
}

/// Porta i controller in cima, con retry finché non sono agganciati.
void scheduleScrollControllersToTop(
  List<ScrollController> controllers, {
  int maxAttempts = 20,
  VoidCallback? onDone,
}) {
  var attempts = 0;
  void tryJump() {
    var jumped = false;
    for (final c in controllers) {
      if (c.hasClients) {
        c.jumpTo(0);
        jumped = true;
      }
    }
    if (jumped || attempts >= maxAttempts) {
      onDone?.call();
      return;
    }
    attempts++;
    Future.delayed(const Duration(milliseconds: 80), tryJump);
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => tryJump());
}

/// Lampeggio ~5 s (alternanza on/off, tick 250 ms).
mixin DeadlineFlashTicker<S extends StatefulWidget> on State<S> {
  static const Duration _flashTick = Duration(milliseconds: 250);

  int _flashTickCount = kDeadlineFlashDefaultTickCount;

  Timer? _deadlineFlashTimer;
  String? _deadlineFlashKey;
  int _deadlineFlashPhase = 0;

  bool deadlineFlashLit(String rowKey) {
    final k = rowKey.trim().toLowerCase();
    final f = (_deadlineFlashKey ?? '').trim().toLowerCase();
    return k.isNotEmpty &&
        f.isNotEmpty &&
        k == f &&
        _deadlineFlashPhase.isOdd;
  }

  void disposeDeadlineFlash() => _deadlineFlashTimer?.cancel();

  void scheduleDeadlineFlash(
    String rowKey, {
    int? tickCount,
  }) {
    if (rowKey.isEmpty) return;
    _flashTickCount = tickCount ?? kDeadlineFlashDefaultTickCount;
    _deadlineFlashTimer?.cancel();
    setState(() {
      _deadlineFlashKey = rowKey.trim();
      // Accendi subito il giallo (isOdd), poi continua ad alternare.
      _deadlineFlashPhase = 1;
    });
    _deadlineFlashTimer = Timer.periodic(_flashTick, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _deadlineFlashPhase++;
        if (_deadlineFlashPhase >= _flashTickCount) {
          _deadlineFlashKey = null;
          _flashTickCount = kDeadlineFlashDefaultTickCount;
          t.cancel();
        }
      });
    });
  }

  void maybeConsumeDeadlineFlashUuid({void Function(String id)? onHighlight}) {
    final id = DeadlineNavHighlight.consumeUuid();
    if (id == null || id.isEmpty) return;
    final ticks = DeadlineNavHighlight.consumeUuidFlashTickCount();
    // Due frame: dopo lo spinner i controller/tabella sono agganciati.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        scheduleDeadlineFlash(id, tickCount: ticks);
        onHighlight?.call(id);
      });
    });
  }

  bool deadlineFlashFormazioneMatch(String personaleId, String rowId) =>
      deadlineFlashLit('${personaleId.trim()}|${rowId.trim()}');

  void maybeConsumeDeadlineFlashFormazioneDlgs({
    void Function(String personaleId, String rowId)? onHighlight,
  }) {
    final pair = DeadlineNavHighlight.consumeFormazioneDlgs();
    if (pair == null) return;
    final key = '${pair.pid}|${pair.rowId}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scheduleDeadlineFlash(key);
      onHighlight?.call(pair.pid, pair.rowId);
    });
  }
}

mixin DeadlineFlashTickerInt<S extends StatefulWidget> on State<S> {
  static const int _flashTickCount = kDeadlineFlashDefaultTickCount;
  static const Duration _flashTick = Duration(milliseconds: 250);

  Timer? _deadlineFlashIntTimer;
  int? _deadlineFlashIntKey;
  int _deadlineFlashIntPhase = 0;

  bool deadlineFlashLitInt(int rowId) =>
      _deadlineFlashIntKey != null &&
      _deadlineFlashIntKey == rowId &&
      _deadlineFlashIntPhase.isOdd;

  void disposeDeadlineFlashInt() => _deadlineFlashIntTimer?.cancel();

  void scheduleDeadlineFlashInt(int rowId) {
    _deadlineFlashIntTimer?.cancel();
    setState(() {
      _deadlineFlashIntKey = rowId;
      _deadlineFlashIntPhase = 0;
    });
    _deadlineFlashIntTimer = Timer.periodic(_flashTick, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _deadlineFlashIntPhase++;
        if (_deadlineFlashIntPhase >= _flashTickCount) {
          _deadlineFlashIntKey = null;
          t.cancel();
        }
      });
    });
  }

  void maybeConsumeDeadlineFlashRfi({void Function(int personaleId)? onHighlight}) {
    final id = DeadlineNavHighlight.consumeRfiPersonRow();
    if (id == null || id <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scheduleDeadlineFlashInt(id);
      onHighlight?.call(id);
    });
  }
}

/// Scroll fino al contesto della riga evidenziata, con retry (liste lazy).
void scheduleDeadlineScrollToAnchor(
  GlobalKey scrollAnchorKey, {
  int maxAttempts = 24,
  VoidCallback? onDone,
}) {
  var attempts = 0;
  void tryScroll() {
    final ctx = scrollAnchorKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      onDone?.call();
      return;
    }
    attempts++;
    if (attempts <= maxAttempts) {
      Future.delayed(const Duration(milliseconds: 120), tryScroll);
    } else {
      onDone?.call();
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
}
