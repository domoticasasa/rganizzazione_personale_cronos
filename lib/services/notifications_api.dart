import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsApi {
  static final _supa = Supabase.instance.client;

  static Future<bool> send({
    required List<int> userIds,
    required String title,
    required String message,
  }) async {
    try {
      final resp = await _supa.functions.invoke(
        'admin-send-notification',
        body: {
          'user_ids': userIds,
          'title': title,
          'message': message,
        },
      );

      print("FUNCTION STATUS: ${resp.status}");
      print("FUNCTION DATA: ${resp.data}");

      return resp.status == 200;
    } catch (e) {
      print("FUNCTION ERROR: $e");
      return false;
    }
  }

  static Future<bool> sendToUser({
    required int userId,
    required String title,
    required String message,
  }) {
    return send(userIds: [userId], title: title, message: message);
  }

  static Future<List<int>> getAdminIds() async {
    final rows =
        await _supa.from('users').select('id').eq('role', 'admin');
    return (rows as List)
        .map((e) => (e['id'] as num).toInt())
        .toList();
  }
}