import 'package:flutter/material.dart';

import '../utils/gestopro_page_chrome.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Sezione vuota di una pagina custom (collegamento da configurare).
class AdminCustomHubSlotPage extends StatelessWidget {
  const AdminCustomHubSlotPage({
    super.key,
    required this.sectionLabel,
    this.pageTitle,
  });

  final String sectionLabel;
  final String? pageTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = pageTitle ?? sectionLabel;
    final slotBody = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.layers_outlined, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                sectionLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sezione vuota: collega qui una funzione dell\'app '
                'oppure sposta un pulsante da un\'altra pagina.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return buildGestoproAwarePage(
      context: context,
      title: title,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(title: title),
      )),
      lightVeilOverTrain: false,
      body: isGestoproFuturisticUi(context)
          ? slotBody
          : PageWithTopLogo(child: slotBody),
    );
  }
}
