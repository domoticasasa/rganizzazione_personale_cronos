import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal_config.dart';

/// Testi legali in-app (audit legale A1, 10/10/2026).
///
/// - Informativa privacy: il titolare è l'azienda cliente, quindi il testo
///   completato va caricato per cliente in `app_legal_documents`
///   (doc_key = 'informativa_privacy', published = true). Se manca o contiene
///   ancora segnaposto, l'app mostra [neutralPrivacyMessage].
/// - Termini d'uso: testo del fornitore (documento 03) compilato con i dati di
///   [LegalConfig] / `app_legal_settings`; se qualche dato manca, messaggio neutro.
class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.content,
    required this.version,
    required this.available,
  });

  final String title;
  final String content;
  final String version;

  /// false = testo non pubblicabile (mostrare il messaggio neutro).
  final bool available;
}

class LegalSettings {
  const LegalSettings({
    this.aziendaNome = '',
    this.gpsRetentionMonths = LegalConfig.gpsRetentionMonths,
    this.fornitore = const {},
  });

  final String aziendaNome;
  final int gpsRetentionMonths;
  final Map<String, String> fornitore;
}

abstract final class LegalDocumentsService {
  static const String privacyKey = 'informativa_privacy';
  static const String terminiKey = 'termini_uso';

  static const String neutralPrivacyMessage =
      'Informativa in fase di pubblicazione: contatta il tuo datore di lavoro.';
  static const String neutralNoteLegaliMessage =
      'Note legali in fase di pubblicazione.';
  static const String neutralTermsMessage =
      "Termini d'uso in fase di pubblicazione: contatta il tuo datore di lavoro.";

  static final RegExp _placeholder = RegExp(
    r'\[(?:[^\]]*(?:DA COMPLETARE|DA ALLINEARE|RAGIONE SOCIALE|P\.IVA|SEDE|PEC|E-MAIL|NOME|DATA|LUOGO|es\.)[^\]]*)\]|\{\{[A-Z_]+\}\}|_{4,}',
  );

  /// true se il testo contiene ancora segnaposto del modello.
  static bool hasPlaceholders(String text) => _placeholder.hasMatch(text);

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<LegalSettings> loadSettings() async {
    try {
      final row = await _db
          .from('app_legal_settings')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return const LegalSettings();
      String s(String k) => (row[k] ?? '').toString().trim();
      final months = int.tryParse('${row['gps_retention_months'] ?? ''}');
      return LegalSettings(
        aziendaNome: s('azienda_nome'),
        gpsRetentionMonths:
            (months != null && months > 0) ? months : LegalConfig.gpsRetentionMonths,
        fornitore: {
          'FORNITORE_RAGIONE_SOCIALE': s('fornitore_ragione_sociale'),
          'FORNITORE_PIVA': s('fornitore_piva'),
          'FORNITORE_SEDE': s('fornitore_sede'),
          'FORNITORE_PEC': s('fornitore_pec'),
          'EMAIL_ASSISTENZA': s('email_assistenza'),
          'TERMINI_DATA': s('termini_data'),
          'FORNITORE_EMAIL': s('fornitore_email'),
          'NOTE_LEGALI_DATA': s('note_legali_data'),
        }..removeWhere((_, v) => v.isEmpty),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LegalDocumentsService.loadSettings: $e');
      return const LegalSettings();
    }
  }

  static Future<LegalDocument> loadPrivacy() async {
    try {
      final row = await _db
          .from('app_legal_documents')
          .select('title, content, version, published')
          .eq('doc_key', privacyKey)
          .eq('published', true)
          .maybeSingle();
      final content = (row?['content'] ?? '').toString().trim();
      if (row != null && content.isNotEmpty && !hasPlaceholders(content)) {
        return LegalDocument(
          title: (row['title'] ?? 'Informativa privacy').toString(),
          content: content,
          version: (row['version'] ?? '').toString(),
          available: true,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LegalDocumentsService.loadPrivacy: $e');
    }
    return const LegalDocument(
      title: 'Informativa privacy',
      content: neutralPrivacyMessage,
      version: '',
      available: false,
    );
  }

  static Future<Map<String, String>> _fornitoreValues() async {
    final settings = await loadSettings();
    return <String, String>{
      'FORNITORE_RAGIONE_SOCIALE': LegalConfig.fornitoreRagioneSociale,
      'FORNITORE_PIVA': LegalConfig.fornitorePiva,
      'FORNITORE_SEDE': LegalConfig.fornitoreSede,
      'FORNITORE_PEC': LegalConfig.fornitorePec,
      'FORNITORE_EMAIL': LegalConfig.fornitoreEmail,
      'EMAIL_ASSISTENZA': LegalConfig.emailAssistenza,
      'TERMINI_VERSIONE': LegalConfig.terminiVersione,
      'TERMINI_DATA': LegalConfig.terminiData,
      'NOTE_LEGALI_DATA': LegalConfig.noteLegaliData,
      ...settings.fornitore,
    };
  }

  static String _fill(String template, Map<String, String> values) {
    var text = template;
    values.forEach((k, v) {
      if (v.trim().isNotEmpty) text = text.replaceAll('{{$k}}', v.trim());
    });
    return text;
  }

  /// Note legali (documento 09) con i dati del fornitore.
  static Future<LegalDocument> loadNoteLegali() async {
    final text = _fill(_noteLegaliTemplate, await _fornitoreValues());
    final ok = !hasPlaceholders(text);
    return LegalDocument(
      title: 'Note legali',
      content: ok ? text : neutralNoteLegaliMessage,
      version: '',
      available: ok,
    );
  }

  static Future<LegalDocument> loadTerms() async {
    final settings = await loadSettings();
    final values = <String, String>{
      'FORNITORE_RAGIONE_SOCIALE': LegalConfig.fornitoreRagioneSociale,
      'FORNITORE_PIVA': LegalConfig.fornitorePiva,
      'FORNITORE_SEDE': LegalConfig.fornitoreSede,
      'FORNITORE_PEC': LegalConfig.fornitorePec,
      'EMAIL_ASSISTENZA': LegalConfig.emailAssistenza,
      'TERMINI_VERSIONE': LegalConfig.terminiVersione,
      'TERMINI_DATA': LegalConfig.terminiData,
      ...settings.fornitore,
    };
    var text = _termsTemplate;
    values.forEach((k, v) {
      if (v.trim().isNotEmpty) text = text.replaceAll('{{$k}}', v.trim());
    });
    final ok = !hasPlaceholders(text);
    return LegalDocument(
      title: "Termini d'uso",
      content: ok ? text : neutralTermsMessage,
      version: LegalConfig.terminiVersione,
      available: ok,
    );
  }

  /// Registra la presa visione (tabella `app_legal_acceptances`).
  static Future<bool> recordAcceptance(String docKey, String version) async {
    try {
      if (_db.auth.currentUser == null) return false;
      await _db.from('app_legal_acceptances').insert({
        'doc_key': docKey,
        'version': version,
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('LegalDocumentsService.recordAcceptance: $e');
      return false;
    }
  }

  /// Admin: salva/pubblica il testo dell'informativa completata dal cliente.
  static Future<void> savePrivacy({
    required String content,
    required String version,
    required bool publish,
  }) async {
    if (publish && hasPlaceholders(content)) {
      throw Exception(
        'Il testo contiene ancora parti da completare tra parentesi quadre: '
        'compilale prima di pubblicare.',
      );
    }
    await _db.from('app_legal_documents').upsert({
      'doc_key': privacyKey,
      'title': 'Informativa privacy',
      'content': content,
      'version': version,
      'published': publish,
    });
  }

  /// Testo admin corrente (anche non pubblicato), per l'editor.
  static Future<Map<String, dynamic>?> loadPrivacyDraft() async {
    try {
      return await _db
          .from('app_legal_documents')
          .select('content, version, published')
          .eq('doc_key', privacyKey)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }
}

/// Documento 03 (Legale/Documenti/03_Termini_d_uso.docx), con segnaposto
/// {{...}} sostituiti a runtime.
const String _termsTemplate = r'''Termini d'uso delle applicazioni GESTOPRO360 e GestoproOre
Testo per gli utenti finali (dipendenti, referenti e amministratori delle aziende clienti). Il rapporto commerciale tra GESTOPRO e l'azienda cliente è regolato dal Contratto SaaS e dai suoi allegati, che prevalgono su questi Termini in caso di contrasto.
1. Chi fornisce le app
Le applicazioni GESTOPRO360 e GestoproOre ("App") sono fornite da Alexandru Cibuc – {{FORNITORE_RAGIONE_SOCIALE}}, P.IVA {{FORNITORE_PIVA}}, sede {{FORNITORE_SEDE}}, PEC {{FORNITORE_PEC}} ("Fornitore"), all'azienda per cui Lei lavora o collabora ("Azienda").
2. Chi può usare le App
Le App sono servizi per imprese. Le usano solo le persone a cui l'Azienda ha creato un account. Il servizio non è rivolto ai consumatori; il Codice del Consumo non si applica al rapporto tra Fornitore e Azienda.
3. Account e credenziali
Le credenziali (password, passkey, codici OTP) sono personali e non vanno condivise.
La password deve avere almeno 10 caratteri con lettere e numeri. Può reimpostarla da solo con la funzione "Password dimenticata?": riceverà un link valido 60 minuti e utilizzabile una sola volta.
Se sospetta un accesso non autorizzato, cambi subito la password, controlli e revochi le passkey che non riconosce e avvisi l'Azienda.
L'Azienda assegna i ruoli e può sospendere o chiudere l'account.
4. Uso corretto
È vietato: usare le App per scopi diversi dal lavoro per l'Azienda; inserire dati falsi (ad esempio timbrature o posizioni alterate); accedere a dati di altri senza autorizzazione; tentare di aggirare le misure di sicurezza, decompilare o copiare il software; caricare file con virus o contenuti illeciti; inserire nelle App diagnosi o dati sanitari non richiesti.
5. Posizione, notifiche e firma
Alcune funzioni (timbratura, buoni pasto) leggono la posizione GPS solo nel momento dell'azione, previo permesso del telefono. Non c'è tracciamento continuo. Dettagli nell'informativa privacy dell'Azienda.
Le notifiche push si possono disattivare dalle impostazioni del telefono.
La firma dei documenti in app con codice OTP è una firma elettronica semplice (art. 25 Reg. UE 910/2014; art. 20 CAD): il suo valore in giudizio è valutato liberamente dal giudice.
6. Privacy
I dati dei dipendenti inseriti nelle App sono trattati dall'Azienda come titolare. Il Fornitore li tratta come responsabile, solo per erogare il servizio. L'informativa è disponibile nella voce "Privacy" delle App.
7. Proprietà del software
Il software, il marchio GESTOPRO360/GestoproOre, la grafica e la documentazione appartengono al Fornitore. All'utente è concesso solo l'uso personale e non trasferibile per conto dell'Azienda, per la durata del contratto con l'Azienda. I dati inseriti restano dell'Azienda.
8. Disponibilità del servizio
Il Fornitore si impegna a mantenere le App disponibili e sicure secondo il contratto con l'Azienda, ma possono esserci interruzioni per manutenzione, aggiornamenti o guasti di servizi di terzi. Le App possono cambiare per miglioramenti o motivi di sicurezza.
9. Responsabilità
Il Fornitore non risponde dei dati inseriti dagli utenti, dell'uso non conforme delle App o delle decisioni prese dall'Azienda sulla base dei dati. Restano ferme le responsabilità per dolo o colpa grave e quelle che la legge non permette di escludere.
10. Sospensione
L'Azienda o il Fornitore possono sospendere un account in caso di uso contrario a questi Termini o di rischio per la sicurezza.
11. Modifiche
Il Fornitore può aggiornare questi Termini; la nuova versione viene mostrata nelle App con la data. Le modifiche importanti vengono comunicate prima dell'entrata in vigore.
12. Legge e contatti
Si applica la legge italiana. Per domande sull'uso delle App si rivolga prima all'Azienda; per questioni tecniche: {{EMAIL_ASSISTENZA}}.
Versione {{TERMINI_VERSIONE}} – {{TERMINI_DATA}}''';

/// Documento 09 (Legale/Documenti/09_Note_legali.md).
const String _noteLegaliTemplate = r'''Note legali

Fornitore
Le applicazioni GESTOPRO360 e GestoproOre sono sviluppate e fornite da:
Alexandru Cibuc – {{FORNITORE_RAGIONE_SOCIALE}}
P.IVA: {{FORNITORE_PIVA}}
Sede: {{FORNITORE_SEDE}}
PEC: {{FORNITORE_PEC}}
E-mail: {{FORNITORE_EMAIL}}

Proprietà intellettuale
Il software GESTOPRO360 e GestoproOre (codice sorgente e oggetto, database, interfacce, grafica e documentazione) e i nomi "GESTOPRO360" e "GestoproOre" appartengono ad Alexandru Cibuc e sono protetti dalla legge sul diritto d'autore (L. 633/1941) e dalle norme sui segni distintivi. L'uso è consentito solo alle aziende clienti e ai loro utenti, nei limiti del contratto di licenza. È vietato copiare, modificare, decompilare, distribuire o cedere il software senza autorizzazione scritta, salvo i casi permessi dalla legge.

Documenti
- Informativa privacy: scheda «Informativa privacy» di questa sezione
- Termini d'uso: scheda «Termini d'uso» di questa sezione

Esclusione di responsabilità
Le app sono strumenti di gestione: i dati inseriti e le decisioni prese sulla base di essi sono responsabilità dell'azienda che le usa. Il fornitore cura la correttezza e la sicurezza del servizio, ma non garantisce che sia sempre privo di errori o interruzioni. Restano ferme le responsabilità che la legge non permette di escludere.

Legge applicabile
Si applica la legge italiana. Per i rapporti con le aziende clienti valgono il contratto di servizio e il foro in esso indicato.

Ultimo aggiornamento: {{NOTE_LEGALI_DATA}}
''';
