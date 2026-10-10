/// Catalogo contenuto minimo casette P.S. (Allegato 1 e 2 — DM 388/2003).
class CasettaPsMaterialeVoce {
  final String id;
  final String descrizione;

  const CasettaPsMaterialeVoce({required this.id, required this.descrizione});
}

abstract final class CasettaPsCatalogo {
  static const String allegato1Label = 'ALLEGATO 1 (piu di 3 lavoratori)';
  static const String allegato2Label = 'ALLEGATO 2 (fino a 3 lavoratori)';

  static bool isAllegato1Tipo(String? tipo) {
    final t = (tipo ?? '').toUpperCase();
    return t.contains('ALL1') || t.contains('ALLEGATO 1');
  }

  static bool isAllegato2Tipo(String? tipo) {
    final t = (tipo ?? '').toUpperCase();
    return t.contains('ALL2') || t.contains('ALLEGATO 2');
  }

  static List<CasettaPsMaterialeVoce> vociPerTipo(String? tipo) {
    if (isAllegato2Tipo(tipo)) return allegato2;
    return allegato1;
  }

  static const List<CasettaPsMaterialeVoce> allegato1 = <CasettaPsMaterialeVoce>[
    CasettaPsMaterialeVoce(id: 'a1_01', descrizione: 'Guanti sterili monouso (5 paia)'),
    CasettaPsMaterialeVoce(
      id: 'a1_02',
      descrizione: 'Flacone soluzione cutanea iodopovidone 10% (1 litro)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a1_03',
      descrizione: 'Flacone soluzione fisiologica 0,9% da 500 ml (3)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a1_04',
      descrizione: 'Compresse garza sterile 10x10 in buste singole (10)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a1_05',
      descrizione: 'Compresse garza sterile 18x40 in buste singole (2)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a1_06',
      descrizione: 'Pinzette da medicazione sterili monouso (2)',
    ),
    CasettaPsMaterialeVoce(id: 'a1_07', descrizione: 'Confezione di cotone idrofilo (1)'),
    CasettaPsMaterialeVoce(
      id: 'a1_08',
      descrizione: 'Confezioni cerotti varie misure pronti all\'uso (2)',
    ),
    CasettaPsMaterialeVoce(id: 'a1_09', descrizione: 'Rotoli di cerotto alto 2,5 cm (2)'),
    CasettaPsMaterialeVoce(id: 'a1_10', descrizione: 'Visiera paraschizzi (1)'),
    CasettaPsMaterialeVoce(id: 'a1_11', descrizione: 'Un paio di forbici (1)'),
    CasettaPsMaterialeVoce(id: 'a1_12', descrizione: 'Lacci emostatici (3)'),
    CasettaPsMaterialeVoce(id: 'a1_13', descrizione: 'Ghiaccio pronto uso (2)'),
    CasettaPsMaterialeVoce(
      id: 'a1_14',
      descrizione: 'Sacchetti monouso raccolta rifiuti sanitari (2)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a1_15',
      descrizione: 'Descrizione e indicazioni uso prodotti',
    ),
    CasettaPsMaterialeVoce(id: 'a1_16', descrizione: 'Teli sterili monouso (2)'),
    CasettaPsMaterialeVoce(
      id: 'a1_17',
      descrizione: 'Confezione rete elastica misura media (1)',
    ),
    CasettaPsMaterialeVoce(id: 'a1_18', descrizione: 'Termometro (1)'),
    CasettaPsMaterialeVoce(
      id: 'a1_19',
      descrizione: 'Apparecchio misurazione pressione arteriosa (1)',
    ),
  ];

  static const List<CasettaPsMaterialeVoce> allegato2 = <CasettaPsMaterialeVoce>[
    CasettaPsMaterialeVoce(id: 'a2_01', descrizione: 'Guanti sterili monouso (2 paia)'),
    CasettaPsMaterialeVoce(
      id: 'a2_02',
      descrizione: 'Flacone soluzione cutanea iodopovidone 10% (125 ml)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a2_03',
      descrizione: 'Flacone soluzione fisiologica 0,9% da 250 ml (1)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a2_04',
      descrizione: 'Compresse garza sterile 10x10 in buste singole (3)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a2_05',
      descrizione: 'Compresse garza sterile 18x40 in buste singole (1)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a2_06',
      descrizione: 'Pinzette da medicazione sterili monouso (1)',
    ),
    CasettaPsMaterialeVoce(id: 'a2_07', descrizione: 'Confezione di cotone idrofilo (1)'),
    CasettaPsMaterialeVoce(
      id: 'a2_08',
      descrizione: 'Confezione cerotti varie misure pronti all\'uso (1)',
    ),
    CasettaPsMaterialeVoce(id: 'a2_09', descrizione: 'Rotolo di cerotto alto 2,5 cm (1)'),
    CasettaPsMaterialeVoce(id: 'a2_10', descrizione: 'Rotolo benda orlata alta 10 cm (1)'),
    CasettaPsMaterialeVoce(id: 'a2_11', descrizione: 'Un paio di forbici (1)'),
    CasettaPsMaterialeVoce(id: 'a2_12', descrizione: 'Laccio emostatico (1)'),
    CasettaPsMaterialeVoce(id: 'a2_13', descrizione: 'Ghiaccio pronto uso (1)'),
    CasettaPsMaterialeVoce(
      id: 'a2_14',
      descrizione: 'Sacchetto monouso raccolta rifiuti sanitari (1)',
    ),
    CasettaPsMaterialeVoce(
      id: 'a2_15',
      descrizione: 'Descrizione e indicazioni uso prodotti',
    ),
  ];
}
