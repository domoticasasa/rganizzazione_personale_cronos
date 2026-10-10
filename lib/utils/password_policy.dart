/// Regole password comuni (reset da link, cambio obbligatorio, password
/// provvisoria admin). Tenere allineato con il Dashboard Supabase
/// (Authentication → Policies: minimo 10, lettere + cifre).
class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 10;

  static const String rulesText =
      'Almeno $minLength caratteri, con almeno una lettera e un numero. '
      'Niente spazi all\u2019inizio o alla fine.';

  /// Null se valida, altrimenti messaggio in italiano. Nessun trim silenzioso.
  static String? validate(String pw, {String? email}) {
    if (pw.isEmpty) return 'Inserisci la nuova password.';
    if (pw != pw.trim()) {
      return 'La password non può iniziare o finire con uno spazio.';
    }
    if (pw.length < minLength) {
      return 'La password deve avere almeno $minLength caratteri.';
    }
    if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(pw) || !RegExp(r'\d').hasMatch(pw)) {
      return 'La password deve contenere almeno una lettera e un numero.';
    }
    final e = (email ?? '').trim().toLowerCase();
    if (e.isNotEmpty) {
      final local = e.split('@').first;
      if (pw.toLowerCase() == e ||
          (local.length >= 4 && pw.toLowerCase().contains(local))) {
        return 'La password non deve contenere la tua email.';
      }
    }
    return null;
  }
}
