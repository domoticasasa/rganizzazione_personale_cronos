import 'dart:io';

/// Genera [lib/hub/hub_icon_catalog_generated.dart] dalle icone Material del SDK Flutter.
///
/// Uso: dart run tool/generate_hub_icon_catalog.dart
void main() {
  final iconsPath = _findIconsDart();
  if (iconsPath == null) {
    stderr.writeln(
      'Impossibile trovare icons.dart del SDK Flutter.\n'
      'Imposta FLUTTER_ROOT oppure installa Flutter in C:\\src\\flutter',
    );
    exit(1);
  }

  final content = File(iconsPath).readAsStringSync();
  final re = RegExp(
    r"static const IconData (\w+) = IconData\((0x[0-9a-fA-F]+), fontFamily: 'MaterialIcons'\);",
  );

  final allNames = <String>{};
  final outlined = <String>[];
  final codepoints = <String, int>{};

  for (final m in re.allMatches(content)) {
    final name = m.group(1)!;
    final cp = int.parse(m.group(2)!);
    allNames.add(name);
    codepoints[name] = cp;
    if (name.endsWith('_outlined')) {
      outlined.add(name);
    }
  }

  outlined.sort();

  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE â€” NON MODIFICARE A MANO.')
    ..writeln('// Rigenera con: dart run tool/generate_hub_icon_catalog.dart')
    ..writeln('// Icone Material *_outlined: ${outlined.length}')
    ..writeln("part of 'hub_icon_catalog.dart';")
    ..writeln()
    ..writeln('const List<HubIconCatalogEntry> _kGeneratedIconCatalog = <HubIconCatalogEntry>[');

  for (final name in outlined) {
    final cp = codepoints[name]!;
    final label = _labelIt(name);
    final keywords = _keywords(name, label);
    buffer.writeln(
      '  HubIconCatalogEntry('
      'icon: Icons.$name, '
      'labelIt: ${_dq(label)}, '
      'keywordsIt: <String>[${_keywordsDart(keywords)}],'
      '),',
    );
    // ignore cp unused - used implicitly via Icons.$name
    if (cp == 0) buffer.write('');
  }

  buffer.writeln('];');

  final out = File('lib/hub/hub_icon_catalog_generated.dart');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(buffer.toString());

  stdout.writeln('Scritto ${out.path} (${outlined.length} icone outlined).');
}

String? _findIconsDart() {
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] != null)
      '${Platform.environment['FLUTTER_ROOT']}/packages/flutter/lib/src/material/icons.dart',
    r'C:\src\flutter\packages\flutter\lib\src\material\icons.dart',
    r'/usr/local/flutter/packages/flutter/lib/src/material/icons.dart',
    r'/opt/flutter/packages/flutter/lib/src/material/icons.dart',
  ];

  for (final p in candidates) {
    final f = File(p.replaceAll('/', Platform.pathSeparator));
    if (f.existsSync()) return f.path;
  }

  try {
    final which = Platform.isWindows ? 'where' : 'which';
    final r = Process.runSync(which, ['flutter']);
    if (r.exitCode == 0) {
      final bin = (r.stdout as String).trim().split('\n').first.trim();
      final sdk = File(bin).parent.parent.path;
      final f = File(
        '$sdk/packages/flutter/lib/src/material/icons.dart'.replaceAll(
          '/',
          Platform.pathSeparator,
        ),
      );
      if (f.existsSync()) return f.path;
    }
  } catch (_) {}

  return null;
}

String _dq(String s) => "'${s.replaceAll("'", r"\'")}'";

String _keywordsDart(List<String> kws) =>
    kws.map(_dq).join(', ');

String _labelIt(String iconName) {
  final base = iconName.replaceAll(RegExp(r'_outlined$'), '');
  final parts = base.split('_');
  final translated = parts
      .map((p) => _segmentItalian[p] ?? _titleCase(p))
      .join(' ');
  return translated;
}

List<String> _keywords(String iconName, String labelIt) {
  final base = iconName.replaceAll(RegExp(r'_outlined$'), '');
  final parts = base.split('_').where((p) => p.isNotEmpty).toList();
  final kws = <String>{
    base,
    labelIt.toLowerCase(),
    ...parts,
    for (final p in parts)
      if (_segmentItalian.containsKey(p)) _segmentItalian[p]!.toLowerCase(),
  };
  return kws.toList()..sort();
}

String _titleCase(String s) {
  if (s.isEmpty) return s;
  if (s.length <= 3 && RegExp(r'^[a-z0-9]+$').hasMatch(s)) return s.toUpperCase();
  return s[0].toUpperCase() + s.substring(1);
}
/// Traduzioni per segmenti ricorrenti nei nomi icona Material.
const Map<String, String> _segmentItalian = {
  'access': 'Accesso',
  'account': 'Account',
  'add': 'Aggiungi',
  'admin': 'Admin',
  'alarm': 'Allarme',
  'alert': 'Alert',
  'analytics': 'Analisi',
  'api': 'API',
  'app': 'App',
  'archive': 'Archivio',
  'arrow': 'Freccia',
  'assignment': 'Compito',
  'attach': 'Allega',
  'auto': 'Auto',
  'av': 'AV',
  'backup': 'Backup',
  'badge': 'Badge',
  'balance': 'Saldo',
  'bar': 'Bar',
  'battery': 'Batteria',
  'beach': 'Spiaggia',
  'bed': 'Letto',
  'bike': 'Bici',
  'bluetooth': 'Bluetooth',
  'boat': 'Barca',
  'book': 'Libro',
  'bookmark': 'Segnalibro',
  'box': 'Box',
  'bug': 'Bug',
  'build': 'Costruzione',
  'bus': 'Bus',
  'business': 'Business',
  'cake': 'Torta',
  'calendar': 'Calendario',
  'call': 'Chiamata',
  'camera': 'Fotocamera',
  'campaign': 'Campagna',
  'cancel': 'Annulla',
  'car': 'Auto',
  'card': 'Carta',
  'cart': 'Carrello',
  'cast': 'Cast',
  'category': 'Categoria',
  'cell': 'Cellulare',
  'chat': 'Chat',
  'check': 'Controllo',
  'child': 'Bambino',
  'circle': 'Cerchio',
  'class': 'Classe',
  'clean': 'Pulizia',
  'clear': 'Cancella',
  'clock': 'Orologio',
  'close': 'Chiudi',
  'cloud': 'Cloud',
  'code': 'Codice',
  'coffee': 'CaffÃ¨',
  'color': 'Colore',
  'comment': 'Commento',
  'commute': 'Pendolarismo',
  'computer': 'Computer',
  'construction': 'Cantiere',
  'contact': 'Contatto',
  'content': 'Contenuto',
  'control': 'Controllo',
  'copy': 'Copia',
  'credit': 'Credito',
  'crisis': 'Crisi',
  'crop': 'Ritaglia',
  'cut': 'Taglia',
  'dark': 'Scuro',
  'data': 'Dati',
  'date': 'Data',
  'delete': 'Elimina',
  'delivery': 'Consegna',
  'design': 'Design',
  'desktop': 'Desktop',
  'device': 'Dispositivo',
  'dining': 'Sala pranzo',
  'direction': 'Direzione',
  'directions': 'Indicazioni',
  'disabled': 'Disabilitato',
  'dns': 'DNS',
  'do': 'Non',
  'document': 'Documento',
  'done': 'Fatto',
  'download': 'Download',
  'draft': 'Bozza',
  'drive': 'Drive',
  'edit': 'Modifica',
  'electric': 'Elettrico',
  'email': 'Email',
  'emergency': 'Emergenza',
  'emoji': 'Emoji',
  'energy': 'Energia',
  'engineering': 'Ingegneria',
  'error': 'Errore',
  'event': 'Evento',
  'exit': 'Uscita',
  'expand': 'Espandi',
  'explore': 'Esplora',
  'export': 'Esporta',
  'extension': 'Estensione',
  'face': 'Volto',
  'fact': 'Verifica',
  'family': 'Famiglia',
  'favorite': 'Preferito',
  'fax': 'Fax',
  'feed': 'Feed',
  'file': 'File',
  'filter': 'Filtro',
  'fire': 'Fuoco',
  'flag': 'Bandiera',
  'flight': 'Volo',
  'folder': 'Cartella',
  'font': 'Font',
  'food': 'Cibo',
  'forest': 'Foresta',
  'format': 'Formato',
  'forum': 'Forum',
  'forward': 'Inoltra',
  'free': 'Gratis',
  'fullscreen': 'Schermo intero',
  'functions': 'Funzioni',
  'game': 'Gioco',
  'gas': 'Benzina',
  'gesture': 'Gesto',
  'get': 'Ottieni',
  'gif': 'GIF',
  'gift': 'Regalo',
  'golf': 'Golf',
  'gps': 'GPS',
  'grade': 'Voto',
  'graph': 'Grafico',
  'grid': 'Griglia',
  'group': 'Gruppo',
  'hand': 'Mano',
  'handyman': 'Manutenzione',
  'headset': 'Cuffie',
  'health': 'Salute',
  'healing': 'Cura',
  'hearing': 'Udito',
  'help': 'Aiuto',
  'history': 'Storico',
  'home': 'Casa',
  'hotel': 'Hotel',
  'hourglass': 'Clessidra',
  'house': 'Casa',
  'hub': 'Hub',
  'image': 'Immagine',
  'import': 'Importa',
  'inbox': 'In arrivo',
  'info': 'Info',
  'input': 'Input',
  'insert': 'Inserisci',
  'install': 'Installa',
  'integration': 'Integrazione',
  'inventory': 'Inventario',
  'invert': 'Inverti',
  'ios': 'iOS',
  'key': 'Chiave',
  'keyboard': 'Tastiera',
  'label': 'Etichetta',
  'landscape': 'Paesaggio',
  'language': 'Lingua',
  'laptop': 'Portatile',
  'launch': 'Avvia',
  'layers': 'Livelli',
  'leaderboard': 'Classifica',
  'library': 'Biblioteca',
  'light': 'Luce',
  'link': 'Link',
  'list': 'Lista',
  'live': 'Live',
  'local': 'Locale',
  'location': 'Posizione',
  'lock': 'Blocco',
  'login': 'Login',
  'logout': 'Logout',
  'luggage': 'Valigia',
  'mail': 'Posta',
  'manage': 'Gestione',
  'map': 'Mappa',
  'mark': 'Segna',
  'medical': 'Medico',
  'medication': 'Farmaco',
  'meeting': 'Riunione',
  'memory': 'Memoria',
  'menu': 'Menu',
  'merge': 'Unisci',
  'message': 'Messaggio',
  'mic': 'Microfono',
  'mobile': 'Mobile',
  'mode': 'ModalitÃ ',
  'money': 'Denaro',
  'monitor': 'Monitor',
  'monitoring': 'Monitoraggio',
  'mood': 'Umore',
  'more': 'Altro',
  'motion': 'Movimento',
  'mouse': 'Mouse',
  'movie': 'Film',
  'music': 'Musica',
  'my': 'Mio',
  'nature': 'Natura',
  'navigation': 'Navigazione',
  'network': 'Rete',
  'new': 'Nuovo',
  'news': 'Notizie',
  'nfc': 'NFC',
  'night': 'Notte',
  'no': 'No',
  'note': 'Nota',
  'notes': 'Note',
  'notification': 'Notifica',
  'notifications': 'Notifiche',
  'numbers': 'Numeri',
  'off': 'Spento',
  'oil': 'Petrolio',
  'on': 'Acceso',
  'open': 'Apri',
  'outbox': 'In uscita',
  'outlined': 'Contorno',
  'page': 'Pagina',
  'palette': 'Palette',
  'pan': 'Pan',
  'park': 'Parco',
  'parking': 'Parcheggio',
  'password': 'Password',
  'paste': 'Incolla',
  'pause': 'Pausa',
  'payment': 'Pagamento',
  'payments': 'Pagamenti',
  'pending': 'In attesa',
  'people': 'Persone',
  'person': 'Persona',
  'pets': 'Animali',
  'phone': 'Telefono',
  'photo': 'Foto',
  'picture': 'Immagine',
  'pie': 'Torta',
  'pin': 'Pin',
  'place': 'Luogo',
  'play': 'Play',
  'policy': 'Policy',
  'pool': 'Piscina',
  'power': 'Energia',
  'precision': 'Precisione',
  'present': 'Presenta',
  'print': 'Stampa',
  'privacy': 'Privacy',
  'public': 'Pubblico',
  'qr': 'QR',
  'query': 'Query',
  'question': 'Domanda',
  'quiz': 'Quiz',
  'radio': 'Radio',
  'railway': 'Ferrovia',
  'rainy': 'Pioggia',
  'rate': 'Valuta',
  'receipt': 'Ricevuta',
  'record': 'Registra',
  'recycling': 'Riciclo',
  'refresh': 'Aggiorna',
  'remove': 'Rimuovi',
  'reply': 'Rispondi',
  'report': 'Segnala',
  'request': 'Richiesta',
  'restore': 'Ripristina',
  'restaurant': 'Ristorante',
  'reviews': 'Recensioni',
  'ring': 'Squillo',
  'rocket': 'Razzo',
  'room': 'Stanza',
  'route': 'Percorso',
  'router': 'Router',
  'rule': 'Regola',
  'run': 'Corsa',
  'satellite': 'Satellite',
  'save': 'Salva',
  'scale': 'Bilancia',
  'scanner': 'Scanner',
  'schedule': 'Programma',
  'school': 'Scuola',
  'science': 'Scienza',
  'screen': 'Schermo',
  'search': 'Cerca',
  'security': 'Sicurezza',
  'self': 'Personale',
  'send': 'Invia',
  'sensor': 'Sensore',
  'settings': 'Impostazioni',
  'share': 'Condividi',
  'shield': 'Scudo',
  'ship': 'Nave',
  'shop': 'Negozio',
  'shopping': 'Shopping',
  'show': 'Mostra',
  'shuffle': 'Casuale',
  'sign': 'Segno',
  'signal': 'Segnale',
  'skip': 'Salta',
  'sleep': 'Sonno',
  'smart': 'Smart',
  'smartphone': 'Smartphone',
  'sms': 'SMS',
  'snooze': 'Posticipa',
  'snow': 'Neve',
  'social': 'Social',
  'solar': 'Solare',
  'sort': 'Ordina',
  'sound': 'Suono',
  'source': 'Sorgente',
  'space': 'Spazio',
  'speaker': 'Altoparlante',
  'speed': 'VelocitÃ ',
  'sports': 'Sport',
  'star': 'Stella',
  'start': 'Avvia',
  'stop': 'Stop',
  'storage': 'Archiviazione',
  'store': 'Negozio',
  'storm': 'Tempesta',
  'straight': 'Dritto',
  'street': 'Strada',
  'subject': 'Oggetto',
  'subway': 'Metro',
  'sun': 'Sole',
  'support': 'Supporto',
  'surf': 'Surf',
  'swap': 'Scambia',
  'sync': 'Sincronizza',
  'system': 'Sistema',
  'table': 'Tabella',
  'tablet': 'Tablet',
  'tag': 'Tag',
  'take': 'Prendi',
  'task': 'AttivitÃ ',
  'taxi': 'Taxi',
  'terrain': 'Terreno',
  'text': 'Testo',
  'theater': 'Teatro',
  'thumb': 'Pollice',
  'time': 'Tempo',
  'timer': 'Timer',
  'tips': 'Suggerimenti',
  'title': 'Titolo',
  'today': 'Oggi',
  'toggle': 'Toggle',
  'toll': 'Pedaggio',
  'tonal': 'Tonal',
  'touch': 'Tocco',
  'tour': 'Tour',
  'traffic': 'Traffico',
  'train': 'Treno',
  'tram': 'Tram',
  'transfer': 'Trasferimento',
  'translate': 'Traduci',
  'travel': 'Viaggio',
  'trending': 'Trend',
  'trip': 'Viaggio',
  'troubleshoot': 'Diagnostica',
  'truck': 'Camion',
  'tune': 'Regola',
  'turn': 'Svolta',
  'tv': 'TV',
  'two': 'Due',
  'type': 'Tipo',
  'umbrella': 'Ombrello',
  'unfold': 'Espandi',
  'update': 'Aggiorna',
  'upload': 'Upload',
  'usb': 'USB',
  'verified': 'Verificato',
  'video': 'Video',
  'videocam': 'Videocamera',
  'view': 'Vista',
  'visibility': 'VisibilitÃ ',
  'voice': 'Voce',
  'volume': 'Volume',
  'vpn': 'VPN',
  'walk': 'Cammina',
  'wallet': 'Portafoglio',
  'warehouse': 'Magazzino',
  'warning': 'Avviso',
  'wash': 'Lava',
  'watch': 'Orologio',
  'water': 'Acqua',
  'wb': 'Meteo',
  'week': 'Settimana',
  'weekend': 'Weekend',
  'whatshot': 'Trending',
  'wheelchair': 'Sedia rotelle',
  'widgets': 'Widget',
  'wifi': 'WiFi',
  'wind': 'Vento',
  'window': 'Finestra',
  'wine': 'Vino',
  'work': 'Lavoro',
  'workspace': 'Workspace',
  'world': 'Mondo',
  'wrong': 'Errato',
  'yard': 'Giardino',
  'zoom': 'Zoom',
};
