/// Errore conversione ExcelTS nel browser (messaggio propagato alla UI).
class AssenzaRfp03BrowserJsException implements Exception {
  AssenzaRfp03BrowserJsException(this.message);
  final String message;
  @override
  String toString() => message;
}
