import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_logo.dart';

// === SERVIZI ===
import '../services/notification_bell.dart';

// === VERSIONI DESKTOP ===
import 'prenotazione_pernottamenti_page.dart';
import 'treno_page.dart';
import 'aereo_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_formazione_dlgs_81_08_page.dart';
import 'admin_formazione_rfi_page.dart';
import 'admin_logistica_hub_page.dart';
import 'admin_logistica_mdo_ferroviari_page.dart';
import 'admin_logistica_mezzi_stradali_page.dart';
import 'dt_richieste_page.dart';
import 'dt_assistenti_permissions_page.dart';
import 'dipendente_prenotazione_page.dart';
import 'caposquadra_prenotazione_page.dart';

// === VERSIONI MOBILE (USA LA CARTELLA CORRETTA: "Mobile") ===
import '../Mobile/aereo_mobile.dart';
import '../Mobile/treno_mobile.dart';
import '../Mobile/prenotazione_pernottamenti_mobile.dart';
import '../Mobile/dt_richieste_mobile.dart';
import '../Mobile/dt_assistenti_permissions_mobile.dart';
import '../Mobile/admin_misc_mobile_pages.dart';

// === DEVICE DETECTOR ===
import '../utils/device.dart';
import '../utils/roles.dart';
import '../services/mezzi_km_service.dart';
import '../services/mezzi_km_reminder_service.dart';

class HomePage extends StatefulWidget {
  final String username;
  final String fullName;
  final String role;
  final int userId;

  const HomePage({
    super.key,
    required this.username,
    required this.fullName,
    required this.role,
    required this.userId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasPendingApprovals = false;
  int _pendingApprovalsCount = 0;
  bool _pendingBlinkOn = true;
  Timer? _pendingBlinkTimer;
  Timer? _pendingRefreshTimer;
  final _supa = Supabase.instance.client;
  final Set<String> _customAllowedPages = <String>{};
  bool _customPermissionsLoaded = false;
  bool _kmPromptShownThisOpen = false;

  bool get isAdmin => isAnyAdminRole(widget.role);
  bool get isAssistenteDt =>
      widget.role.toLowerCase().replaceAll(' ', '_') == 'assistente_dt';
  bool get isDT => widget.role.toLowerCase() == 'dt';
  bool get isDipendente => widget.role.toLowerCase() == 'dipendente';
  bool get isDipendenteLike =>
      const {'dipendente', 'dipendenti', 'user'}.contains(_normalizedRole);
  bool get isLogistica => normalizeRole(widget.role) == 'logistica';
  bool get isAdminGenerale => isAdminGeneraleRole(widget.role);
  String get _normalizedRole => normalizeRole(widget.role);
  bool get _isBuiltInRole => const {
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione',
        'caposquadra',
        'dt',
        'assistente_dt',
        'logistica',
        'user',
        'dipendente',
        'admin',
      }.contains(_normalizedRole);

  bool _canShowPage(
    String pageKey,
    bool fallbackAllowed, {
    bool allowCustomRoleOverride = true,
  }) {
    if (_isBuiltInRole) return fallbackAllowed;
    if (!allowCustomRoleOverride) return false;
    if (!_customPermissionsLoaded) return false;
    return _customAllowedPages.contains(pageKey);
  }

  Future<void> _loadCustomRolePermissions() async {
    _customAllowedPages.clear();
    _customPermissionsLoaded = false;
    if (_isBuiltInRole) {
      _customPermissionsLoaded = true;
      return;
    }
    try {
      final rows = await _supa
          .from('app_custom_role_pages')
          .select('page_key, can_view')
          .eq('role_key', _normalizedRole)
          .eq('can_view', true);
      for (final row in (rows as List)) {
        final key = (row['page_key'] ?? '').toString().trim();
        if (key.isNotEmpty) _customAllowedPages.add(key);
      }
    } catch (_) {
      // fallback to default visibility rules if custom permissions are unavailable
    } finally {
      _customPermissionsLoaded = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openRolePreviewChooser() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Vista Dipendente'),
                subtitle: const Text('Apre la stessa vista del dipendente'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DipendentePrenotazioniPage(
                        userId: widget.userId,
                        username: widget.username,
                        fullName: widget.fullName,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: const Text('Vista Caposquadra'),
                subtitle: const Text('Apre la stessa vista del caposquadra'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CaposquadraPrenotazioniPage(
                        userId: widget.userId,
                        username: widget.username,
                        fullName: widget.fullName,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _pendingBlinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      if (!_hasPendingApprovals) return;
      setState(() => _pendingBlinkOn = !_pendingBlinkOn);
    });
    _pendingRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _loadPendingApprovals();
    });
    _loadCustomRolePermissions();
    _loadPendingApprovals();
    MezziKmReminderService.instance.configure(
      enabledForUser: isDipendenteLike,
      userId: widget.userId,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptMezziKmIfNeeded();
    });
  }

  @override
  void dispose() {
    _pendingBlinkTimer?.cancel();
    _pendingRefreshTimer?.cancel();
    MezziKmReminderService.instance.stop();
    super.dispose();
  }

  Future<void> _loadPendingApprovals() async {
    if (!isDT) return;
    try {
      final u = await Supabase.instance.client
          .from('users')
          .select('id_uuid')
          .eq('id', widget.userId)
          .maybeSingle();
      final dtUuid = (u?['id_uuid'] ?? '').toString().trim();
      if (dtUuid.isEmpty) return;

      final tr = await Supabase.instance.client
          .from('bookings_treno')
          .select('id')
          .eq('workflow_status', 'INVIATA_AL_DT')
          .eq('assigned_dt_user_uuid', dtUuid);
      final ar = await Supabase.instance.client
          .from('bookings_aereo')
          .select('id')
          .eq('workflow_status', 'INVIATA_AL_DT')
          .eq('assigned_dt_user_uuid', dtUuid);

      final trCount = (tr as List).length;
      final arCount = (ar as List).length;
      final totalPending = trCount + arCount;
      final hasPending = totalPending > 0;
      if (!mounted) return;
      setState(() {
        _hasPendingApprovals = hasPending;
        _pendingApprovalsCount = totalPending;
        if (!hasPending) _pendingBlinkOn = true;
      });
    } catch (_) {
      // se fallisce il check non blocchiamo la home
    }
  }

  Future<void> _checkAndPromptMezziKmIfNeeded() async {
    if (!mounted || _kmPromptShownThisOpen) return;
    if (!isDipendenteLike || !MezziKmService.shouldRequireMonthlyKm()) return;
    try {
      final pending =
          await MezziKmService.pendingAssignedMezziForCurrentMonth();
      if (!mounted || pending.isEmpty) return;
      _kmPromptShownThisOpen = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Inserimento km richiesto'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Per i mezzi a te assegnati devi inserire i km mensili prima possibile.',
                ),
                const SizedBox(height: 10),
                Text('Mezzi in attesa: ${pending.length}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Posticipa'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminLogisticaMezziStradaliPage(
                      dipendenteMode: true,
                      promptMonthlyKmOnOpen: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.speed),
              label: const Text('Inserisci km'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Se il controllo km fallisce non blocchiamo la home.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tiles = <_HomeTile>[
      // ===== PERNOTTAMENTI =====
      if (_canShowPage('pernottamenti', true))
        _HomeTile(
          icon: Icons.bed_outlined,
          label: 'Pernottamenti',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isMobileDevice()
                  ? PernottamentiMobilePage(
                      username: widget.username,
                      userId: widget.userId,
                      role: widget.role,
                      fullName: widget.fullName,
                    )
                  : PrenotazionePernottamentiPage(
                      username: widget.username,
                      userId: widget.userId,
                      role: widget.role,
                      fullName: widget.fullName,
                    ),
            ),
          ),
        ),

      // ===== TRENI =====
      if (_canShowPage('treni', true))
        _HomeTile(
          icon: Icons.train_outlined,
          label: 'Treni',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isMobileDevice()
                  ? TrenoMobilePage(
                      username: widget.username,
                      userId: widget.userId,
                      role: widget.role,
                      fullName: widget.fullName,
                    )
                  : TrenoPage(
                      username: widget.username,
                      userId: widget.userId,
                      role: widget.role,
                      fullName: widget.fullName,
                    ),
            ),
          ),
        ),

      // ===== AEREI =====
      if (_canShowPage('aerei', true))
        _HomeTile(
          icon: Icons.flight_takeoff_outlined,
          label: 'Aerei',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isMobileDevice()
                  ? AereoMobilePage(
                      username: widget.username,
                      userId: widget.userId,
                      role: widget.role,
                      fullName: widget.fullName,
                    )
                  : AereoPage(
                      username: widget.username,
                      userId: widget.userId,
                      role: widget.role,
                      fullName: widget.fullName,
                    ),
            ),
          ),
        ),
    ];

    // ===== ADMIN =====
    if (_canShowPage('admin_dashboard', isAdmin)) {
      tiles.add(
        _HomeTile(
          icon: Icons.dashboard_outlined,
          label: 'Admin Dashboard',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminDashboardPage(
                adminId: widget.userId,
                role: widget.role,
                customAllowedPages: _customAllowedPages,
              ),
            ),
          ),
        ),
      );
    }
    if (_canShowPage('anteprima_vista_ruolo', isAdminGenerale)) {
      tiles.add(
        _HomeTile(
          icon: Icons.visibility_outlined,
          label: 'Anteprima vista ruolo',
          color: theme.colorScheme.primary,
          onTap: _openRolePreviewChooser,
        ),
      );
    }

    // ===== DT =====
    if (_canShowPage('richieste_da_approvare', isDT)) {
      tiles.add(
        _HomeTile(
          icon: Icons.approval_outlined,
          label: 'Richieste da approvare',
          color: _hasPendingApprovals
              ? (_pendingBlinkOn ? Colors.red : theme.colorScheme.primary)
              : theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isMobileDevice()
                  ? DTRichiesteMobilePage(
                      userId: widget.userId, fullName: widget.fullName)
                  : DTRichiestePage(
                      userId: widget.userId, fullName: widget.fullName),
            ),
          ).then((_) => _loadPendingApprovals()),
        ),
      );
    }

    if (_canShowPage('formazione_rfi', isDT || isAssistenteDt)) {
      tiles.add(
        _HomeTile(
          icon: Icons.account_tree_outlined,
          label: 'Formazione RFI',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminFormazioneRfiPage(readOnly: true),
            ),
          ),
        ),
      );
    }

    if (_canShowPage(
        'logistica', isAdmin || isDT || isAssistenteDt || isLogistica)) {
      tiles.add(
        _HomeTile(
          icon: Icons.local_shipping_outlined,
          label: 'Logistica',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isMobileDevice()
                  ? AdminLogisticaHubMobilePage(userId: widget.userId)
                  : AdminLogisticaHubPage(userId: widget.userId),
            ),
          ),
        ),
      );
    }

    if (_canShowPage(
      'mdo_ferroviari',
      isDipendenteLike,
    )) {
      tiles.add(
        _HomeTile(
          icon: Icons.train_outlined,
          label: 'MDO Ferroviari',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const AdminLogisticaMdoFerroviariPage(dipendenteMode: true),
            ),
          ),
        ),
      );
    }

    if (_canShowPage('mezzi_stradali', isDipendenteLike)) {
      tiles.add(
        _HomeTile(
          icon: Icons.local_shipping_outlined,
          label: 'Mezzi Stradali',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminLogisticaMezziStradaliPage(
                dipendenteMode: true,
                promptMonthlyKmOnOpen: true,
              ),
            ),
          ),
        ),
      );
    }

    if (_canShowPage('formazione_dlgs_81_08', isDT)) {
      tiles.add(
        _HomeTile(
          icon: Icons.school_outlined,
          label: 'Formazione D.Lgs. 81/08',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminFormazionePage(readOnly: true),
            ),
          ),
        ),
      );
    }

    if (_canShowPage('permessi_assistenti_dt', isDT)) {
      tiles.add(
        _HomeTile(
          icon: Icons.security_outlined,
          label: 'Permessi Assistenti DT',
          color: theme.colorScheme.primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isMobileDevice()
                  ? DtAssistentiPermissionsMobilePage(
                      fullName: widget.fullName,
                    )
                  : DtAssistentiPermissionsPage(
                      fullName: widget.fullName,
                    ),
            ),
          ),
        ),
      );
    }

    int crossAxis = MediaQuery.of(context).size.width >= 1000
        ? (MediaQuery.of(context).size.width >= 1500 ? 4 : 3)
        : 2;

    return Scaffold(
      appBar: AppBar(
        title: ResponsiveAppBarTitle(title: 'Benvenuto ${widget.fullName}'),
        actions: [
          NotificationBell(
              userId: widget.userId, iconColor: theme.colorScheme.onPrimary),
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadPendingApprovals();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Home aggiornata')),
              );
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },
          ),
        ],
      ),
      body: PageWithTopLogo(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            itemCount: tiles.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxis,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.25,
            ),
            itemBuilder: (context, index) {
              final tile = tiles[index];
              final isPendingTile = tile.label == 'Richieste da approvare';
              return _HomeCard(
                item: tile,
                badgeCount: isPendingTile ? _pendingApprovalsCount : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HomeTile {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  _HomeTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
}

class _HomeCard extends StatelessWidget {
  final _HomeTile item;
  final int? badgeCount;

  const _HomeCard({required this.item, this.badgeCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: item.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.icon,
                    size: 48, color: item.color ?? theme.colorScheme.primary),
                if (badgeCount != null && badgeCount! > 0)
                  Positioned(
                    right: -10,
                    top: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badgeCount! > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(item.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
