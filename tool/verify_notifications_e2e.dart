// Verifica end-to-end: inserimento notifica + lettura come fa il client.
// Uso: dart run tool/verify_notifications_e2e.dart --user-id=2
// Richiede SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY (o anon + test manuale).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

void main(List<String> args) async {
  final userId = _argInt(args, 'user-id') ?? 2;
  final url = Platform.environment['SUPABASE_URL'] ??
      'https://bjdimalvbdablzoctrsf.supabase.co';
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

  if (serviceKey.isEmpty) {
    stderr.writeln(
      'Imposta SUPABASE_SERVICE_ROLE_KEY (Dashboard → Settings → API) '
      'per eseguire il test automatico.',
    );
    exit(2);
  }

  final headers = {
    'apikey': serviceKey,
    'Authorization': 'Bearer $serviceKey',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  // Ultima notifica consegnata simulata: max id esistente prima del test.
  final beforeRes = await http.get(
    Uri.parse(
      '$url/rest/v1/notifications?user_id=eq.$userId&select=id&order=id.desc&limit=1',
    ),
    headers: headers,
  );
  final beforeList = jsonDecode(beforeRes.body) as List;
  final beforeId = beforeList.isEmpty
      ? 0
      : (beforeList.first as Map)['id'] as int;

  stdout.writeln('User #$userId — ultimo id notifica prima del test: $beforeId');

  final testTitle = 'Test automatico Cronos ${DateTime.now().toIso8601String()}';
  final insertRes = await http.post(
    Uri.parse('$url/rest/v1/notifications'),
    headers: headers,
    body: jsonEncode({
      'user_id': userId,
      'title': testTitle,
      'message': 'Verifica banner: se l\'app è in ascolto deve comparire entro ~15s.',
      'meta': {
        'action': 'test_auto',
        'booking_id': DateTime.now().millisecondsSinceEpoch % 2000000000,
      },
      'is_read': false,
    }),
  );

  if (insertRes.statusCode < 200 || insertRes.statusCode >= 300) {
    stderr.writeln('INSERT fallito: ${insertRes.statusCode} ${insertRes.body}');
    exit(1);
  }

  final inserted = (jsonDecode(insertRes.body) as List).first as Map;
  final newId = inserted['id'] as int;
  stdout.writeln('Inserita notifica id=$newId title="$testTitle"');

  // Simula query polling client (gt lastSeen).
  await Future<void>.delayed(const Duration(seconds: 2));
  final pollRes = await http.get(
    Uri.parse(
      '$url/rest/v1/notifications?user_id=eq.$userId&id=gt.$beforeId'
      '&select=id,title,message&order=id.asc',
    ),
    headers: headers,
  );
  final pollList = jsonDecode(pollRes.body) as List;
  stdout.writeln(
    'Polling (id > $beforeId): ${pollList.length} righe — '
    '${pollList.map((e) => (e as Map)['id']).toList()}',
  );

  if (pollList.any((e) => (e as Map)['id'] == newId)) {
    stdout.writeln('OK: il DB espone la notifica; il client la troverebbe in poll.');
    stdout.writeln(
      'Con app aperta cerca in console: >>> LISTENER ATTIVO / >>> NOTIFICA VALIDA',
    );
    exit(0);
  } else {
    stderr.writeln('ERRORE: notifica inserita ma non visibile in poll.');
    exit(1);
  }
}

int? _argInt(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) {
      return int.tryParse(a.split('=').last);
    }
  }
  return null;
}
