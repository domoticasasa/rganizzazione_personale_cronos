import 'package:flutter/material.dart';

part 'hub_icon_catalog_generated.dart';

/// Voce libreria icone con etichette/parole chiave in italiano.
class HubIconCatalogEntry {
  const HubIconCatalogEntry({
    required this.icon,
    required this.labelIt,
    this.keywordsIt = const <String>[],
  });

  final IconData icon;
  final String labelIt;
  final List<String> keywordsIt;

  int get codepoint => icon.codePoint;

  bool matchesQuery(String query) {
    final q = _norm(query);
    if (q.isEmpty) return true;
    if (_norm(labelIt).contains(q)) return true;
    for (final k in keywordsIt) {
      if (_norm(k).contains(q)) return true;
    }
    return false;
  }

  static String _norm(String s) =>
      s.toLowerCase().trim().replaceAll('à', 'a').replaceAll('è', 'e').replaceAll('é', 'e').replaceAll('ì', 'i').replaceAll('ò', 'o').replaceAll('ù', 'u');
}

/// Catalogo icone Material per hub (ricerca in italiano).
abstract final class HubIconCatalog {
  HubIconCatalog._();

  /// Etichette italiane curate (hanno priorità sul catalogo generato).
  static const List<HubIconCatalogEntry> _curated = <HubIconCatalogEntry>[
    HubIconCatalogEntry(
      icon: Icons.train_outlined,
      labelIt: 'Treno',
      keywordsIt: ['treni', 'ferrovia', 'rfi', 'trasporto'],
    ),
    HubIconCatalogEntry(
      icon: Icons.flight_outlined,
      labelIt: 'Aereo',
      keywordsIt: ['aerei', 'volo', 'viaggio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.bed_outlined,
      labelIt: 'Pernottamento',
      keywordsIt: ['pernottamenti', 'hotel', 'notte', 'camera'],
    ),
    HubIconCatalogEntry(
      icon: Icons.local_shipping_outlined,
      labelIt: 'Logistica',
      keywordsIt: ['camion', 'spedizione', 'magazzino'],
    ),
    HubIconCatalogEntry(
      icon: Icons.school_outlined,
      labelIt: 'Formazione',
      keywordsIt: ['corso', 'corsi', 'scuola', 'studio', 'rfi'],
    ),
    HubIconCatalogEntry(
      icon: Icons.menu_book_outlined,
      labelIt: 'Manuale',
      keywordsIt: ['libro', 'documento', 'dlgs', '81'],
    ),
    HubIconCatalogEntry(
      icon: Icons.calendar_month_outlined,
      labelIt: 'Calendario',
      keywordsIt: ['programmazione', 'data', 'pianificazione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.event_available_outlined,
      labelIt: 'Appuntamento',
      keywordsIt: ['evento', 'prenotazione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.medical_services_outlined,
      labelIt: 'Visita medica',
      keywordsIt: ['salute', 'medico', 'ambulatorio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.warning_amber_outlined,
      labelIt: 'Avviso',
      keywordsIt: ['alert', 'scadenza', 'scadenze', 'attenzione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.settings_outlined,
      labelIt: 'Impostazioni',
      keywordsIt: ['configurazione', 'opzioni', 'ingranaggio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.tune_outlined,
      labelIt: 'Regolazione',
      keywordsIt: ['slider', 'parametri'],
    ),
    HubIconCatalogEntry(
      icon: Icons.dashboard_outlined,
      labelIt: 'Dashboard',
      keywordsIt: ['pannello', 'riepilogo', 'admin'],
    ),
    HubIconCatalogEntry(
      icon: Icons.grid_view_outlined,
      labelIt: 'Griglia',
      keywordsIt: ['matrice', 'hub', 'pulsanti'],
    ),
    HubIconCatalogEntry(
      icon: Icons.people_outlined,
      labelIt: 'Persone',
      keywordsIt: ['dipendenti', 'team', 'gruppo', 'personale'],
    ),
    HubIconCatalogEntry(
      icon: Icons.person_outlined,
      labelIt: 'Persona',
      keywordsIt: ['utente', 'profilo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.badge_outlined,
      labelIt: 'Badge',
      keywordsIt: ['tesserino', 'identificativo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.verified_user_outlined,
      labelIt: 'Sicurezza',
      keywordsIt: ['protezione', 'uqsa', 'dpi'],
    ),
    HubIconCatalogEntry(
      icon: Icons.construction_outlined,
      labelIt: 'Cantiere',
      keywordsIt: ['lavori', 'manutenzione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.engineering_outlined,
      labelIt: 'Ingegneria',
      keywordsIt: ['tecnico', 'tecnica'],
    ),
    HubIconCatalogEntry(
      icon: Icons.inventory_2_outlined,
      labelIt: 'Inventario',
      keywordsIt: ['magazzino', 'stock', 'dpi'],
    ),
    HubIconCatalogEntry(
      icon: Icons.checklist_outlined,
      labelIt: 'Checklist',
      keywordsIt: ['lista', 'controllo', 'verifica'],
    ),
    HubIconCatalogEntry(
      icon: Icons.assignment_outlined,
      labelIt: 'Compito',
      keywordsIt: ['documento', 'pratica'],
    ),
    HubIconCatalogEntry(
      icon: Icons.description_outlined,
      labelIt: 'Documento',
      keywordsIt: ['file', 'pdf', 'foglio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.folder_outlined,
      labelIt: 'Cartella',
      keywordsIt: ['archivio', 'directory'],
    ),
    HubIconCatalogEntry(
      icon: Icons.cloud_outlined,
      labelIt: 'Cloud',
      keywordsIt: ['nuvola', 'online', 'sync'],
    ),
    HubIconCatalogEntry(
      icon: Icons.email_outlined,
      labelIt: 'Email',
      keywordsIt: ['posta', 'messaggio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.notifications_outlined,
      labelIt: 'Notifiche',
      keywordsIt: ['campanella', 'avvisi'],
    ),
    HubIconCatalogEntry(
      icon: Icons.map_outlined,
      labelIt: 'Mappa',
      keywordsIt: ['geografia', 'luogo', 'gps'],
    ),
    HubIconCatalogEntry(
      icon: Icons.place_outlined,
      labelIt: 'Posizione',
      keywordsIt: ['pin', 'sede', 'indirizzo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.hotel_outlined,
      labelIt: 'Hotel',
      keywordsIt: ['struttura', 'alloggio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.restaurant_outlined,
      labelIt: 'Ristorante',
      keywordsIt: ['pasto', 'mensa'],
    ),
    HubIconCatalogEntry(
      icon: Icons.attach_money_outlined,
      labelIt: 'Denaro',
      keywordsIt: ['euro', 'costo', 'budget'],
    ),
    HubIconCatalogEntry(
      icon: Icons.bar_chart_outlined,
      labelIt: 'Grafico',
      keywordsIt: ['statistica', 'report', 'analisi'],
    ),
    HubIconCatalogEntry(
      icon: Icons.insights_outlined,
      labelIt: 'Insight',
      keywordsIt: ['kpi', 'andamento'],
    ),
    HubIconCatalogEntry(
      icon: Icons.search_outlined,
      labelIt: 'Cerca',
      keywordsIt: ['ricerca', 'lente'],
    ),
    HubIconCatalogEntry(
      icon: Icons.add_circle_outline,
      labelIt: 'Aggiungi',
      keywordsIt: ['nuovo', 'piu', 'crea'],
    ),
    HubIconCatalogEntry(
      icon: Icons.edit_outlined,
      labelIt: 'Modifica',
      keywordsIt: ['penna', 'cambia'],
    ),
    HubIconCatalogEntry(
      icon: Icons.delete_outline,
      labelIt: 'Elimina',
      keywordsIt: ['cestino', 'rimuovi'],
    ),
    HubIconCatalogEntry(
      icon: Icons.save_outlined,
      labelIt: 'Salva',
      keywordsIt: ['memorizza', 'disco'],
    ),
    HubIconCatalogEntry(
      icon: Icons.print_outlined,
      labelIt: 'Stampa',
      keywordsIt: ['printer', 'stampa'],
    ),
    HubIconCatalogEntry(
      icon: Icons.download_outlined,
      labelIt: 'Scarica',
      keywordsIt: ['export', 'esporta'],
    ),
    HubIconCatalogEntry(
      icon: Icons.upload_outlined,
      labelIt: 'Carica',
      keywordsIt: ['import', 'importa'],
    ),
    HubIconCatalogEntry(
      icon: Icons.lock_outlined,
      labelIt: 'Blocco',
      keywordsIt: ['lucchetto', 'privato'],
    ),
    HubIconCatalogEntry(
      icon: Icons.key_outlined,
      labelIt: 'Chiave',
      keywordsIt: ['accesso', 'login'],
    ),
    HubIconCatalogEntry(
      icon: Icons.help_outline,
      labelIt: 'Aiuto',
      keywordsIt: ['supporto', 'domanda'],
    ),
    HubIconCatalogEntry(
      icon: Icons.info_outline,
      labelIt: 'Informazioni',
      keywordsIt: ['info', 'dettaglio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.star_outline,
      labelIt: 'Preferito',
      keywordsIt: ['stella', 'importante'],
    ),
    HubIconCatalogEntry(
      icon: Icons.favorite_outline,
      labelIt: 'Cuore',
      keywordsIt: ['like', 'salute'],
    ),
    HubIconCatalogEntry(
      icon: Icons.home_outlined,
      labelIt: 'Home',
      keywordsIt: ['casa', 'principale'],
    ),
    HubIconCatalogEntry(
      icon: Icons.business_outlined,
      labelIt: 'Azienda',
      keywordsIt: ['ufficio', 'sede', 'impresa'],
    ),
    HubIconCatalogEntry(
      icon: Icons.apartment_outlined,
      labelIt: 'Edificio',
      keywordsIt: ['palazzo', 'struttura'],
    ),
    HubIconCatalogEntry(
      icon: Icons.directions_bus_outlined,
      labelIt: 'Autobus',
      keywordsIt: ['bus', 'trasporto'],
    ),
    HubIconCatalogEntry(
      icon: Icons.directions_car_outlined,
      labelIt: 'Auto',
      keywordsIt: ['macchina', 'veicolo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.pedal_bike_outlined,
      labelIt: 'Bici',
      keywordsIt: ['bicicletta', 'ciclo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.eco_outlined,
      labelIt: 'Ecologia',
      keywordsIt: ['verde', 'ambiente', 'foglia'],
    ),
    HubIconCatalogEntry(
      icon: Icons.build_outlined,
      labelIt: 'Attrezzi',
      keywordsIt: ['chiave inglese', 'riparazione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.handyman_outlined,
      labelIt: 'Manutenzione',
      keywordsIt: ['tecnico', 'intervento'],
    ),
    HubIconCatalogEntry(
      icon: Icons.schedule_outlined,
      labelIt: 'Orario',
      keywordsIt: ['orologio', 'tempo', 'turno'],
    ),
    HubIconCatalogEntry(
      icon: Icons.timer_outlined,
      labelIt: 'Timer',
      keywordsIt: ['conto', 'scadenza'],
    ),
    HubIconCatalogEntry(
      icon: Icons.account_tree_outlined,
      labelIt: 'Organigramma',
      keywordsIt: ['struttura', 'albero'],
    ),
    HubIconCatalogEntry(
      icon: Icons.hub_outlined,
      labelIt: 'Hub',
      keywordsIt: ['centro', 'nodo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.widgets_outlined,
      labelIt: 'Widget',
      keywordsIt: ['modulo', 'componente'],
    ),
    HubIconCatalogEntry(
      icon: Icons.palette_outlined,
      labelIt: 'Palette',
      keywordsIt: ['colore', 'stile', 'aspetto'],
    ),
    HubIconCatalogEntry(
      icon: Icons.photo_outlined,
      labelIt: 'Foto',
      keywordsIt: ['immagine', 'galleria'],
    ),
    HubIconCatalogEntry(
      icon: Icons.videocam_outlined,
      labelIt: 'Video',
      keywordsIt: ['camera', 'registrazione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.phone_outlined,
      labelIt: 'Telefono',
      keywordsIt: ['chiamata', 'contatto'],
    ),
    HubIconCatalogEntry(
      icon: Icons.chat_outlined,
      labelIt: 'Chat',
      keywordsIt: ['messaggio', 'discussione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.groups_outlined,
      labelIt: 'Gruppi',
      keywordsIt: ['squadra', 'team'],
    ),
    HubIconCatalogEntry(
      icon: Icons.work_outline,
      labelIt: 'Lavoro',
      keywordsIt: ['ufficio', 'mansione', 'job'],
    ),
    HubIconCatalogEntry(
      icon: Icons.gavel_outlined,
      labelIt: 'Normativa',
      keywordsIt: ['legge', 'dlgs', 'compliance'],
    ),
    HubIconCatalogEntry(
      icon: Icons.health_and_safety_outlined,
      labelIt: 'Salute e sicurezza',
      keywordsIt: ['ssl', 'sicurezza sul lavoro'],
    ),
    HubIconCatalogEntry(
      icon: Icons.local_hospital_outlined,
      labelIt: 'Ospedale',
      keywordsIt: ['clinica', 'pronto soccorso'],
    ),
    HubIconCatalogEntry(
      icon: Icons.science_outlined,
      labelIt: 'Scienza',
      keywordsIt: ['laboratorio', 'prova'],
    ),
    HubIconCatalogEntry(
      icon: Icons.biotech_outlined,
      labelIt: 'Biotech',
      keywordsIt: ['dna', 'ricerca'],
    ),
    HubIconCatalogEntry(
      icon: Icons.pets_outlined,
      labelIt: 'Animali',
      keywordsIt: ['pet'],
    ),
    HubIconCatalogEntry(
      icon: Icons.sports_soccer_outlined,
      labelIt: 'Sport',
      keywordsIt: ['pallone', 'calcio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.beach_access_outlined,
      labelIt: 'Vacanza',
      keywordsIt: ['mare', 'ferie', 'ombrellone'],
    ),
    HubIconCatalogEntry(
      icon: Icons.luggage_outlined,
      labelIt: 'Valigia',
      keywordsIt: ['viaggio', 'bagaglio'],
    ),
    HubIconCatalogEntry(
      icon: Icons.receipt_long_outlined,
      labelIt: 'Ricevuta',
      keywordsIt: ['fattura', 'contabilita'],
    ),
    HubIconCatalogEntry(
      icon: Icons.credit_card_outlined,
      labelIt: 'Carta',
      keywordsIt: ['pagamento', 'carta credito'],
    ),
    HubIconCatalogEntry(
      icon: Icons.qr_code_outlined,
      labelIt: 'QR code',
      keywordsIt: ['codice', 'scanner'],
    ),
    HubIconCatalogEntry(
      icon: Icons.link_outlined,
      labelIt: 'Link',
      keywordsIt: ['collegamento', 'url'],
    ),
    HubIconCatalogEntry(
      icon: Icons.language_outlined,
      labelIt: 'Web',
      keywordsIt: ['internet', 'mondo', 'sito'],
    ),
    HubIconCatalogEntry(
      icon: Icons.translate_outlined,
      labelIt: 'Traduzione',
      keywordsIt: ['lingua', 'italiano'],
    ),
    HubIconCatalogEntry(
      icon: Icons.flag_outlined,
      labelIt: 'Bandiera',
      keywordsIt: ['obiettivo', 'meta'],
    ),
    HubIconCatalogEntry(
      icon: Icons.emoji_events_outlined,
      labelIt: 'Premio',
      keywordsIt: ['trofeo', 'vittoria'],
    ),
    HubIconCatalogEntry(
      icon: Icons.lightbulb_outline,
      labelIt: 'Idea',
      keywordsIt: ['lampadina', 'suggerimento'],
    ),
    HubIconCatalogEntry(
      icon: Icons.bolt_outlined,
      labelIt: 'Energia',
      keywordsIt: ['fulmine', 'elettricita'],
    ),
    HubIconCatalogEntry(
      icon: Icons.water_drop_outlined,
      labelIt: 'Acqua',
      keywordsIt: ['goccia', 'liquido'],
    ),
    HubIconCatalogEntry(
      icon: Icons.thermostat_outlined,
      labelIt: 'Temperatura',
      keywordsIt: ['clima', 'caldo', 'freddo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.railway_alert_outlined,
      labelIt: 'Allerta ferrovia',
      keywordsIt: ['binario', 'segnale'],
    ),
    HubIconCatalogEntry(
      icon: Icons.track_changes_outlined,
      labelIt: 'Tracciamento',
      keywordsIt: ['obiettivo', 'target'],
    ),
    HubIconCatalogEntry(
      icon: Icons.fact_check_outlined,
      labelIt: 'Verifica',
      keywordsIt: ['controllo', 'approvazione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.rule_folder_outlined,
      labelIt: 'Regole',
      keywordsIt: ['policy', 'norme'],
    ),
    HubIconCatalogEntry(
      icon: Icons.admin_panel_settings_outlined,
      labelIt: 'Admin',
      keywordsIt: ['amministratore', 'gestione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.manage_accounts_outlined,
      labelIt: 'Gestione account',
      keywordsIt: ['utenti', 'ruoli'],
    ),
    HubIconCatalogEntry(
      icon: Icons.support_agent_outlined,
      labelIt: 'Assistenza',
      keywordsIt: ['help desk', 'call center'],
    ),
    HubIconCatalogEntry(
      icon: Icons.headset_mic_outlined,
      labelIt: 'Supporto',
      keywordsIt: ['cuffie', 'microfono'],
    ),
    HubIconCatalogEntry(
      icon: Icons.campaign_outlined,
      labelIt: 'Annuncio',
      keywordsIt: ['megafono', 'comunicazione'],
    ),
    HubIconCatalogEntry(
      icon: Icons.newspaper_outlined,
      labelIt: 'Notizie',
      keywordsIt: ['giornale', 'news'],
    ),
    HubIconCatalogEntry(
      icon: Icons.bookmark_outline,
      labelIt: 'Segnalibro',
      keywordsIt: ['salva', 'preferito'],
    ),
    HubIconCatalogEntry(
      icon: Icons.archive_outlined,
      labelIt: 'Archivio',
      keywordsIt: ['storico', 'scatola'],
    ),
    HubIconCatalogEntry(
      icon: Icons.restore_outlined,
      labelIt: 'Ripristina',
      keywordsIt: ['undo', 'annulla'],
    ),
    HubIconCatalogEntry(
      icon: Icons.refresh_outlined,
      labelIt: 'Aggiorna',
      keywordsIt: ['reload', 'ricarica'],
    ),
    HubIconCatalogEntry(
      icon: Icons.sync_outlined,
      labelIt: 'Sincronizza',
      keywordsIt: ['sync', 'allinea'],
    ),
    HubIconCatalogEntry(
      icon: Icons.visibility_outlined,
      labelIt: 'Visualizza',
      keywordsIt: ['occhio', 'anteprima'],
    ),
    HubIconCatalogEntry(
      icon: Icons.visibility_off_outlined,
      labelIt: 'Nascondi',
      keywordsIt: ['occhio chiuso', 'privato'],
    ),
    HubIconCatalogEntry(
      icon: Icons.block_outlined,
      labelIt: 'Blocca voce',
      keywordsIt: ['vietato', 'stop'],
    ),
    HubIconCatalogEntry(
      icon: Icons.check_circle_outline,
      labelIt: 'OK',
      keywordsIt: ['spunta', 'completato', 'successo'],
    ),
    HubIconCatalogEntry(
      icon: Icons.cancel_outlined,
      labelIt: 'Annulla',
      keywordsIt: ['chiudi', 'errore'],
    ),
    HubIconCatalogEntry(
      icon: Icons.more_horiz,
      labelIt: 'Altro',
      keywordsIt: ['menu', 'opzioni'],
    ),
  ];

  static List<HubIconCatalogEntry>? _allCache;
  static Map<int, HubIconCatalogEntry>? _byCodepointCache;

  /// Tutte le icone Material outlined (~2200) + etichette curate in italiano.
  static List<HubIconCatalogEntry> get all {
    if (_allCache != null) return _allCache!;
    final byCp = <int, HubIconCatalogEntry>{};
    for (final e in _kGeneratedIconCatalog) {
      byCp[e.codepoint] = e;
    }
    for (final e in _curated) {
      byCp[e.codepoint] = e;
    }
    final merged = byCp.values.toList(growable: false)
      ..sort((a, b) => a.labelIt.toLowerCase().compareTo(b.labelIt.toLowerCase()));
    _allCache = merged;
    _byCodepointCache = byCp;
    return merged;
  }

  static Map<int, HubIconCatalogEntry> get _byCodepoint {
    all; // popola cache
    return _byCodepointCache!;
  }

  static List<HubIconCatalogEntry> search(String query) {
    return all.where((e) => e.matchesQuery(query)).toList(growable: false);
  }

  static HubIconCatalogEntry? byCodepoint(int? codepoint) {
    if (codepoint == null) return null;
    return _byCodepoint[codepoint];
  }

  static IconData iconFromCodepoint(int? codepoint, IconData fallback) {
    if (codepoint == null) return fallback;
    final entry = byCodepoint(codepoint);
    // Solo icone const dal catalogo: IconData(codepoint) a runtime rompe
    // il tree-shake delle font Material su build web release.
    return entry?.icon ?? fallback;
  }
}
