/// Dati del FORNITORE del software (Alexandru Cibuc / GESTOPRO) usati nei
/// Termini d'uso. Compilare qui OPPURE nella tabella `app_legal_settings`
/// (i valori del database hanno la precedenza).
/// Finché un campo resta vuoto l'app NON mostra i Termini (mostra un
/// messaggio neutro), così non compaiono mai segnaposto non compilati.
abstract final class LegalConfig {
  static const String fornitoreRagioneSociale = '';
  static const String fornitorePiva = '';
  static const String fornitoreSede = '';
  static const String fornitorePec = '';
  static const String emailAssistenza = '';
  static const String fornitoreEmail = '';
  static const String noteLegaliData = '';
  static const String terminiVersione = '1.0';
  static const String terminiData = '';

  /// Conservazione posizioni GPS (mesi). Valore di default se il database
  /// non ne indica uno (`app_legal_settings.gps_retention_months`).
  static const int gpsRetentionMonths = 12;
}
