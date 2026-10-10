import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal_documents.dart';

/// Pagina "Privacy e termini" (audit legale A1).
/// [canEdit] = admin: può incollare/pubblicare l'informativa completata.
class PrivacyTerminiPage extends StatefulWidget {
  const PrivacyTerminiPage({super.key, this.canEdit = false, this.initialTab = 0});

  final bool canEdit;
  final int initialTab;

  static Future<void> open(BuildContext context,
      {bool canEdit = false, int initialTab = 0}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrivacyTerminiPage(canEdit: canEdit, initialTab: initialTab),
      ),
    );
  }

  @override
  State<PrivacyTerminiPage> createState() => _PrivacyTerminiPageState();
}

class _PrivacyTerminiPageState extends State<PrivacyTerminiPage> {
  late Future<List<LegalDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<LegalDocument>> _load() => Future.wait([
        LegalDocumentsService.loadPrivacy(),
        LegalDocumentsService.loadTerms(),
        LegalDocumentsService.loadNoteLegali(),
      ]);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Privacy e termini'),
          actions: [
            if (widget.canEdit)
              IconButton(
                tooltip: 'Modifica informativa (admin)',
                icon: const Icon(Icons.edit_note),
                onPressed: () async {
                  final changed = await showDialog<bool>(
                    context: context,
                    builder: (_) => const _PrivacyEditorDialog(),
                  );
                  if (changed == true) _reload();
                },
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Informativa privacy'),
              Tab(text: "Termini d'uso"),
              Tab(text: 'Note legali'),
            ],
          ),
        ),
        body: FutureBuilder<List<LegalDocument>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!;
            return TabBarView(
              children: [
                _DocView(doc: docs[0], docKey: LegalDocumentsService.privacyKey),
                _DocView(doc: docs[1], docKey: LegalDocumentsService.terminiKey),
                _DocView(doc: docs[2], docKey: 'note_legali', showAccept: false),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DocView extends StatefulWidget {
  const _DocView({
    required this.doc,
    required this.docKey,
    this.showAccept = true,
  });
  final LegalDocument doc;
  final bool showAccept;
  final String docKey;

  @override
  State<_DocView> createState() => _DocViewState();
}

class _DocViewState extends State<_DocView> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loggedIn = Supabase.instance.client.auth.currentUser != null;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.doc.available)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 12),
                    Expanded(child: Text(widget.doc.content)),
                  ],
                ),
              ),
            )
          else ...[
            Text(widget.doc.content,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
            if (widget.doc.version.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Versione ${widget.doc.version}',
                  style: theme.textTheme.bodySmall),
            ],
            if (loggedIn && widget.showAccept) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _accepted
                    ? null
                    : () async {
                        final ok = await LegalDocumentsService.recordAcceptance(
                            widget.docKey, widget.doc.version);
                        if (!mounted) return;
                        setState(() => _accepted = ok);
                        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Presa visione registrata.'
                              : 'Impossibile registrare la presa visione.'),
                        ));
                      },
                icon: const Icon(Icons.check),
                label: Text(_accepted ? 'Presa visione registrata' : 'Ho letto'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PrivacyEditorDialog extends StatefulWidget {
  const _PrivacyEditorDialog();

  @override
  State<_PrivacyEditorDialog> createState() => _PrivacyEditorDialogState();
}

class _PrivacyEditorDialogState extends State<_PrivacyEditorDialog> {
  final _text = TextEditingController();
  final _version = TextEditingController(text: '1.0');
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    LegalDocumentsService.loadPrivacyDraft().then((row) {
      if (!mounted) return;
      setState(() {
        _text.text = (row?['content'] ?? '').toString();
        final v = (row?['version'] ?? '').toString();
        if (v.isNotEmpty) _version.text = v;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _version.dispose();
    super.dispose();
  }

  Future<void> _save(bool publish) async {
    setState(() => _saving = true);
    try {
      await LegalDocumentsService.savePrivacy(
        content: _text.text.trim(),
        version: _version.text.trim(),
        publish: publish,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Informativa privacy dei dipendenti'),
      content: SizedBox(
        width: 720,
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Il titolare è l'azienda: incolla qui l'informativa "
                    'completata (nessuna parte tra [ ] da compilare). '
                    'Finché non è pubblicata, i dipendenti vedono un messaggio neutro.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _text.text = kInformativaPrivacyModello),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Inserisci il modello da completare'),
                    ),
                  ),
                  TextField(
                    controller: _version,
                    decoration: const InputDecoration(labelText: 'Versione'),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: TextField(
                      controller: _text,
                      maxLines: 18,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Testo informativa',
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        OutlinedButton(
          onPressed: _saving || _loading ? null : () => _save(false),
          child: const Text('Salva bozza'),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : () => _save(true),
          child: const Text('Pubblica'),
        ),
      ],
    );
  }
}

/// Modello (documento 01) SOLO per l'editor admin: non viene mai mostrato ai
/// dipendenti finché contiene segnaposto.
const String kInformativaPrivacyModello = r'''Informativa sul trattamento dei dati personali dei lavoratori e degli utenti delle applicazioni GESTOPRO360 e GestoproOre
(artt. 13 e 14 Reg. UE 2016/679 – "GDPR" – e art. 4, comma 3, L. 300/1970 – Statuto dei Lavoratori)
Modello da completare a cura dell'azienda cliente (Titolare del trattamento). Le parti tra [ ] vanno compilate o eliminate. Il fornitore del software non è titolare di questi dati: questo testo è un fac-simile e va adattato dall'azienda, possibilmente con il proprio consulente privacy/del lavoro.
1. Titolare del trattamento
Il Titolare del trattamento è [RAGIONE SOCIALE DEL CLIENTE], con sede in [SEDE DEL CLIENTE], P.IVA [P.IVA DEL CLIENTE], PEC [PEC DEL CLIENTE], e-mail privacy [E-MAIL PRIVACY DEL CLIENTE] (di seguito "Azienda").
Responsabile della protezione dei dati (DPO), se nominato: [NOME E CONTATTI DPO / "non nominato"] [DA COMPLETARE].
2. Responsabile del trattamento
L'Azienda utilizza le applicazioni GESTOPRO360 e/o GestoproOre fornite da Alexandru Cibuc – [RAGIONE SOCIALE], P.IVA [P.IVA], sede [SEDE], PEC [PEC], nominato Responsabile del trattamento ai sensi dell'art. 28 GDPR (Allegato C del contratto di servizio). Il Responsabile tratta i dati solo per erogare il servizio e secondo le istruzioni dell'Azienda. L'elenco dei sub-responsabili è riportato al punto 7.
3. Quali dati trattiamo
In base ai moduli attivati dall'Azienda [DA COMPLETARE: eliminare le voci non usate]:
dati anagrafici e di contatto: nome, cognome, e-mail, telefono, mansione, qualifica, ruolo nell'app, commessa/cantiere, eventuale fotografia del badge;
dati di accesso: credenziali, passkey, log di accesso e di attività, token del dispositivo per le notifiche push;
dati sull'attività lavorativa: ore lavorate e timbrature, rapportini mensili, costi di commessa, trasferte, viaggi (treno/aereo), pernottamenti, distacchi presso altre sedi, scadenze contrattuali;
assenze, ferie e permessi, comprese le assenze per malattia (senza diagnosi);
formazione, attestati, DPI e vestiario (comprese le taglie);
visite mediche: date, scadenze ed eventuale giudizio di idoneità alla mansione. Il giudizio di idoneità è un dato relativo alla salute (art. 9 GDPR). L'app non deve contenere diagnosi o cartelle sanitarie, che restano al medico competente;
note spese e rimborsi, con scontrini e giustificativi;
buoni pasto;
documenti consegnati o firmati in app (firma elettronica semplice con codice OTP) e relative evidenze;
posizione geografica (GPS), solo nei momenti descritti al punto 5.
I dati sono forniti da Lei o inseriti dall'Azienda (ufficio personale, direttori tecnici, amministratori). Alcuni dati possono provenire da terzi [DA COMPLETARE: es. medico competente, enti di formazione, consulente del lavoro] (art. 14 GDPR).
4. Finalità e basi giuridiche
Non si usano i dati per decisioni completamente automatizzate né per profilazione (art. 22 GDPR).
5. Geolocalizzazione e Statuto dei Lavoratori (art. 4 L. 300/1970)
La posizione GPS del telefono viene letta solo nel momento in cui Lei esegue un'azione precisa: la timbratura (GestoproOre) o la registrazione di un buono pasto (GESTOPRO360) [DA COMPLETARE: altre azioni, se attivate].
Non c'è alcun tracciamento continuo e la posizione non viene letta in background né quando l'app è chiusa.
Viene salvata la posizione (latitudine e longitudine) insieme a data e ora dell'azione. Possono vederla solo [DA COMPLETARE: ruoli autorizzati, es. amministratore generale, ufficio personale].
Il permesso di localizzazione viene chiesto dal telefono e si può revocare dalle impostazioni; in tal caso [DA COMPLETARE: cosa succede – es. timbratura senza posizione / timbratura non possibile].
Lo strumento può consentire indirettamente un controllo a distanza. L'Azienda lo usa solo per esigenze organizzative e produttive, di sicurezza del lavoro e di tutela del patrimonio, [DA COMPLETARE: "in base all'accordo sindacale del ___" / "in base all'autorizzazione dell'Ispettorato del Lavoro n. ___ del ___" / "senza accordo perché strumento utilizzato per rendere la prestazione" – da valutare con il consulente del lavoro].
I dati raccolti possono essere usati a tutti i fini connessi al rapporto di lavoro solo perché Lei ha ricevuto questa informativa (art. 4, comma 3, Statuto) e nel rispetto del GDPR. L'uso per fini disciplinari è [DA COMPLETARE: previsto/escluso].
La posizione GPS è conservata per [DA COMPLETARE: es. 12 mesi], poi cancellata.
6. Chi può vedere i dati
Il personale dell'Azienda autorizzato secondo il proprio ruolo nell'app (amministratori, direttore tecnico e assistenti, ufficio, UQSA, logistica, caposquadra), ognuno solo per le sezioni di sua competenza;
il Responsabile del trattamento (punto 2) e i suoi sub-responsabili (punto 7);
ristoranti convenzionati, solo per i dati necessari al buono pasto [DA COMPLETARE: verificare];
consulente del lavoro, medico competente, enti di formazione, strutture ricettive e vettori per le prenotazioni, enti pubblici quando richiesto dalla legge [DA COMPLETARE].
I dati non sono diffusi.
7. Fornitori tecnici e trasferimenti fuori dall'UE
Nella versione cloud standard i dati sono ospitati su Supabase nell'Unione europea (Irlanda, regione eu-west-1). Gli altri fornitori tecnici usati dal Responsabile sono:
Cloudflare, Inc. – hosting del sito e della web app (Cloudflare Pages);
Resend – invio di e-mail di servizio (es. recupero password, firma documenti); Supabase come servizio e-mail di riserva;
Google (Firebase Cloud Messaging) – invio delle notifiche push (riceve il token del dispositivo e il testo della notifica);
Google Maps – visualizzazione delle mappe (riceve l'indirizzo IP del dispositivo).
Alcuni di questi fornitori hanno sede negli Stati Uniti. I trasferimenti avvengono sulla base della decisione di adeguatezza EU-U.S. Data Privacy Framework per i soggetti certificati o delle Clausole Contrattuali Standard (art. 46 GDPR).
[DA COMPLETARE: se l'Azienda usa la versione installata sul proprio server ("in sede"), indicare che il database è sul server dell'Azienda in [LUOGO] e togliere i fornitori non usati.]
8. Per quanto tempo
[DA COMPLETARE dall'Azienda; valori indicativi]
9. Sicurezza
L'accesso avviene con credenziali personali (password e/o passkey). I dati sono trasmessi cifrati (HTTPS), con permessi per ruolo e spazi file privati. I dati sanitari sono visibili solo a Lei e ai ruoli abilitati.
10. I Suoi diritti
Può chiedere all'Azienda accesso, rettifica, cancellazione, limitazione, portabilità e opporsi al trattamento basato sul legittimo interesse (artt. 15-22 GDPR), scrivendo a [E-MAIL PRIVACY DEL CLIENTE]. Ha diritto di proporre reclamo al Garante per la protezione dei dati personali (www.garanteprivacy.it).
11. Obbligatorietà
Il conferimento dei dati necessari al rapporto di lavoro è obbligatorio: senza di essi non è possibile gestire presenze, retribuzione e sicurezza. [DA COMPLETARE: indicare i dati facoltativi, es. foto del badge.]
Data e versione dell'informativa: [DATA] – versione [1.0]
Per presa visione (anche con conferma nell'app): ____________________
Finalità | Base giuridica
Gestione del rapporto di lavoro: presenze, ore, rapportini, assenze, ferie, permessi, trasferte, pernottamenti, rimborsi, buoni pasto, distacchi | Esecuzione del contratto di lavoro (art. 6.1.b GDPR); obblighi di legge e di contratto collettivo (art. 6.1.c)
Sicurezza sul lavoro: formazione, DPI, scadenze delle visite e idoneità (D.Lgs. 81/2008) | Obbligo di legge (art. 6.1.c); per i dati sanitari art. 9.2.b e 9.2.h GDPR
Verifica del luogo della timbratura o della registrazione del buono pasto | Legittimo interesse organizzativo e di tutela del patrimonio (art. 6.1.f), nei limiti dell'art. 4 Statuto dei Lavoratori; [DA COMPLETARE: estremi dell'accordo sindacale o dell'autorizzazione INL, se richiesti]
Firma e consegna di documenti | Esecuzione del contratto e obblighi di legge (art. 6.1.b e c)
Costi di commessa e organizzazione del lavoro | Legittimo interesse (art. 6.1.f)
Sicurezza informatica dell'app (log, autenticazione) | Legittimo interesse e obbligo di sicurezza (art. 6.1.f e art. 32 GDPR)
Notifiche push e comunicazioni di servizio | Esecuzione del contratto (art. 6.1.b); le notifiche si possono disattivare dalle impostazioni del telefono
Difesa in giudizio | Legittimo interesse (art. 6.1.f; art. 9.2.f per dati sanitari)
Dati | Conservazione
Dati di presenza, ore, rapportini e rimborsi | [es. 10 anni dalla registrazione, per obblighi fiscali e contributivi]
Dati sulla formazione e sui DPI | [es. per la durata del rapporto + 10 anni]
Scadenze visite e giudizi di idoneità | [es. per la durata del rapporto + ___]
Posizione GPS | [es. 12 mesi]
Log di attività dell'app | 14 giorni
Chat interna | 7 giorni
Backup tecnici | 60 giorni
Account dopo la cessazione del rapporto | [es. disattivato alla cessazione e cancellato dopo ___]''';
