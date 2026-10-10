import 'dart:async';
import 'dart:ui';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/cronos_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_chat_overlay_controller.dart';
import '../../services/app_chat_service.dart';
import '../../services/app_open_tracker.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/admin_vista_guard.dart';
import '../../utils/app_chat_clipboard_image.dart';
import '../../utils/app_navigator.dart';
import '../../utils/date_formatters.dart';
import '../../utils/mobile_navigation.dart';
import '../../utils/roles.dart';
import '../futuristic/glowing_border_shell.dart';
import 'app_chat_peer_profile_sheet.dart';
import 'chat_presence_avatar.dart';

enum _ChatMode { group, direct }

/// Pannello popup chat aziendale (gruppo + privati).
class AppChatPanel extends StatefulWidget {
  const AppChatPanel({super.key});

  @override
  State<AppChatPanel> createState() => _AppChatPanelState();
}

class _AppChatPanelState extends State<AppChatPanel> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  final _inboxSearchCtrl = TextEditingController();
  final _textFocus = FocusNode();
  final _service = AppChatService.instance;

  StreamSubscription<List<AppChatMessage>>? _sub;
  List<AppChatMessage> _all = const [];
  AppChatMessage? _replyTo;
  bool _sending = false;
  bool _loading = true;
  String? _error;
  String? _myAuthId;
  bool _emojiOpen = false;

  _ChatMode _mode = _ChatMode.group;
  AppChatPeer? _peer;
  bool _pickingPeer = false;
  List<AppChatPeer> _directory = const [];
  bool _loadingDirectory = false;
  String _inboxQuery = '';

  String? _selectedGroupId;
  void Function()? _detachWebPaste;
  DateTime? _lastClipboardImageAt;
  Timer? _groupReadPoll;
  Timer? _presenceHeartbeat;
  VoidCallback? _presenceListener;

  bool get _isAdmin => canMutateAsAdmin(currentSessionRole() ?? '');

  /// Foto/documenti: gruppo per tutti; privato solo admin.
  bool get _canSendAttachments {
    if (_mode == _ChatMode.group) return _selectedGroupId != null;
    return _mode == _ChatMode.direct && _peer != null && _isAdmin;
  }

  AppChatGroup? get _selectedGroup {
    final id = _selectedGroupId;
    if (id == null) return null;
    for (final g in _service.myGroups.value) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<AppChatMessage> get _visibleMessages {
    if (_mode == _ChatMode.group) {
      final gid = _selectedGroupId;
      if (gid == null) return const [];
      return _service.groupMessages(gid);
    }
    final peer = _peer;
    if (peer == null) return const [];
    return _service.directMessagesWith(peer);
  }

  @override
  void initState() {
    super.initState();
    _myAuthId = Supabase.instance.client.auth.currentUser?.id;
    _textFocus.onKeyEvent = _onComposerKeyEvent;
    _textFocus.addListener(_onComposerFocusChanged);
    _detachWebPaste =
        AppChatClipboardImage.attachNativePasteListener(_onNativePasteImage);
    unawaited(AppChatOverlayController.ensurePanelPositionLoaded());
    _presenceListener = () {
      if (mounted) setState(() {});
    };
    _service.presenceByAuth.addListener(_presenceListener!);
    unawaited(AppOpenTracker.touchCurrentUser(force: true));
    _presenceHeartbeat = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(AppOpenTracker.heartbeat());
      unawaited(_refreshPresenceHints(force: true));
    });
    _bootstrap();
    _groupReadPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      if (_mode != _ChatMode.group) return;
      final gid = _selectedGroupId;
      if (gid == null) return;
      unawaited(_service.refreshGroupReadStates(gid));
    });
  }

  void _onComposerFocusChanged() {
    if (!_textFocus.hasFocus) return;
    if (_emojiOpen && mounted) setState(() => _emojiOpen = false);
    _scrollToBottomSoon();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.start();
      _sub?.cancel();
      _sub = _service.messagesStream.listen((list) {
        if (!mounted) return;
        setState(() => _all = list);
        unawaited(_refreshPresenceHints());
        if (_mode == _ChatMode.group && _selectedGroupId != null) {
          _scrollToBottomSoon();
          AppChatOverlayController.markSeen(groupId: _selectedGroupId);
        } else if (_mode == _ChatMode.direct && _peer != null) {
          _scrollToBottomSoon();
        }
        final peer = _peer;
        if (_mode == _ChatMode.direct && peer != null) {
          unawaited(_service.markDmConversationRead(peer));
        }
      });
      _service.dmPeerLastReadByAuth.addListener(_onPeerReadChanged);
      _service.dmUnreadByPeerAuth.addListener(_onPeerReadChanged);
      _service.groupReadStates.addListener(_onPeerReadChanged);
      _service.myGroups.addListener(_onGroupsChanged);

      final groups = _service.myGroups.value;
      String? initialGroupId;
      if (groups.isNotEmpty) {
        final aziendale = groups.where((g) => g.name == 'Aziendale');
        initialGroupId =
            (aziendale.isNotEmpty ? aziendale.first : groups.first).id;
      }
      _selectedGroupId = initialGroupId;

      setState(() {
        _all = _service.currentMessages;
        _loading = false;
      });
      unawaited(_refreshPresenceHints(force: true));

      if (initialGroupId != null) {
        unawaited(_service.refreshGroupReadStates(initialGroupId));
        AppChatOverlayController.markSeen(groupId: initialGroupId);
      }
      _scrollToBottomSoon();
      // Dopo markSeen il cursore locale si aggiorna: ricarica ricevute gruppo.
      Future<void>.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted || initialGroupId == null) return;
        unawaited(_service.refreshGroupReadStates(initialGroupId));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onPeerReadChanged() {
    if (mounted) setState(() {});
  }

  void _onGroupsChanged() {
    if (!mounted) return;
    final groups = _service.myGroups.value;
    if (_selectedGroupId != null &&
        !groups.any((g) => g.id == _selectedGroupId)) {
      final next = groups.isEmpty ? null : groups.first.id;
      setState(() => _selectedGroupId = next);
      if (next != null) {
        unawaited(_service.refreshGroupReadStates(next));
        AppChatOverlayController.markSeen(groupId: next);
      }
    } else {
      setState(() {});
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _groupReadPoll?.cancel();
    _groupReadPoll = null;
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
    if (_presenceListener != null) {
      _service.presenceByAuth.removeListener(_presenceListener!);
      _presenceListener = null;
    }
    _detachWebPaste?.call();
    _detachWebPaste = null;
    _service.dmPeerLastReadByAuth.removeListener(_onPeerReadChanged);
    _service.dmUnreadByPeerAuth.removeListener(_onPeerReadChanged);
    _service.groupReadStates.removeListener(_onPeerReadChanged);
    _service.myGroups.removeListener(_onGroupsChanged);
    _sub?.cancel();
    _textCtrl.dispose();
    _textFocus.removeListener(_onComposerFocusChanged);
    _textFocus.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _inboxSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPresenceHints({bool force = false}) async {
    final ids = <String>{};
    for (final m in _visibleMessages) {
      if (m.senderAuthId.trim().isNotEmpty) ids.add(m.senderAuthId.trim());
    }
    final peer = _peer;
    if (peer != null && peer.authId.trim().isNotEmpty) {
      ids.add(peer.authId.trim());
    }
    for (final p in _service.recentDirectPeers()) {
      if (p.authId.trim().isNotEmpty) ids.add(p.authId.trim());
    }
    if (ids.isEmpty) return;
    await _service.ensurePresenceHints(ids, force: force);
  }

  KeyEventResult _onComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isPaste = (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isPaste) return KeyEventResult.ignored;
    // Su web il listener nativo gestisce meglio gli screenshot.
    if (kIsWeb) return KeyEventResult.ignored;
    unawaited(_tryPasteClipboardImage());
    return KeyEventResult.ignored;
  }

  void _onNativePasteImage(Uint8List bytes, String mime) {
    if (!_textFocus.hasFocus) return;
    unawaited(_sendClipboardImageBytes(bytes, mime: mime));
  }

  Future<void> _tryPasteClipboardImage() async {
    if (!_canSendAttachments || _sending) return;
    final shot = await AppChatClipboardImage.readScreenshot();
    if (shot == null || !mounted) return;
    await _sendClipboardImageBytes(
      shot.bytes,
      mime: shot.mime,
      fileName: shot.fileName,
    );
  }

  Future<void> _sendClipboardImageBytes(
    Uint8List bytes, {
    required String mime,
    String? fileName,
  }) async {
    if (!_canSendAttachments || _sending) return;
    if (bytes.isEmpty) return;
    final now = DateTime.now();
    final last = _lastClipboardImageAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastClipboardImageAt = now;

    final stamp = now.toUtc().millisecondsSinceEpoch;
    final ext = mime.contains('jpeg') || mime.contains('jpg')
        ? 'jpg'
        : (mime.contains('webp')
            ? 'webp'
            : (mime.contains('gif') ? 'gif' : 'png'));
    final name = (fileName ?? 'screenshot_$stamp.$ext').trim();
    final file = AppChatAttachmentBytes(
      bytes: bytes,
      fileName: name.isEmpty ? 'screenshot_$stamp.$ext' : name,
      mimeType: mime.isEmpty ? 'image/png' : mime,
    );

    setState(() => _sending = true);
    try {
      final caption = _textCtrl.text.trim();
      await _service.sendAttachment(
        file: file,
        caption: caption.isEmpty ? null : caption,
        replyToId: _replyTo?.id,
        to: _mode == _ChatMode.direct ? _peer : null,
        groupId: _mode == _ChatMode.group ? _selectedGroupId : null,
      );
      _textCtrl.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Screenshot non inviato: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openPeerPicker() async {
    setState(() {
      _pickingPeer = true;
      _loadingDirectory = true;
      _searchCtrl.clear();
    });
    final list = await _service.listDirectory();
    if (!mounted) return;
    await _service.ensurePresenceHints(list.map((p) => p.authId), force: true);
    if (!mounted) return;
    setState(() {
      _directory = list;
      _loadingDirectory = false;
    });
  }

  Future<void> _filterDirectory(String q) async {
    setState(() => _loadingDirectory = true);
    final list = await _service.listDirectory(query: q);
    if (!mounted) return;
    await _service.ensurePresenceHints(list.map((p) => p.authId));
    if (!mounted) return;
    setState(() {
      _directory = list;
      _loadingDirectory = false;
    });
  }

  void _selectPeer(AppChatPeer peer) {
    setState(() {
      _peer = peer;
      _pickingPeer = false;
      _mode = _ChatMode.direct;
      _replyTo = null;
    });
    AppChatOverlayController.markDmSeen();
    unawaited(_syncDmReadState(peer));
    _scrollToBottomSoon();
  }

  Future<void> _syncDmReadState(AppChatPeer peer) async {
    await _service.markDmConversationRead(peer);
    await _service.refreshPeerDmLastRead(peer);
    if (mounted) setState(() {});
  }

  void _selectGroup(String groupId) {
    if (_selectedGroupId == groupId) return;
    setState(() {
      _selectedGroupId = groupId;
      _replyTo = null;
    });
    AppChatOverlayController.markSeen(groupId: groupId);
    unawaited(_service.refreshGroupReadStates(groupId));
    _scrollToBottomSoon();
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (_mode == _ChatMode.direct && _peer == null) return;
    if (_mode == _ChatMode.group && _selectedGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un gruppo.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _service.sendText(
        text: text,
        replyToId: _replyTo?.id,
        to: _mode == _ChatMode.direct ? _peer : null,
        groupId: _mode == _ChatMode.group ? _selectedGroupId : null,
      );
      _textCtrl.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invio fallito: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendFile({required bool imagesOnly}) async {
    if (_sending) return;
    if (!_canSendAttachments) {
      if (!mounted) return;
      final msg = _mode == _ChatMode.direct && !_isAdmin
          ? 'Nelle chat private solo gli amministratori possono '
              'inviare foto o documenti.'
          : (_mode == _ChatMode.group
              ? 'Seleziona un gruppo.'
              : 'Nelle chat private non è consentito inviare foto o documenti.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }
    try {
      // openFile (non ImagePicker): niente compressione / file "scaled_".
      // Carica i byte originali a massima risoluzione.
      final group = imagesOnly
          ? const XTypeGroup(
              label: 'Immagini',
              extensions: <String>[
                'png',
                'jpg',
                'jpeg',
                'webp',
                'gif',
                'heic',
                'heif',
                'bmp',
              ],
            )
          : const XTypeGroup(
              label: 'Documenti',
              extensions: <String>[
                'pdf',
                'doc',
                'docx',
                'xls',
                'xlsx',
                'zip',
                'png',
                'jpg',
                'jpeg',
                'webp',
                'gif',
                'txt',
              ],
            );
      final x = await openFile(acceptedTypeGroups: [group]);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final name = x.name;
      final mime = _guessMime(name) ??
          (imagesOnly ? 'image/jpeg' : 'application/octet-stream');
      final file = AppChatAttachmentBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: name,
        mimeType: mime,
      );

      setState(() => _sending = true);
      final caption = _textCtrl.text.trim();
      await _service.sendAttachment(
        file: file,
        caption: caption.isEmpty ? null : caption,
        replyToId: _replyTo?.id,
        to: _mode == _ChatMode.direct ? _peer : null,
        groupId: _mode == _ChatMode.group ? _selectedGroupId : null,
      );
      _textCtrl.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Allegato non inviato: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _guessMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.doc')) return 'application/msword';
    if (n.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (n.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (n.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (n.endsWith('.zip')) return 'application/zip';
    if (n.endsWith('.txt')) return 'text/plain';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Chat sempre in stile neon GESTOPRO (come Profilo personale).
    return _buildPanel(context, futuristic: true);
  }

  Widget _buildPanel(BuildContext context, {required bool futuristic}) {
    final mobile = useMobileUi(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final showComposer =
        !_pickingPeer && (_mode == _ChatMode.group || _peer != null);

    Widget buildCore({
      required double panelWidth,
      required double panelHeight,
    }) {
      final panelCore = ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(mobile ? 22 : 20),
          bottom: Radius.circular(mobile ? 0 : 20),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: futuristic
                ? CronosFuturisticTheme.panelBg.withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: mobile ? 0.82 : 0.78),
            elevation: 0,
            child: SizedBox(
              width: panelWidth,
              height: panelHeight,
              child: DefaultTextStyle(
                style: TextStyle(
                  color: futuristic
                      ? CronosFuturisticTheme.textPrimary
                      : const Color(0xFF1A1F36),
                ),
                child: Column(
                  children: [
                    if (mobile)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: (futuristic
                                    ? CronosFuturisticTheme.neonCyan
                                    : Colors.black)
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    _header(
                      context,
                      mobile,
                      futuristic: futuristic,
                      panelWidth: panelWidth,
                      panelHeight: panelHeight,
                    ),
                    _modeTabs(context, futuristic: futuristic),
                    if (_mode == _ChatMode.group)
                      _groupSelector(context, futuristic: futuristic),
                    Container(
                      width: double.infinity,
                      color: futuristic
                          ? CronosFuturisticTheme.neonCyan
                              .withValues(alpha: 0.08)
                          : const Color(0xFF2F6FED).withValues(alpha: 0.10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        _mode == _ChatMode.group
                            ? 'Messaggi ed eventuali allegati eliminati dopo 7 giorni. Visibili solo agli invitati del gruppo.'
                            : 'Chat privata a scopo lavorativo: solo testo (niente foto né documenti). Eliminata dopo 7 giorni.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: futuristic
                              ? CronosFuturisticTheme.textMuted
                              : null,
                        ),
                      ),
                    ),
                    Expanded(child: _body(context, futuristic: futuristic)),
                    if (_replyTo != null && showComposer)
                      _replyBar(context, futuristic: futuristic),
                    if (showComposer)
                      _composer(context, futuristic: futuristic),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      return futuristic
          ? GlowingBorderShell(
              color: CronosFuturisticTheme.neonCyan,
              strokeWidth: 1.6,
              borderRadius: mobile ? 22 : 20,
              child: panelCore,
            )
          : panelCore;
    }

    if (mobile) {
      final panelWidth = size.width;
      // Solleva il pannello sopra la tastiera e riduce l'altezza disponibile.
      final availableH =
          (size.height - pad.top - 8 - keyboard).clamp(280.0, size.height);
      final panelHeight = availableH.toDouble();
      return Positioned.fill(
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                AppChatOverlayController.close();
              },
              child: Container(
                color: Colors.black.withValues(alpha: futuristic ? 0.55 : 0.35),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboard,
              child: buildCore(
                panelWidth: panelWidth,
                panelHeight: panelHeight,
              ),
            ),
          ],
        ),
      );
    }

    final defaultW =
        (size.width * 0.44).clamp(340.0, 460.0).toDouble();
    final defaultH =
        (size.height * 0.76).clamp(400.0, 680.0).toDouble();

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: AppChatOverlayController.close,
            child: Container(
              color: Colors.black.withValues(alpha: futuristic ? 0.45 : 0.22),
            ),
          ),
          ValueListenableBuilder<Size?>(
            valueListenable: AppChatOverlayController.panelSize,
            builder: (context, storedSize, _) {
              final panelSize = AppChatOverlayController.clampPanelSize(
                size: storedSize ?? Size(defaultW, defaultH),
                screen: size,
                padding: pad,
              );
              final defaultLeft = size.width - panelSize.width - 20;
              final defaultTop = size.height - panelSize.height - 24;
              return ValueListenableBuilder<Offset?>(
                valueListenable: AppChatOverlayController.panelTopLeft,
                builder: (context, stored, _) {
                  final raw = stored ?? Offset(defaultLeft, defaultTop);
                  final pos = AppChatOverlayController.clampPanelTopLeft(
                    topLeft: raw,
                    screen: size,
                    panel: panelSize,
                    padding: pad,
                  );
                  return Positioned(
                    left: pos.dx,
                    top: pos.dy,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (futuristic
                                    ? CronosFuturisticTheme.neonCyan
                                    : Colors.black)
                                .withValues(alpha: futuristic ? 0.28 : 0.18),
                            blurRadius: futuristic ? 32 : 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          buildCore(
                            panelWidth: panelSize.width,
                            panelHeight: panelSize.height,
                          ),
                          // Bordo destro
                          Positioned(
                            top: 24,
                            right: 0,
                            bottom: 24,
                            width: 10,
                            child: _ChatResizeHandle(
                              cursor: SystemMouseCursors.resizeLeftRight,
                              onDrag: (dx, dy) {
                                _resizePanel(
                                  context,
                                  deltaW: dx,
                                  deltaH: 0,
                                  topLeft: pos,
                                  current: panelSize,
                                );
                              },
                            ),
                          ),
                          // Bordo inferiore
                          Positioned(
                            left: 24,
                            right: 24,
                            bottom: 0,
                            height: 10,
                            child: _ChatResizeHandle(
                              cursor: SystemMouseCursors.resizeUpDown,
                              onDrag: (dx, dy) {
                                _resizePanel(
                                  context,
                                  deltaW: 0,
                                  deltaH: dy,
                                  topLeft: pos,
                                  current: panelSize,
                                );
                              },
                            ),
                          ),
                          // Angolo basso-destra
                          Positioned(
                            right: 0,
                            bottom: 0,
                            width: 22,
                            height: 22,
                            child: _ChatResizeHandle(
                              cursor: SystemMouseCursors.resizeUpLeftDownRight,
                              showGrip: true,
                              accent: futuristic
                                  ? CronosFuturisticTheme.neonCyan
                                  : const Color(0xFF2F6FED),
                              onDrag: (dx, dy) {
                                _resizePanel(
                                  context,
                                  deltaW: dx,
                                  deltaH: dy,
                                  topLeft: pos,
                                  current: panelSize,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _resizePanel(
    BuildContext context, {
    required double deltaW,
    required double deltaH,
    required Offset topLeft,
    required Size current,
  }) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final next = AppChatOverlayController.clampPanelSize(
      size: Size(current.width + deltaW, current.height + deltaH),
      screen: size,
      padding: pad,
    );
    AppChatOverlayController.panelSize.value = next;
    // Mantieni in schermo dopo resize.
    final clampedPos = AppChatOverlayController.clampPanelTopLeft(
      topLeft: topLeft,
      screen: size,
      panel: next,
      padding: pad,
    );
    AppChatOverlayController.panelTopLeft.value = clampedPos;
  }

  void _persistPanelGeometry() {
    final size = AppChatOverlayController.panelSize.value;
    final pos = AppChatOverlayController.panelTopLeft.value;
    if (size != null) {
      unawaited(AppChatOverlayController.setPanelSize(size));
    }
    if (pos != null) {
      unawaited(AppChatOverlayController.setPanelTopLeft(pos));
    }
  }

  Widget _header(
    BuildContext context,
    bool mobile, {
    required bool futuristic,
    double? panelWidth,
    double? panelHeight,
  }) {
    final selectedGroup = _selectedGroup;
    final title = _mode == _ChatMode.group
        ? (selectedGroup?.name ?? 'Chat di gruppo')
        : (_peer?.displayName ?? 'Messaggio privato');
    final subtitle = _mode == _ChatMode.group
        ? (selectedGroup == null
            ? 'Nessun gruppo disponibile'
            : '${selectedGroup.memberCount} membri')
        : (_peer == null
            ? 'Scegli a chi scrivere'
            : 'Solo tra voi due');

    final header = Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: futuristic
              ? [
                  CronosFuturisticTheme.deepSpace,
                  CronosFuturisticTheme.panelBg,
                  CronosFuturisticTheme.electricBright.withValues(alpha: 0.45),
                ]
              : [
                  const Color(0xFF2F6FED).withValues(alpha: 0.92),
                  const Color(0xFF1B4FBF).withValues(alpha: 0.88),
                ],
        ),
        border: futuristic
            ? Border(
                bottom: BorderSide(
                  color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.45),
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          if (_mode == _ChatMode.direct && (_peer != null || _pickingPeer))
            IconButton(
              tooltip: 'Indietro',
              onPressed: () {
                setState(() {
                  if (_pickingPeer) {
                    _pickingPeer = false;
                  } else {
                    _peer = null;
                    _replyTo = null;
                  }
                });
              },
              icon: Icon(
                Icons.arrow_back,
                color: futuristic
                    ? CronosFuturisticTheme.neonCyan
                    : Colors.white,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.chat_bubble_rounded,
                color: futuristic
                    ? CronosFuturisticTheme.neonCyan
                    : Colors.white,
                size: 22,
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: mobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: futuristic ? 0.6 : 0,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: futuristic
                              ? CronosFuturisticTheme.neonCyan
                                  .withValues(alpha: 0.75)
                              : Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                : MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        final size = MediaQuery.sizeOf(context);
                        final pad = MediaQuery.paddingOf(context);
                        final stored = AppChatOverlayController.panelSize.value;
                        final panelW = panelWidth ??
                            stored?.width ??
                            (size.width * 0.44).clamp(340.0, 460.0).toDouble();
                        final panelH = panelHeight ??
                            stored?.height ??
                            (size.height * 0.76).clamp(400.0, 680.0).toDouble();
                        final current =
                            AppChatOverlayController.panelTopLeft.value ??
                                Offset(
                                  size.width - panelW - 20,
                                  size.height - panelH - 24,
                                );
                        final next =
                            AppChatOverlayController.clampPanelTopLeft(
                          topLeft: current + details.delta,
                          screen: size,
                          panel: Size(panelW, panelH),
                          padding: pad,
                        );
                        AppChatOverlayController.panelTopLeft.value = next;
                      },
                      onPanEnd: (_) => _persistPanelGeometry(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: futuristic ? 0.6 : 0,
                            ),
                          ),
                          Text(
                            'Trascina per spostare · angolo ↓↘ per ridimensionare',
                            style: TextStyle(
                              color: futuristic
                                  ? CronosFuturisticTheme.neonCyan
                                      .withValues(alpha: 0.75)
                                  : Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          if (_mode == _ChatMode.group && _isAdmin) ...[
            IconButton(
              tooltip: 'Nuovo gruppo',
              onPressed: _loading ? null : _openCreateGroupDialog,
              icon: Icon(
                Icons.group_add_outlined,
                color: futuristic
                    ? CronosFuturisticTheme.neonCyan
                    : Colors.white,
              ),
            ),
            if (_selectedGroupId != null)
              IconButton(
                tooltip: 'Membri',
                onPressed: _loading ? null : _openMembersDialog,
                icon: Icon(
                  Icons.manage_accounts_outlined,
                  color: futuristic
                      ? CronosFuturisticTheme.neonCyan
                      : Colors.white,
                ),
              ),
          ],
          if (_mode == _ChatMode.direct && _peer != null)
            IconButton(
              tooltip: 'Cancella chat con ${_peer!.displayName}',
              onPressed: _sending ? null : () => unawaited(_deleteCurrentDmConversation()),
              icon: Icon(
                Icons.delete_sweep_outlined,
                color: futuristic
                    ? CronosFuturisticTheme.neonOrange
                    : Colors.white,
              ),
            ),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _loading
                ? null
                : () async {
                    await _service.refresh();
                    if (_mode == _ChatMode.group) {
                      await _service.refreshMyGroups();
                      if (_selectedGroupId != null) {
                        unawaited(
                          _service.refreshGroupReadStates(_selectedGroupId),
                        );
                      }
                    }
                    if (_pickingPeer) await _filterDirectory(_searchCtrl.text);
                  },
            icon: Icon(
              Icons.refresh,
              color: futuristic
                  ? CronosFuturisticTheme.neonCyan
                  : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Chiudi',
            onPressed: AppChatOverlayController.close,
            icon: Icon(
              Icons.close,
              color: futuristic
                  ? CronosFuturisticTheme.neonCyan
                  : Colors.white,
            ),
          ),
        ],
      ),
    );
    return header;
  }

  Widget _modeTabs(BuildContext context, {required bool futuristic}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          AppChatOverlayController.unreadGroupCount,
          AppChatOverlayController.unreadDmCount,
        ]),
        builder: (context, _) {
          final groupUnread = AppChatOverlayController.unreadGroupCount.value;
          final dmUnread = AppChatOverlayController.unreadDmCount.value;
          final anyUnread = groupUnread > 0 || dmUnread > 0;
          final tabs = SegmentedButton<_ChatMode>(
            style: futuristic
                ? ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.28);
                      }
                      return CronosFuturisticTheme.brushedMetal
                          .withValues(alpha: 0.55);
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return CronosFuturisticTheme.neonCyan;
                      }
                      return CronosFuturisticTheme.textMuted;
                    }),
                    side: WidgetStatePropertyAll(
                      BorderSide(
                        color: CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.35),
                      ),
                    ),
                  )
                : null,
            segments: [
              ButtonSegment(
                value: _ChatMode.group,
                label: _UnreadModeTabLabel(
                  text: 'Gruppo',
                  unread: groupUnread,
                  futuristic: futuristic,
                ),
                icon: Icon(
                  groupUnread > 0
                      ? Icons.mark_chat_unread_outlined
                      : Icons.groups_outlined,
                  size: 18,
                ),
              ),
              ButtonSegment(
                value: _ChatMode.direct,
                label: _UnreadModeTabLabel(
                  text: 'Privato',
                  unread: dmUnread,
                  futuristic: futuristic,
                ),
                icon: Icon(
                  dmUnread > 0
                      ? Icons.mark_chat_unread_outlined
                      : Icons.person_outline,
                  size: 18,
                ),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              final next = s.first;
              setState(() {
                _mode = next;
                _replyTo = null;
                _pickingPeer = false;
                if (next == _ChatMode.group) {
                  _peer = null;
                }
              });
              if (next == _ChatMode.group && _selectedGroupId != null) {
                AppChatOverlayController.markSeen(groupId: _selectedGroupId);
                unawaited(_service.refreshGroupReadStates(_selectedGroupId));
                _scrollToBottomSoon();
              } else if (next == _ChatMode.direct && _peer != null) {
                AppChatOverlayController.markDmSeen();
                _scrollToBottomSoon();
              }
              // Ricalcola subito i badge tab (anche con chat aperta).
              unawaited(_service.refreshUnreadBadge());
            },
          );
          final shell = GlowingBorderShell(
            color: anyUnread
                ? CronosFuturisticTheme.neonOrange
                : CronosFuturisticTheme.neonCyan,
            strokeWidth: anyUnread ? 2.0 : 1.4,
            borderRadius: 14,
            child: tabs,
          );
          if (!anyUnread) return shell;
          return _UnreadPulse(child: shell);
        },
      ),
    );
  }

  Widget _groupSelector(BuildContext context, {required bool futuristic}) {
    return ValueListenableBuilder<List<AppChatGroup>>(
      valueListenable: _service.myGroups,
      builder: (context, groups, _) {
        final accent = futuristic
            ? CronosFuturisticTheme.neonCyan
            : const Color(0xFF2F6FED);
        if (groups.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              _isAdmin
                  ? 'Nessun gruppo. Crea il primo con «Nuovo gruppo».'
                  : 'Non sei ancora stato aggiunto a nessun gruppo.',
              style: TextStyle(
                fontSize: 12,
                color: futuristic ? CronosFuturisticTheme.textMuted : null,
              ),
            ),
          );
        }
        final selected = () {
          for (final g in groups) {
            if (g.id == _selectedGroupId) return g;
          }
          return groups.first;
        }();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Builder(
            builder: (btnCtx) {
              return GlowingBorderShell(
                color: accent,
                strokeWidth: 1.35,
                borderRadius: 14,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openGroupDropdown(
                      anchorContext: btnCtx,
                      groups: groups,
                      futuristic: futuristic,
                    ),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            CronosFuturisticTheme.electricBright
                                .withValues(alpha: 0.22),
                            CronosFuturisticTheme.deepSpace
                                .withValues(alpha: 0.92),
                            CronosFuturisticTheme.panelBg,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${selected.name} · ${selected.memberCount} membri',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CronosFuturisticTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                shadows: [
                                  Shadow(
                                    color: accent.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Icon(Icons.expand_more, color: accent),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openGroupDropdown({
    required BuildContext anchorContext,
    required List<AppChatGroup> groups,
    required bool futuristic,
  }) {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final overlayState = Overlay.maybeOf(anchorContext, rootOverlay: true) ??
        Overlay.maybeOf(anchorContext);
    if (overlayState == null) return;
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;

    final accent = futuristic
        ? CronosFuturisticTheme.neonCyan
        : const Color(0xFF2F6FED);
    final topLeft = overlayBox != null
        ? box.localToGlobal(Offset.zero, ancestor: overlayBox)
        : box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.sizeOf(anchorContext);
    final menuWidth = size.width.clamp(200.0, screen.width - 24);
    final left = topLeft.dx.clamp(12.0, screen.width - menuWidth - 12);
    final top = topLeft.dy + size.height + 4;
    final maxMenuH = (screen.height - top - 24).clamp(120.0, 260.0);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => entry.remove(),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: Material(
                elevation: 10,
                color: futuristic
                    ? CronosFuturisticTheme.deepSpace
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                shadowColor: Colors.black.withValues(alpha: 0.35),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxMenuH),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: futuristic
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (context, i) {
                      final g = groups[i];
                      final isSel = g.id == _selectedGroupId;
                      return InkWell(
                        onTap: () {
                          entry.remove();
                          _selectGroup(g.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      g.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: futuristic
                                            ? CronosFuturisticTheme.textPrimary
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${g.memberCount} membri',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: futuristic
                                            ? CronosFuturisticTheme.textMuted
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSel)
                                Icon(Icons.check, size: 18, color: accent),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(entry);
  }

  Widget _body(BuildContext context, {required bool futuristic}) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: futuristic ? CronosFuturisticTheme.neonCyan : null,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Errore chat: $_error',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: futuristic
                  ? CronosFuturisticTheme.neonRed
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      );
    }

    if (_mode == _ChatMode.direct) {
      if (_pickingPeer) {
        return _peerPicker(context, futuristic: futuristic);
      }
      if (_peer == null) {
        return _directInbox(context, futuristic: futuristic);
      }
    }

    if (_mode == _ChatMode.group && _selectedGroupId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _service.myGroups.value.isEmpty
                ? (_isAdmin
                    ? 'Nessun gruppo ancora creato.\nUsa «Nuovo gruppo» in alto.'
                    : 'Non fai ancora parte di nessun gruppo.\nChiedi a un amministratore di invitarti.')
                : 'Seleziona un gruppo dall\'elenco in alto.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: futuristic ? CronosFuturisticTheme.textMuted : null,
            ),
          ),
        ),
      );
    }

    final messages = _visibleMessages;
    // ignore: unused_local_variable — tiene aggiornato il rebuild su stream
    final _ = _all.length;

    if (messages.isEmpty) {
      return Center(
        child: Text(
          _mode == _ChatMode.group
              ? 'Nessun messaggio in «${_selectedGroup?.name ?? 'questo gruppo'}» negli ultimi 7 giorni.\nScrivi il primo!'
              : 'Nessun messaggio con ${_peer?.displayName ?? 'questo utente'}.\nScrivi il primo!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: futuristic ? CronosFuturisticTheme.textMuted : null,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[i];
        final mine = _myAuthId != null && m.senderAuthId == _myAuthId;
        return _MessageBubble(
          message: m,
          mine: mine,
          futuristic: futuristic,
          presenceHint: _service.presenceHintFor(m.senderAuthId),
          readByPeer: (mine &&
                  _mode == _ChatMode.direct &&
                  _peer != null &&
                  !m.isDeleted)
              ? _service.isDmMessageReadByPeer(m, _peer!)
              : null,
          groupReaders: (mine && _mode == _ChatMode.group && !m.isDeleted)
              ? _service.groupReadersForMessage(m)
              : null,
          onReply: m.isDeleted ? null : () => setState(() => _replyTo = m),
          onDelete: (!mine || m.isDeleted)
              ? null
              : () => unawaited(_deleteMessage(m)),
          onOpenAttachment: () => _openAttachment(m),
          onDownloadAttachment: () => unawaited(_downloadAttachment(m)),
          resolveAttachmentUrl: () => _service.signedUrlFor(m.attachmentPath),
          onPreviewImage: (url) => _previewImageFullscreen(
            url,
            m.attachmentName ?? 'Immagine',
          ),
          onShowGroupReaders: (mine && _mode == _ChatMode.group && !m.isDeleted)
              ? () => unawaited(_showGroupReadersSheet(m))
              : null,
          onShowSenderProfile: () => _showSenderProfile(m),
        );
      },
    );
  }

  Widget _directInbox(BuildContext context, {required bool futuristic}) {
    final allPeers = _service.recentDirectPeers();
    final q = _inboxQuery.trim().toLowerCase();
    final peers = q.isEmpty
        ? allPeers
        : allPeers.where((p) {
            final name = p.displayName.toLowerCase();
            return name.contains(q);
          }).toList(growable: false);
    final accent = futuristic
        ? CronosFuturisticTheme.neonCyan
        : const Color(0xFF2F6FED);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SizedBox(
            width: double.infinity,
            child: futuristic
                ? _FuturisticActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Nuovo messaggio privato',
                    onPressed: _openPeerPicker,
                  )
                : FilledButton.icon(
                    onPressed: _openPeerPicker,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Nuovo messaggio privato'),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _inboxSearchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Cerca conversazione privata...',
              isDense: true,
              filled: true,
              fillColor: futuristic
                  ? CronosFuturisticTheme.brushedMetal.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.85),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: futuristic
                      ? CronosFuturisticTheme.neonCyan.withValues(alpha: 0.3)
                      : const Color(0xFFCFD9EE),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: futuristic
                      ? CronosFuturisticTheme.neonCyan.withValues(alpha: 0.22)
                      : const Color(0xFFCFD9EE),
                ),
              ),
              suffixIcon: _inboxQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Pulisci ricerca',
                      onPressed: () {
                        _inboxSearchCtrl.clear();
                        setState(() => _inboxQuery = '');
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
            onChanged: (v) => setState(() => _inboxQuery = v),
          ),
        ),
        Expanded(
          child: peers.isEmpty
              ? Center(
                  child: Text(
                    allPeers.isEmpty
                        ? 'Nessuna conversazione privata.\nTocca «Nuovo messaggio privato».'
                        : 'Nessun risultato per la ricerca.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          futuristic ? CronosFuturisticTheme.textMuted : null,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: peers.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: futuristic
                        ? CronosFuturisticTheme.neonCyan.withValues(alpha: 0.15)
                        : null,
                  ),
                  itemBuilder: (context, i) {
                    final p = peers[i];
                    final msgs = _service.directMessagesWith(p);
                    final unreadCount = _service.dmUnreadCountForPeer(p);
                    final last = msgs.isEmpty ? null : msgs.last;
                    final preview = last == null
                        ? ''
                        : (last.body ?? last.attachmentName ?? 'allegato');
                    final tile = ListTile(
                      leading: ChatPresenceAvatar(
                        radius: 18,
                        initial: p.displayName,
                        fotoPath:
                            _service.presenceHintFor(p.authId)?.fotoPath,
                        online: _service
                                .presenceHintFor(p.authId)
                                ?.isOnline() ??
                            false,
                      ),
                      title: Text(
                        p.displayName,
                        style: TextStyle(
                          fontWeight:
                              unreadCount > 0 ? FontWeight.w900 : FontWeight.w700,
                          color: unreadCount > 0
                              ? (futuristic
                                  ? CronosFuturisticTheme.neonOrange
                                  : const Color(0xFFE65100))
                              : (futuristic
                                  ? CronosFuturisticTheme.textPrimary
                                  : null),
                        ),
                      ),
                      subtitle: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: futuristic
                              ? CronosFuturisticTheme.textMuted
                              : null,
                        ),
                      ),
                      onTap: () => _selectPeer(p),
                      trailing: unreadCount > 0
                          ? _UnreadCountBadge(
                              count: unreadCount,
                              futuristic: futuristic,
                            )
                          : null,
                    );
                    if (!futuristic) return tile;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CronosFuturisticTheme.brushedMetal
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: unreadCount > 0
                                ? CronosFuturisticTheme.neonOrange
                                    .withValues(alpha: 0.7)
                                : accent.withValues(alpha: 0.28),
                          ),
                        ),
                        child: unreadCount > 0
                            ? _UnreadPulse(child: tile)
                            : tile,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _peerPicker(BuildContext context, {required bool futuristic}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(
              color: futuristic ? CronosFuturisticTheme.textPrimary : null,
            ),
            decoration: InputDecoration(
              hintText: 'Cerca dipendente…',
              hintStyle: TextStyle(
                color: futuristic ? CronosFuturisticTheme.textMuted : null,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: futuristic ? CronosFuturisticTheme.neonCyan : null,
              ),
              filled: true,
              fillColor: futuristic
                  ? CronosFuturisticTheme.brushedMetal.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.75),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: futuristic
                    ? BorderSide(
                        color: CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.35),
                      )
                    : BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: futuristic
                    ? BorderSide(
                        color: CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.25),
                      )
                    : BorderSide.none,
              ),
              isDense: true,
            ),
            onChanged: (v) => unawaited(_filterDirectory(v)),
          ),
        ),
        Expanded(
          child: _loadingDirectory
              ? Center(
                  child: CircularProgressIndicator(
                    color: futuristic ? CronosFuturisticTheme.neonCyan : null,
                  ),
                )
              : _directory.isEmpty
                  ? Center(
                      child: Text(
                        'Nessun utente trovato.',
                        style: TextStyle(
                          color: futuristic
                              ? CronosFuturisticTheme.textMuted
                              : null,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _directory.length,
                      itemBuilder: (context, i) {
                        final p = _directory[i];
                        return ListTile(
                          leading: ChatPresenceAvatar(
                            radius: 18,
                            initial: p.displayName,
                            fotoPath:
                                _service.presenceHintFor(p.authId)?.fotoPath,
                            online: _service
                                    .presenceHintFor(p.authId)
                                    ?.isOnline() ??
                                false,
                          ),
                          title: Text(
                            p.displayName,
                            style: TextStyle(
                              color: futuristic
                                  ? CronosFuturisticTheme.textPrimary
                                  : null,
                            ),
                          ),
                          onTap: () => _selectPeer(p),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _openAttachment(AppChatMessage m) async {
    if (m.isDeleted) return;
    final url = await _service.signedUrlFor(m.attachmentPath);
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire l\'allegato.')),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _downloadAttachment(AppChatMessage m) async {
    if (m.isDeleted || !m.hasAttachment) return;
    try {
      final bytes =
          await _service.downloadAttachmentBytes(m.attachmentPath);
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download non riuscito.')),
        );
        return;
      }
      final rawName = (m.attachmentName ?? 'allegato').trim();
      final dot = rawName.lastIndexOf('.');
      final ext = (dot > 0 && dot < rawName.length - 1)
          ? rawName.substring(dot + 1).toLowerCase()
          : _extFromMime(m.attachmentMime);
      final base = (dot > 0)
          ? rawName.substring(0, dot)
          : (rawName.isEmpty ? 'allegato' : rawName);
      await FileSaver.instance.saveFile(
        name: base,
        bytes: bytes,
        ext: ext,
        mimeType: MimeType.other,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Download avviato (file originale).'
                : 'File salvato (risoluzione originale).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download fallito: $e')),
      );
    }
  }

  String _extFromMime(String? mime) {
    final m = (mime ?? '').toLowerCase();
    if (m.contains('png')) return 'png';
    if (m.contains('webp')) return 'webp';
    if (m.contains('gif')) return 'gif';
    if (m.contains('jpeg') || m.contains('jpg')) return 'jpg';
    if (m.contains('pdf')) return 'pdf';
    return 'bin';
  }

  void _previewImageFullscreen(String url, String title) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      final navCtx = appNavigatorContext;
      if (navCtx == null) return;
      unawaited(
        showDialog<void>(
          context: navCtx,
          useRootNavigator: true,
          builder: (ctx) => _ChatImageLightbox(
            url: url,
            title: title,
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
      return;
    }
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ChatImageLightbox(
        url: url,
        title: title,
        onClose: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  Future<void> _showGroupReadersSheet(AppChatMessage m) async {
    final gid = (m.groupId ?? '').trim();
    if (gid.isNotEmpty) {
      await _service.refreshGroupReadStates(gid);
    }
    if (!mounted) return;
    final readers = _service.groupReadersForMessage(m);
    await _service.ensurePresenceHints(
      readers.map((r) => r.authId),
      force: true,
    );
    if (!mounted) return;
    final futuristic = Theme.of(context).brightness == Brightness.dark;

    Widget sheet(BuildContext ctx, {required VoidCallback close}) {
      return Material(
        color: futuristic
            ? CronosFuturisticTheme.deepSpace.withValues(alpha: 0.96)
            : Theme.of(ctx).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        readers.isEmpty
                            ? 'Ancora nessuno ha visualizzato'
                            : 'Visualizzato da ${readers.length}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: futuristic
                              ? CronosFuturisticTheme.textPrimary
                              : null,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: close,
                      icon: Icon(
                        Icons.close,
                        color: futuristic
                            ? CronosFuturisticTheme.textMuted
                            : null,
                      ),
                    ),
                  ],
                ),
                if (readers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Quando qualcuno apre la chat di gruppo, il suo nome comparirà qui.',
                      style: TextStyle(
                        color: futuristic
                            ? CronosFuturisticTheme.textMuted
                            : Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: readers.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: futuristic
                            ? Colors.white.withValues(alpha: 0.08)
                            : null,
                      ),
                      itemBuilder: (context, i) {
                        final r = readers[i];
                        final when =
                            formatDateTimeItFromSupabase(r.lastReadAt);
                        final hint = _service.presenceHintFor(r.authId);
                        final online = hint?.isOnline() ?? false;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: ChatPresenceAvatar(
                            radius: 16,
                            initial: r.displayName,
                            fotoPath: hint?.fotoPath,
                            online: online,
                          ),
                          title: Text(
                            r.displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: futuristic
                                  ? CronosFuturisticTheme.textPrimary
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            '$when · ${online ? 'online' : 'offline'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: online
                                  ? const Color(0xFF22C55E)
                                  : (futuristic
                                      ? CronosFuturisticTheme.textMuted
                                      : Theme.of(ctx)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      final navCtx = appNavigatorContext;
      if (navCtx == null) return;
      unawaited(
        showModalBottomSheet<void>(
          context: navCtx,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => sheet(ctx, close: () => Navigator.of(ctx).pop()),
        ),
      );
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => entry.remove(),
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: sheet(ctx, close: () => entry.remove()),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }

  void _showSenderProfile(AppChatMessage m) {
    final userId = m.senderUserId;
    final authId = m.senderAuthId.trim();
    if (userId <= 0 && authId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilo non disponibile.')),
      );
      return;
    }

    final isSelf = _myAuthId != null &&
        authId.isNotEmpty &&
        authId == _myAuthId;
    final probePeer = AppChatPeer(
      userId: userId,
      authId: authId.isEmpty ? '—' : authId,
      displayName: m.senderName,
    );
    final hasExistingDm = !isSelf &&
        (_service.directMessagesWith(probePeer).isNotEmpty ||
            _service.recentDirectPeers().any(
                  (p) =>
                      (userId > 0 && p.userId == userId) ||
                      (authId.isNotEmpty && p.authId == authId),
                ));
    final openChatLabel =
        hasExistingDm ? 'Apri chat privata' : 'Avvia chat privata';

    void openDm(AppChatPeer peer, VoidCallback closeSheet) {
      closeSheet();
      _selectPeer(peer);
    }

    void insertSheet(OverlayState overlay) {
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => entry.remove(),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ),
              AppChatPeerProfileSheet(
                userId: userId,
                authId: authId,
                fallbackName: m.senderName,
                onClose: () => entry.remove(),
                showOpenChat: !isSelf,
                openChatLabel: openChatLabel,
                onOpenPrivateChat: isSelf
                    ? null
                    : (peer) => openDm(peer, () => entry.remove()),
              ),
            ],
          );
        },
      );
      overlay.insert(entry);
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay != null) {
      insertSheet(overlay);
      return;
    }
    final navCtx = appNavigatorContext;
    if (navCtx == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: navCtx,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => AppChatPeerProfileSheet(
          userId: userId,
          authId: authId,
          fallbackName: m.senderName,
          onClose: () => Navigator.of(ctx).pop(),
          showOpenChat: !isSelf,
          openChatLabel: openChatLabel,
          onOpenPrivateChat: isSelf
              ? null
              : (peer) => openDm(peer, () => Navigator.of(ctx).pop()),
        ),
      ),
    );
  }

  Future<void> _deleteMessage(AppChatMessage m) async {
    // Il pannello chat è in un Overlay sopra il Navigator: showDialog finirebbe
    // dietro. Conferma sullo stesso Overlay della chat.
    final confirmed = await _confirmDeleteOnOverlay();
    if (confirmed != true || !mounted) return;
    try {
      final ok = await _service.deleteMessage(m.id);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile cancellare il messaggio.')),
        );
        return;
      }
      if (_replyTo?.id == m.id) {
        setState(() => _replyTo = null);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancellazione fallita: $e')),
      );
    }
  }

  Future<void> _deleteCurrentDmConversation() async {
    final peer = _peer;
    if (peer == null) return;
    final confirm = await _showOverlayDialog<bool>(
      builder: (ctx, close) => _chatConfirmDialog(
        ctx,
        title: 'Cancella chat privata',
        message:
            'Vuoi cancellare tutta la chat con ${peer.displayName}?\n\n'
            'I messaggi verranno rimossi dalla conversazione.',
        confirmText: 'Cancella chat',
        onCancel: () => close(false),
        onConfirm: () => close(true),
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final deleted = await _service.deleteDmConversation(peer);
      if (!mounted) return;
      setState(() {
        _peer = null;
        _replyTo = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted > 0
                ? 'Chat con ${peer.displayName} cancellata ($deleted messaggi).'
                : 'Nessun messaggio da cancellare con ${peer.displayName}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore cancellazione chat: $e')),
      );
    }
  }

  Future<bool?> _confirmDeleteOnOverlay() async {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      final navCtx = appNavigatorContext;
      if (navCtx == null) return false;
      return showDialog<bool>(
        context: navCtx,
        useRootNavigator: true,
        builder: (ctx) => _deleteConfirmDialog(ctx),
      );
    }

    final completer = Completer<bool>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return Material(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: _deleteConfirmDialog(
                ctx,
                onCancel: () {
                  entry.remove();
                  if (!completer.isCompleted) completer.complete(false);
                },
                onConfirm: () {
                  entry.remove();
                  if (!completer.isCompleted) completer.complete(true);
                },
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    return completer.future;
  }

  Widget _deleteConfirmDialog(
    BuildContext ctx, {
    VoidCallback? onCancel,
    VoidCallback? onConfirm,
  }) {
    return _chatConfirmDialog(
      ctx,
      title: 'Cancella messaggio',
      message: 'Il messaggio verrà sostituito da «Messaggio cancellato». Continuare?',
      confirmText: 'Cancella',
      onCancel: onCancel ?? () => Navigator.of(ctx).pop(false),
      onConfirm: onConfirm ?? () => Navigator.of(ctx).pop(true),
    );
  }

  Widget _chatConfirmDialog(
    BuildContext ctx, {
    required String title,
    required String message,
    required String confirmText,
    required VoidCallback onCancel,
    required VoidCallback onConfirm,
  }) {
    final futuristic = Theme.of(ctx).brightness == Brightness.dark;
    final accent = futuristic
        ? CronosFuturisticTheme.neonCyan
        : const Color(0xFF2F6FED);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: futuristic
              ? CronosFuturisticTheme.deepSpace.withValues(alpha: 0.96)
              : Theme.of(ctx).dialogTheme.backgroundColor ??
                  Theme.of(ctx).colorScheme.surface,
          border: Border.all(
            color: futuristic
                ? accent.withValues(alpha: 0.42)
                : const Color(0xFFCFD9EE),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: futuristic ? 0.38 : 0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.delete_sweep_outlined,
                    color: futuristic
                        ? CronosFuturisticTheme.neonOrange
                        : Colors.redAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: futuristic
                            ? CronosFuturisticTheme.textPrimary
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: futuristic
                      ? CronosFuturisticTheme.textMuted
                      : Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: onCancel,
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: futuristic
                          ? CronosFuturisticTheme.neonOrange
                          : Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(confirmText),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Overlay generico (la chat vive in un Overlay sopra il Navigator: uno
  /// showDialog "nudo" finirebbe dietro al pannello).
  Future<T?> _showOverlayDialog<T>({
    required Widget Function(BuildContext ctx, void Function(T? result) close)
        builder,
  }) async {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      final navCtx = appNavigatorContext;
      if (navCtx == null) return null;
      return showDialog<T>(
        context: navCtx,
        useRootNavigator: true,
        builder: (ctx) =>
            builder(ctx, (result) => Navigator.of(ctx).pop(result)),
      );
    }

    final completer = Completer<T?>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return Material(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
              child: builder(ctx, (result) {
                entry.remove();
                if (!completer.isCompleted) completer.complete(result);
              }),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    return completer.future;
  }

  Future<void> _openCreateGroupDialog() async {
    final directory = await _service.listDirectory();
    if (!mounted) return;
    final futuristic = true;

    final newGroupId = await _showOverlayDialog<String>(
      builder: (ctx, close) => _CreateGroupDialogContent(
        directory: directory,
        futuristic: futuristic,
        onCancel: () => close(null),
        onCreated: (id) => close(id),
      ),
    );
    if (!mounted || newGroupId == null || newGroupId.isEmpty) return;
    await _service.refreshMyGroups();
    if (!mounted) return;
    _selectGroup(newGroupId);
  }

  Future<void> _openMembersDialog() async {
    final gid = _selectedGroupId;
    if (gid == null) return;
    final groupName = _selectedGroup?.name ?? 'Gruppo';
    final members = await _service.listGroupMembers(gid);
    if (!mounted) return;
    final directory = await _service.listDirectory();
    if (!mounted) return;
    final futuristic = true;
    final memberIds = members.map((p) => p.userId).toSet();

    final saved = await _showOverlayDialog<bool>(
      builder: (ctx, close) => _EditMembersDialogContent(
        groupName: groupName,
        directory: directory,
        initialMemberIds: memberIds,
        futuristic: futuristic,
        onCancel: () => close(false),
        onSave: (selectedIds) async {
          await _service.setGroupMembers(
            groupId: gid,
            memberUserIds: selectedIds.toList(),
          );
          close(true);
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membri del gruppo aggiornati.')),
      );
    }
  }

  Widget _replyBar(BuildContext context, {required bool futuristic}) {
    final r = _replyTo!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: futuristic
            ? CronosFuturisticTheme.deepSpace.withValues(alpha: 0.75)
            : Colors.white.withValues(alpha: 0.55),
        border: futuristic
            ? Border(
                top: BorderSide(
                  color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.25),
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Icon(
            Icons.reply,
            size: 18,
            color: futuristic ? CronosFuturisticTheme.neonCyan : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Risposta a ${r.senderName}: ${r.body ?? r.attachmentName ?? 'allegato'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: futuristic ? CronosFuturisticTheme.textMuted : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Annulla risposta',
            onPressed: () => setState(() => _replyTo = null),
            icon: Icon(
              Icons.close,
              size: 18,
              color: futuristic ? CronosFuturisticTheme.neonCyan : null,
            ),
          ),
        ],
      ),
    );
  }

  void _insertEmoji(String emoji) {
    final text = _textCtrl.text;
    final sel = _textCtrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(0, text.length);
    final next = text.replaceRange(safeStart, safeEnd, emoji);
    final caret = safeStart + emoji.length;
    _textCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret),
    );
    _textFocus.requestFocus();
  }

  Widget _composer(BuildContext context, {required bool futuristic}) {
    final isDm = _mode == _ChatMode.direct && _peer != null;
    final hint = isDm
        ? (_isAdmin
            ? 'Messaggio a ${_peer!.displayName}… (Ctrl+V per screenshot)'
            : 'Messaggio a ${_peer!.displayName}…')
        : 'Scrivi un messaggio… (Ctrl+V per screenshot)';
    final iconColor =
        futuristic ? CronosFuturisticTheme.neonCyan : null;
    final accent = futuristic
        ? CronosFuturisticTheme.neonCyan
        : const Color(0xFF2F6FED);
    return SafeArea(
      top: false,
      // Con tastiera aperta il pannello è già sollevato: evita gap extra.
      bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_emojiOpen)
            _ChatEmojiPicker(
              futuristic: futuristic,
              accent: accent,
              onPick: _insertEmoji,
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 8, 8, 10),
            decoration: BoxDecoration(
              color: futuristic
                  ? CronosFuturisticTheme.deepSpace.withValues(alpha: 0.82)
                  : Colors.white.withValues(alpha: 0.62),
              border: Border(
                top: BorderSide(
                  color: futuristic
                      ? CronosFuturisticTheme.neonCyan.withValues(alpha: 0.28)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_canSendAttachments) ...[
                  IconButton(
                    tooltip: 'Foto',
                    onPressed: _sending
                        ? null
                        : () => _pickAndSendFile(imagesOnly: true),
                    icon: Icon(Icons.photo_outlined, color: iconColor),
                  ),
                  IconButton(
                    tooltip: 'Documento',
                    onPressed: _sending
                        ? null
                        : () => _pickAndSendFile(imagesOnly: false),
                    icon: Icon(Icons.attach_file, color: iconColor),
                  ),
                ],
                IconButton(
                  tooltip: _emojiOpen ? 'Chiudi emoji' : 'Emoji',
                  onPressed: _sending
                      ? null
                      : () => setState(() => _emojiOpen = !_emojiOpen),
                  icon: Icon(
                    _emojiOpen
                        ? Icons.keyboard_outlined
                        : Icons.emoji_emotions_outlined,
                    color: iconColor,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    focusNode: _textFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onTap: () {
                      if (_emojiOpen) setState(() => _emojiOpen = false);
                      _scrollToBottomSoon();
                    },
                    onSubmitted: (_) => _sendText(),
                    style: TextStyle(
                      color: futuristic
                          ? CronosFuturisticTheme.textPrimary
                          : null,
                    ),
                    cursorColor:
                        futuristic ? CronosFuturisticTheme.neonCyan : null,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        color: futuristic
                            ? CronosFuturisticTheme.textMuted
                            : null,
                      ),
                      filled: true,
                      fillColor: futuristic
                          ? CronosFuturisticTheme.brushedMetal
                              .withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.75),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: futuristic
                            ? BorderSide(
                                color: CronosFuturisticTheme.neonCyan
                                    .withValues(alpha: 0.35),
                              )
                            : BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: futuristic
                            ? BorderSide(
                                color: CronosFuturisticTheme.neonCyan
                                    .withValues(alpha: 0.28),
                              )
                            : BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: futuristic
                              ? CronosFuturisticTheme.neonCyan
                              : const Color(0xFF2F6FED),
                          width: 1.4,
                        ),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.transparent,
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _sending ? null : _sendText,
                    customBorder: const CircleBorder(),
                    splashColor:
                        CronosFuturisticTheme.neonCyan.withValues(alpha: 0.25),
                    child: Ink(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            CronosFuturisticTheme.neonCyan
                                .withValues(alpha: 0.55),
                            CronosFuturisticTheme.electricBright
                                .withValues(alpha: 0.9),
                            CronosFuturisticTheme.deepSpace,
                          ],
                        ),
                      ),
                      child: Center(
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.futuristic,
    this.presenceHint,
    required this.readByPeer,
    required this.groupReaders,
    required this.onReply,
    required this.onDelete,
    required this.onOpenAttachment,
    required this.onDownloadAttachment,
    required this.resolveAttachmentUrl,
    required this.onPreviewImage,
    required this.onShowGroupReaders,
    required this.onShowSenderProfile,
  });

  final AppChatMessage message;
  final bool mine;
  final bool futuristic;
  final AppChatPresenceHint? presenceHint;
  /// null = non mostrare ricevuta (gruppo / messaggi altrui).
  final bool? readByPeer;
  /// null = non gruppo / non miei; lista (anche vuota) = mostra stato lettura gruppo.
  final List<AppChatGroupReader>? groupReaders;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;
  final VoidCallback onOpenAttachment;
  final VoidCallback onDownloadAttachment;
  final Future<String?> Function() resolveAttachmentUrl;
  final void Function(String url) onPreviewImage;
  final VoidCallback? onShowGroupReaders;
  final VoidCallback? onShowSenderProfile;

  String get _groupReadersLabel {
    final readers = groupReaders;
    if (readers == null) return '';
    if (readers.isEmpty) return 'Inviato';
    if (readers.length == 1) {
      return 'Visto da ${readers.first.displayName}';
    }
    if (readers.length == 2) {
      return 'Visto da ${readers[0].displayName}, ${readers[1].displayName}';
    }
    return 'Visto da ${readers[0].displayName}, '
        '${readers[1].displayName} +${readers.length - 2}';
  }

  String _replyPreviewText(AppChatMessage r) {
    if (r.isDeleted) return 'Messaggio cancellato';
    return r.body ?? r.attachmentName ?? 'allegato';
  }

  @override
  Widget build(BuildContext context) {
    final deleted = message.isDeleted;
    final accent = futuristic
        ? CronosFuturisticTheme.neonCyan
        : const Color(0xFF2F6FED);
    final muted = futuristic
        ? CronosFuturisticTheme.textMuted
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final bg = deleted
        ? (futuristic
            ? CronosFuturisticTheme.brushedMetal.withValues(alpha: 0.55)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.7))
        : (mine
            ? (futuristic
                ? CronosFuturisticTheme.electricBright.withValues(alpha: 0.28)
                : const Color(0xFF2F6FED).withValues(alpha: 0.16))
            : (futuristic
                ? CronosFuturisticTheme.brushedMetal.withValues(alpha: 0.72)
                : Theme.of(context).colorScheme.surfaceContainerHighest));
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final timeLabel = formatDateTimeItFromSupabase(message.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
            child: InkWell(
              onTap: onShowSenderProfile,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!mine) ...[
                      ChatPresenceAvatar(
                        radius: 13,
                        initial: message.senderName,
                        fotoPath: presenceHint?.fotoPath,
                        online: presenceHint?.isOnline() ?? false,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      mine ? 'Tu' : message.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: onShowSenderProfile == null
                            ? muted
                            : (futuristic
                                ? CronosFuturisticTheme.neonCyan
                                : const Color(0xFF2F6FED)),
                        decoration: onShowSenderProfile == null
                            ? TextDecoration.none
                            : TextDecoration.underline,
                        decorationColor: (futuristic
                                ? CronosFuturisticTheme.neonCyan
                                : const Color(0xFF2F6FED))
                            .withValues(alpha: 0.45),
                      ),
                    ),
                    if (!mine) ...[
                      const SizedBox(width: 6),
                      Text(
                        (presenceHint?.isOnline() ?? false)
                            ? 'online'
                            : 'offline',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: (presenceHint?.isOnline() ?? false)
                              ? const Color(0xFF22C55E)
                              : muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: InkWell(
              onLongPress: deleted
                  ? null
                  : () {
                      if (mine && onDelete != null) {
                        onDelete!();
                      } else if (onReply != null) {
                        onReply!();
                      }
                    },
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: futuristic
                      ? Border.all(
                          color: accent.withValues(alpha: mine ? 0.45 : 0.22),
                        )
                      : null,
                  boxShadow: futuristic && mine
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!deleted && message.replyPreview != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: futuristic
                              ? Colors.black.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(color: accent, width: 3),
                          ),
                        ),
                        child: Text(
                          '${message.replyPreview!.senderName}: '
                          '${_replyPreviewText(message.replyPreview!)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: futuristic
                                ? CronosFuturisticTheme.textMuted
                                : null,
                          ),
                        ),
                      ),
                    ],
                    if (deleted)
                      Text(
                        'Messaggio cancellato',
                        style: TextStyle(
                          height: 1.3,
                          fontStyle: FontStyle.italic,
                          color: muted,
                        ),
                      )
                    else if ((message.body ?? '').isNotEmpty)
                      Text(
                        message.body!,
                        style: TextStyle(
                          height: 1.3,
                          color: futuristic
                              ? CronosFuturisticTheme.textPrimary
                              : null,
                        ),
                      ),
                    if (!deleted && message.hasAttachment) ...[
                      if ((message.body ?? '').isNotEmpty)
                        const SizedBox(height: 8),
                      if (message.isImage)
                        _ChatImageAttachment(
                          fileName: message.attachmentName ?? 'Immagine',
                          accent: accent,
                          muted: muted,
                          futuristic: futuristic,
                          resolveUrl: resolveAttachmentUrl,
                          onPreview: onPreviewImage,
                          onDownload: onDownloadAttachment,
                          onOpen: onOpenAttachment,
                        )
                      else
                        _ChatFileAttachment(
                          fileName: message.attachmentName ?? 'Allegato',
                          accent: accent,
                          onOpen: onOpenAttachment,
                          onDownload: onDownloadAttachment,
                        ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          timeLabel,
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                        if (readByPeer != null) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                readByPeer!
                                    ? Icons.done_all_rounded
                                    : Icons.done_rounded,
                                size: 14,
                                color: readByPeer!
                                    ? (futuristic
                                        ? CronosFuturisticTheme.neonCyan
                                        : const Color(0xFF2F6FED))
                                    : muted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                readByPeer! ? 'Letto' : 'Inviato',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: readByPeer!
                                      ? (futuristic
                                          ? CronosFuturisticTheme.neonCyan
                                          : const Color(0xFF2F6FED))
                                      : muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (groupReaders != null)
                          InkWell(
                            onTap: onShowGroupReaders,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  groupReaders!.isEmpty
                                      ? Icons.done_rounded
                                      : Icons.done_all_rounded,
                                  size: 14,
                                  color: groupReaders!.isEmpty
                                      ? muted
                                      : (futuristic
                                          ? CronosFuturisticTheme.neonCyan
                                          : const Color(0xFF2F6FED)),
                                ),
                                const SizedBox(width: 3),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 160),
                                  child: Text(
                                    _groupReadersLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: groupReaders!.isEmpty
                                          ? muted
                                          : (futuristic
                                              ? CronosFuturisticTheme.neonCyan
                                              : const Color(0xFF2F6FED)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!deleted && onReply != null)
                          InkWell(
                            onTap: onReply,
                            child: Text(
                              'Rispondi',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: futuristic
                                    ? accent
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        if (!deleted && onDelete != null)
                          InkWell(
                            onTap: onDelete,
                            child: Text(
                              'Cancella',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: futuristic
                                    ? CronosFuturisticTheme.neonRed
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatFileAttachment extends StatelessWidget {
  const _ChatFileAttachment({
    required this.fileName,
    required this.accent,
    required this.onOpen,
    required this.onDownload,
  });

  final String fileName;
  final Color accent;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 18, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Scarica',
          onPressed: onDownload,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.download_outlined, size: 20, color: accent),
        ),
      ],
    );
  }
}

class _ChatImageAttachment extends StatefulWidget {
  const _ChatImageAttachment({
    required this.fileName,
    required this.accent,
    required this.muted,
    required this.futuristic,
    required this.resolveUrl,
    required this.onPreview,
    required this.onDownload,
    required this.onOpen,
  });

  final String fileName;
  final Color accent;
  final Color muted;
  final bool futuristic;
  final Future<String?> Function() resolveUrl;
  final void Function(String url) onPreview;
  final VoidCallback onDownload;
  final VoidCallback onOpen;

  @override
  State<_ChatImageAttachment> createState() => _ChatImageAttachmentState();
}

class _ChatImageAttachmentState extends State<_ChatImageAttachment> {
  late final Future<String?> _urlFuture = widget.resolveUrl();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<String?>(
          future: _urlFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Container(
                height: 160,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final url = snap.data;
            if (url == null || url.isEmpty) {
              return InkWell(
                onTap: widget.onOpen,
                child: Row(
                  children: [
                    Icon(Icons.broken_image_outlined,
                        size: 18, color: widget.accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.fileName,
                        style: TextStyle(
                          color: widget.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => widget.onPreview(url),
                borderRadius: BorderRadius.circular(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 240,
                      minHeight: 120,
                    ),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => Container(
                        height: 120,
                        alignment: Alignment.center,
                        color: Colors.black.withValues(alpha: 0.06),
                        child: Icon(Icons.broken_image_outlined,
                            color: widget.muted),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 160,
                          alignment: Alignment.center,
                          color: Colors.black.withValues(alpha: 0.06),
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: widget.muted),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onDownload,
              icon: Icon(Icons.download_outlined,
                  size: 16, color: widget.accent),
              label: Text(
                'Scarica',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.accent,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatImageLightbox extends StatelessWidget {
  const _ChatImageLightbox({
    required this.url,
    required this.title,
    required this.onClose,
  });

  final String url;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onClose,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 12,
              right: 8,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenuto dialog "Nuovo gruppo": nome + selezione membri dalla rubrica.
class _CreateGroupDialogContent extends StatefulWidget {
  const _CreateGroupDialogContent({
    required this.directory,
    required this.futuristic,
    required this.onCancel,
    required this.onCreated,
  });

  final List<AppChatPeer> directory;
  final bool futuristic;
  final VoidCallback onCancel;
  final void Function(String? groupId) onCreated;

  @override
  State<_CreateGroupDialogContent> createState() =>
      _CreateGroupDialogContentState();
}

class _CreateGroupDialogContentState extends State<_CreateGroupDialogContent> {
  final _nameCtrl = TextEditingController();
  final Set<int> _selected = <int>{};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Inserisci un nome per il gruppo.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await AppChatService.instance.createGroup(
        name: name,
        memberUserIds: _selected.toList(),
      );
      widget.onCreated(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Creazione fallita: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GroupDialogShell(
      futuristic: widget.futuristic,
      title: 'Nuovo gruppo',
      onClose: widget.onCancel,
      children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          style: TextStyle(
            color: widget.futuristic ? CronosFuturisticTheme.textPrimary : null,
          ),
          decoration: InputDecoration(
            labelText: 'Nome gruppo',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Membri (${_selected.length} selezionati)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: widget.futuristic ? CronosFuturisticTheme.textMuted : null,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: widget.directory.isEmpty
              ? Center(
                  child: Text(
                    'Nessun utente disponibile.',
                    style: TextStyle(
                      color: widget.futuristic
                          ? CronosFuturisticTheme.textMuted
                          : null,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.directory.length,
                  itemBuilder: (context, i) {
                    final p = widget.directory[i];
                    final checked = _selected.contains(p.userId);
                    return CheckboxListTile(
                      dense: true,
                      value: checked,
                      title: Text(
                        p.displayName,
                        style: TextStyle(
                          color: widget.futuristic
                              ? CronosFuturisticTheme.textPrimary
                              : null,
                        ),
                      ),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(p.userId);
                          } else {
                            _selected.remove(p.userId);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              color: widget.futuristic
                  ? CronosFuturisticTheme.neonRed
                  : Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : widget.onCancel,
              child: const Text('Annulla'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Crea'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Contenuto dialog "Membri": checkbox su rubrica, preselezionati i membri attuali.
class _EditMembersDialogContent extends StatefulWidget {
  const _EditMembersDialogContent({
    required this.groupName,
    required this.directory,
    required this.initialMemberIds,
    required this.futuristic,
    required this.onCancel,
    required this.onSave,
  });

  final String groupName;
  final List<AppChatPeer> directory;
  final Set<int> initialMemberIds;
  final bool futuristic;
  final VoidCallback onCancel;
  final Future<void> Function(Set<int> selectedUserIds) onSave;

  @override
  State<_EditMembersDialogContent> createState() =>
      _EditMembersDialogContentState();
}

class _EditMembersDialogContentState extends State<_EditMembersDialogContent> {
  late final Set<int> _selected = Set<int>.from(widget.initialMemberIds);
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_selected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Salvataggio fallito: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GroupDialogShell(
      futuristic: widget.futuristic,
      title: 'Membri · ${widget.groupName}',
      onClose: widget.onCancel,
      children: [
        Text(
          '${_selected.length} selezionati',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: widget.futuristic ? CronosFuturisticTheme.textMuted : null,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: widget.directory.isEmpty
              ? Center(
                  child: Text(
                    'Nessun utente disponibile.',
                    style: TextStyle(
                      color: widget.futuristic
                          ? CronosFuturisticTheme.textMuted
                          : null,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.directory.length,
                  itemBuilder: (context, i) {
                    final p = widget.directory[i];
                    final checked = _selected.contains(p.userId);
                    return CheckboxListTile(
                      dense: true,
                      value: checked,
                      title: Text(
                        p.displayName,
                        style: TextStyle(
                          color: widget.futuristic
                              ? CronosFuturisticTheme.textPrimary
                              : null,
                        ),
                      ),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(p.userId);
                          } else {
                            _selected.remove(p.userId);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              color: widget.futuristic
                  ? CronosFuturisticTheme.neonRed
                  : Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : widget.onCancel,
              child: const Text('Annulla'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salva'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Involucro comune per i dialog gruppo (overlay chat): titolo + corpo scrollabile.
class _GroupDialogShell extends StatelessWidget {
  const _GroupDialogShell({
    required this.futuristic,
    required this.title,
    required this.onClose,
    required this.children,
  });

  final bool futuristic;
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: futuristic
          ? CronosFuturisticTheme.deepSpace.withValues(alpha: 0.97)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color:
                          futuristic ? CronosFuturisticTheme.textPrimary : null,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close,
                    color: futuristic ? CronosFuturisticTheme.textMuted : null,
                  ),
                ),
              ],
            ),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatResizeHandle extends StatelessWidget {
  const _ChatResizeHandle({
    required this.cursor,
    required this.onDrag,
    this.showGrip = false,
    this.accent,
  });

  final MouseCursor cursor;
  final void Function(double dx, double dy) onDrag;
  final bool showGrip;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onDrag(d.delta.dx, d.delta.dy),
        onPanEnd: (_) {
          // Persist via nearest panel state if available — handled by parent
          // through ValueNotifier; panel calls _persistPanelGeometry on end
          // when using AppChatPanel handles. Fire a soft save here too.
          final size = AppChatOverlayController.panelSize.value;
          final pos = AppChatOverlayController.panelTopLeft.value;
          if (size != null) {
            unawaited(AppChatOverlayController.setPanelSize(size));
          }
          if (pos != null) {
            unawaited(AppChatOverlayController.setPanelTopLeft(pos));
          }
        },
        child: showGrip
            ? CustomPaint(
                size: const Size(22, 22),
                painter: _ResizeGripPainter(
                  color: (accent ?? const Color(0xFF2F6FED))
                      .withValues(alpha: 0.85),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  _ResizeGripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    const gap = 4.0;
    for (var i = 0; i < 3; i++) {
      final o = 6.0 + i * gap;
      canvas.drawLine(
        Offset(size.width - 4, size.height - o),
        Offset(size.width - o, size.height - 4),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ResizeGripPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ChatEmojiPicker extends StatelessWidget {
  const _ChatEmojiPicker({
    required this.futuristic,
    required this.accent,
    required this.onPick,
  });

  final bool futuristic;
  final Color accent;
  final void Function(String emoji) onPick;

  static const List<String> _emojis = <String>[
    '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😅',
    '😉', '🥳', '😇', '🙂', '🙌', '👍', '👎', '👏', '🙏', '💪',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '✨',
    '🔥', '⭐', '✅', '❌', '⚠️', '📌', '📎', '📝', '🗓️', '⏰',
    '🚗', '🚚', '✈️', '🚂', '🏗️', '🔧', '🛠️', '📦', '📍', '🏠',
    '☕', '🍕', '🍰', '🎉', '🎊', '💯', '🚀', '💡', '📞', '💬',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 168,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: futuristic
            ? CronosFuturisticTheme.deepSpace.withValues(alpha: 0.95)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: futuristic
                ? accent.withValues(alpha: 0.28)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: GridView.builder(
        itemCount: _emojis.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemBuilder: (context, i) {
          final emoji = _emojis[i];
          return InkWell(
            onTap: () => onPick(emoji),
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        },
      ),
    );
  }
}

/// Pulsante azione stile Nexus: bordo glow + vetro scuro.
class _FuturisticActionButton extends StatelessWidget {
  const _FuturisticActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const accent = CronosFuturisticTheme.neonCyan;
    return GlowingBorderShell(
      color: accent,
      strokeWidth: 1.8,
      borderRadius: 14,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          splashColor: accent.withValues(alpha: 0.2),
          highlightColor: accent.withValues(alpha: 0.08),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CronosFuturisticTheme.electricBright.withValues(alpha: 0.35),
                  CronosFuturisticTheme.deepSpace.withValues(alpha: 0.95),
                  CronosFuturisticTheme.panelBg,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: accent, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: CronosFonts.exo2(
                        color: CronosFuturisticTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.4,
                        shadows: [
                          Shadow(
                            color: accent.withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ],
                      ),
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

class _UnreadCountBadge extends StatelessWidget {
  const _UnreadCountBadge({
    required this.count,
    required this.futuristic,
  });

  final int count;
  final bool futuristic;

  @override
  Widget build(BuildContext context) {
    final color = futuristic
        ? CronosFuturisticTheme.neonOrange
        : const Color(0xFFE65100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Lampeggio leggero del bordo tab quando ci sono non letti.
class _UnreadPulse extends StatefulWidget {
  const _UnreadPulse({required this.child});

  final Widget child;

  @override
  State<_UnreadPulse> createState() => _UnreadPulseState();
}

class _UnreadPulseState extends State<_UnreadPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = 0.55 + (_ctrl.value * 0.45);
        return Opacity(opacity: t, child: child);
      },
      child: widget.child,
    );
  }
}

/// Etichetta tab Gruppo/Privato con badge e lampeggio se non letti.
class _UnreadModeTabLabel extends StatefulWidget {
  const _UnreadModeTabLabel({
    required this.text,
    required this.unread,
    required this.futuristic,
  });

  final String text;
  final int unread;
  final bool futuristic;

  @override
  State<_UnreadModeTabLabel> createState() => _UnreadModeTabLabelState();
}

class _UnreadModeTabLabelState extends State<_UnreadModeTabLabel>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _syncCtrl();
  }

  @override
  void didUpdateWidget(covariant _UnreadModeTabLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.unread > 0) != (widget.unread > 0)) {
      _syncCtrl();
    }
  }

  void _syncCtrl() {
    if (widget.unread > 0) {
      _ctrl ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      )..repeat(reverse: true);
    } else {
      _ctrl?.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.futuristic
        ? CronosFuturisticTheme.neonOrange
        : const Color(0xFFE65100);
    final base = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.text),
        if (widget.unread > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.unread > 99 ? '99+' : '${widget.unread}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ],
    );

    final ctrl = _ctrl;
    if (ctrl == null) return base;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, child) {
        final glow = 0.35 + (ctrl.value * 0.65);
        return DefaultTextStyle.merge(
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color.lerp(
              widget.futuristic
                  ? CronosFuturisticTheme.textMuted
                  : Colors.grey.shade700,
              accent,
              glow,
            ),
            shadows: [
              Shadow(
                color: accent.withValues(alpha: glow * 0.7),
                blurRadius: 8 + (ctrl.value * 6),
              ),
            ],
          ),
          child: child!,
        );
      },
      child: base,
    );
  }
}
