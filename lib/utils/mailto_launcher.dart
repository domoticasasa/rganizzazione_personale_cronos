import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum MailtoLaunchResult {
  opened,
  openedSubjectOnlyBodyInClipboard,
  failed,
}

/// Lunghezza massima conservativa per URL mailto (limiti browser/client).
const int kMailtoMaxUrlLength = 1900;

Uri buildMailtoUri({
  required String to,
  required String subject,
  String? body,
}) {
  final email = to.trim();
  // encodeComponent usa %20 per gli spazi (non "+"): Outlook web li interpreta correttamente.
  final query = StringBuffer('subject=${Uri.encodeComponent(subject)}');
  final trimmedBody = (body ?? '').trim();
  if (trimmedBody.isNotEmpty) {
    query.write('&body=${Uri.encodeComponent(trimmedBody)}');
  }
  return Uri.parse('mailto:$email?$query');
}

/// Apre il client email predefinito (Outlook web/desktop, Gmail, ecc.).
Future<MailtoLaunchResult> launchMailtoDraft({
  required String to,
  required String subject,
  required String body,
}) async {
  final email = to.trim();
  if (email.isEmpty) return MailtoLaunchResult.failed;

  var uri = buildMailtoUri(to: email, subject: subject, body: body);
  var copiedBody = false;

  if (uri.toString().length > kMailtoMaxUrlLength) {
    await Clipboard.setData(ClipboardData(text: body));
    copiedBody = true;
    uri = buildMailtoUri(to: email, subject: subject);
  }

  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) return MailtoLaunchResult.failed;
    return copiedBody
        ? MailtoLaunchResult.openedSubjectOnlyBodyInClipboard
        : MailtoLaunchResult.opened;
  } catch (_) {
    return MailtoLaunchResult.failed;
  }
}
