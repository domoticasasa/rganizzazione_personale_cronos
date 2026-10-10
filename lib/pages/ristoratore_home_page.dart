import 'package:flutter/material.dart';

import '../pages/ristoratore_buoni_pasto_report_page.dart';
import '../services/supabase_service.dart';
import '../utils/app_logout.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Home per operatori ristorante (report buoni pasto).
class RistoratoreHomePage extends StatefulWidget {
  const RistoratoreHomePage({
    super.key,
    required this.username,
    required this.fullName,
    required this.userId,
  });

  final String username;
  final String fullName;
  final int userId;

  @override
  State<RistoratoreHomePage> createState() => _RistoratoreHomePageState();
}

class _RistoratoreHomePageState extends State<RistoratoreHomePage> {
  String? _structureId;
  String? _structureName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final supa = SupabaseService.client;
      _structureId = await supa.rpc('current_ristoratore_structure_uuid') as String?;
      if (_structureId != null && _structureId!.isNotEmpty) {
        final row = await supa
            .from('structures')
            .select('name')
            .eq('id_uuid', _structureId!)
            .maybeSingle();
        _structureName = (row?['name'] ?? '').toString();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() => performAppLogout(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Portale ristoratore'),
        actions: [
          IconButton(
            tooltip: 'Esci',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      )),
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Benvenuto, ${widget.fullName.isNotEmpty ? widget.fullName : widget.username}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if ((_structureName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _structureName!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _structureId == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => RistoratoreBuoniPastoReportPage(
                                    structureIdUuid: _structureId!,
                                    structureName: _structureName ?? '',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Report buoni pasto'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
