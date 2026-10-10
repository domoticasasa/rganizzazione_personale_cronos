import 'package:flutter/material.dart';

import 'data_import_hub_entry.dart';

/// Catalogo moduli importabili, raggruppati per area applicativa.
abstract final class DataImportHubCatalog {
  DataImportHubCatalog._();

  static const sections = <DataImportHubSection>[
    DataImportHubSection(
      id: 'impostazioni',
      label: 'Amministrazione / Personale',
      sortOrder: 0,
      subtitle: 'Dati anagrafici e tabelle di base',
    ),
    DataImportHubSection(
      id: 'uqsa',
      label: 'QSA / UQSA',
      sortOrder: 1,
      subtitle: 'Liste POS, formazione, tesserini, estintori e cassette P.S.',
    ),
    DataImportHubSection(
      id: 'logistica',
      label: 'Logistica',
      sortOrder: 2,
      subtitle: 'Mezzi, attrezzature, BOX, multicard e noleggio',
    ),
    DataImportHubSection(
      id: 'carburante',
      label: 'Carburante',
      sortOrder: 3,
      subtitle: 'Verifica fatture QT (formato fornitore)',
    ),
    DataImportHubSection(
      id: 'dpi',
      label: 'DPI e Vestiario',
      sortOrder: 4,
      subtitle: 'Assegnazioni e inventario',
    ),
  ];

  static const entries = <DataImportHubEntry>[
    // —— Impostazioni ——
    DataImportHubEntry(
      id: 'master_commesse',
      sectionId: 'impostazioni',
      sectionLabel: 'Amministrazione / Personale',
      title: 'Commesse',
      description:
          'Codici commessa, CIG/CUP, PM, DT e coordinate GPS (lat/lon). '
          'Importare per prime. Dopo i BOX puoi anche usare «GPS da BOX» in Gestione Dati.',
      sortOrder: 0,
      icon: Icons.work_outline,
    ),
    DataImportHubEntry(
      id: 'master_stazioni',
      sectionId: 'impostazioni',
      sectionLabel: 'Amministrazione / Personale',
      title: 'Stazioni',
      description: 'Elenco stazioni ferroviarie attive/inattive.',
      sortOrder: 1,
      prerequisites: ['Commesse (consigliato)'],
      icon: Icons.train_outlined,
    ),
    DataImportHubEntry(
      id: 'master_aeroporti',
      sectionId: 'impostazioni',
      sectionLabel: 'Amministrazione / Personale',
      title: 'Aeroporti',
      description: 'Elenco aeroporti.',
      sortOrder: 2,
      icon: Icons.flight_outlined,
    ),
    DataImportHubEntry(
      id: 'master_strutture',
      sectionId: 'impostazioni',
      sectionLabel: 'Amministrazione / Personale',
      title: 'Strutture (hotel / ristoranti)',
      description: 'Strutture ricettive con indirizzo e GPS.',
      sortOrder: 3,
      icon: Icons.hotel_outlined,
    ),
    DataImportHubEntry(
      id: 'master_strutture_dlgs',
      sectionId: 'impostazioni',
      sectionLabel: 'Amministrazione / Personale',
      title: 'Strutture formazione D.Lgs. 81/08',
      description: 'Sedi e aule per corsi D.Lgs.',
      sortOrder: 4,
      icon: Icons.school_outlined,
    ),
    DataImportHubEntry(
      id: 'personale',
      sectionId: 'impostazioni',
      sectionLabel: 'Amministrazione / Personale',
      title: 'Gestione dipendenti',
      description:
          'Anagrafica dipendenti (nome, email, matricola, date). Senza creazione login.',
      sortOrder: 5,
      icon: Icons.groups_outlined,
    ),

    // —— QSA ——
    DataImportHubEntry(
      id: 'pos_dipendenti_lista',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Lista dipendenti POS',
      description: 'Elenco maestranze per commessa (allegato 01).',
      sortOrder: 0,
      requiresCommessa: true,
      prerequisites: ['Commesse', 'Dipendenti in anagrafica'],
      icon: Icons.engineering_outlined,
    ),
    DataImportHubEntry(
      id: 'pos_mdo_ferroviari_lista',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Elenco MdO ferroviari POS',
      description: 'Mezzi d\'opera ferroviari per commessa (allegato 02.3).',
      sortOrder: 1,
      requiresCommessa: true,
      prerequisites: ['Commesse', 'MdO ferroviari in Logistica'],
      icon: Icons.train_outlined,
    ),
    DataImportHubEntry(
      id: 'pos_mezzi_stradali_lista',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Elenco mezzi stradali POS',
      description: 'Mezzi stradali per commessa (allegato 02.1).',
      sortOrder: 2,
      requiresCommessa: true,
      prerequisites: ['Commesse', 'Mezzi stradali in Logistica'],
      icon: Icons.local_shipping_outlined,
    ),
    DataImportHubEntry(
      id: 'pos_mdo_proprieta_lista',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Elenco MdO proprietà/noleggio POS',
      description: 'MdO di proprietà o a noleggio (allegato 02.2).',
      sortOrder: 3,
      requiresCommessa: true,
      prerequisites: ['Commesse', 'MdO proprietà in Logistica'],
      icon: Icons.construction_outlined,
    ),
    DataImportHubEntry(
      id: 'formazione_dlgs',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Formazione D.Lgs. 81/08',
      description: 'Corsi, attestati e scadenze per dipendente.',
      sortOrder: 4,
      prerequisites: ['Dipendenti', 'Strutture D.Lgs.'],
      icon: Icons.school_outlined,
    ),
    DataImportHubEntry(
      id: 'formazione_rfi',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Formazione RFI',
      description: 'Formazione RFI per dipendente e corso.',
      sortOrder: 5,
      prerequisites: ['Dipendenti', 'Strutture RFI'],
      icon: Icons.account_tree_outlined,
    ),
    DataImportHubEntry(
      id: 'formazione_rfi_strutture',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Strutture formazione RFI',
      description: 'Anagrafica strutture/DOIT per formazione RFI.',
      sortOrder: 6,
      icon: Icons.business_outlined,
    ),
    DataImportHubEntry(
      id: 'tesserini',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Tesserini',
      description:
          'Numero tesserino e date per dipendenti già in anagrafica.',
      sortOrder: 7,
      prerequisites: ['Dipendenti in anagrafica'],
      icon: Icons.badge_outlined,
    ),
    DataImportHubEntry(
      id: 'estintori',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Estintori',
      description: 'Registro estintori con scadenze e commessa.',
      sortOrder: 8,
      prerequisites: ['Commesse'],
      icon: Icons.fire_extinguisher_outlined,
    ),
    DataImportHubEntry(
      id: 'casette_ps',
      sectionId: 'uqsa',
      sectionLabel: 'QSA / UQSA',
      title: 'Cassette P.S.',
      description: 'Cassette di primo soccorso.',
      sortOrder: 9,
      prerequisites: ['Commesse'],
      icon: Icons.medical_services_outlined,
    ),

    // —— Logistica ——
    DataImportHubEntry(
      id: 'box',
      sectionId: 'logistica',
      sectionLabel: 'Logistica',
      title: 'BOX',
      description:
          'Container BOX con ubicazione, GPS (lat/lon) e commessa. '
          'Il GPS BOX può poi aggiornare le commesse da Gestione Dati.',
      sortOrder: 0,
      prerequisites: ['Commesse'],
      icon: Icons.inventory_2_outlined,
    ),
    DataImportHubEntry(
      id: 'mdo_ferroviari',
      sectionId: 'logistica',
      sectionLabel: 'Logistica',
      title: 'MDO ferroviari',
      description: 'Mezzi d\'opera ferroviari in anagrafica logistica.',
      sortOrder: 1,
      prerequisites: ['Commesse'],
      icon: Icons.train_outlined,
    ),
    DataImportHubEntry(
      id: 'mdo_proprieta',
      sectionId: 'logistica',
      sectionLabel: 'Logistica',
      title: 'MDO proprietà',
      description: 'Mezzi e accessori di proprietà.',
      sortOrder: 2,
      prerequisites: ['Commesse'],
      icon: Icons.construction_outlined,
    ),
    DataImportHubEntry(
      id: 'mezzi_stradali',
      sectionId: 'logistica',
      sectionLabel: 'Logistica',
      title: 'Mezzi stradali',
      description: 'Automezzi e veicoli stradali.',
      sortOrder: 3,
      icon: Icons.local_shipping_outlined,
    ),
    DataImportHubEntry(
      id: 'attrezzature',
      sectionId: 'logistica',
      sectionLabel: 'Logistica',
      title: 'Attrezzature',
      description: 'Attrezzature con riferimento commessa.',
      sortOrder: 4,
      prerequisites: ['Commesse'],
      icon: Icons.handyman_outlined,
    ),
    DataImportHubEntry(
      id: 'multicard',
      sectionId: 'logistica',
      sectionLabel: 'Logistica',
      title: 'Multicard',
      description: 'Carte carburante multicard.',
      sortOrder: 5,
      icon: Icons.credit_card_outlined,
    ),
    DataImportHubEntry(
      id: 'noleggio',
      sectionId: 'logistica',
      sectionLabel: 'Logistica',
      title: 'Noleggio',
      description: 'Mezzi in noleggio.',
      sortOrder: 6,
      icon: Icons.car_rental_outlined,
    ),

    // —— Carburante ——
    DataImportHubEntry(
      id: 'qt_fatturazione_verifica',
      sectionId: 'carburante',
      sectionLabel: 'Carburante',
      title: 'Verifica fatturazione QT',
      description:
          'Importa gli Excel fattura del fornitore QT (non un modello Cronos) '
          'e confronta con i giustificativi RCC. Usa la pagina dedicata.',
      sortOrder: 0,
      opensExistingPage: true,
      prerequisites: ['Multicard / mezzi', 'Giustificativi RCC'],
      icon: Icons.fact_check_outlined,
    ),

    // —— DPI e Vestiario (allineato all'hub DPI) ——
    DataImportHubEntry(
      id: 'dpi_report',
      sectionId: 'dpi',
      sectionLabel: 'DPI e Vestiario',
      title: 'Report DPI dipendenti',
      description: 'Dotazioni DPI per dipendente e categoria.',
      sortOrder: 0,
      prerequisites: ['Dipendenti', 'Categorie DPI'],
      icon: Icons.inventory_2_outlined,
    ),
    DataImportHubEntry(
      id: 'dpi_categorie',
      sectionId: 'dpi',
      sectionLabel: 'DPI e Vestiario',
      title: 'Categorie DPI',
      description: 'Tipologie DPI disponibili.',
      sortOrder: 1,
      icon: Icons.category_outlined,
    ),
    DataImportHubEntry(
      id: 'dpi_terza_categoria',
      sectionId: 'dpi',
      sectionLabel: 'DPI e Vestiario',
      title: 'Assegnazione DPI III categoria',
      description: 'DPI di terza categoria per dipendente.',
      sortOrder: 2,
      prerequisites: ['Dipendenti'],
      icon: Icons.description_outlined,
    ),
    DataImportHubEntry(
      id: 'vestiario_assegnazione',
      sectionId: 'dpi',
      sectionLabel: 'DPI e Vestiario',
      title: 'Assegnazione vestiario',
      description: 'Consegne vestiario per dipendente, articolo e taglia.',
      sortOrder: 3,
      prerequisites: ['Dipendenti', 'Inventario vestiario'],
      icon: Icons.checkroom_outlined,
    ),
    DataImportHubEntry(
      id: 'vestiario_riepilogo',
      sectionId: 'dpi',
      sectionLabel: 'DPI e Vestiario',
      title: 'Riepilogo vestiario (taglie)',
      description: 'Taglie dipendenti per t-shirt, pantalone, scarpe, ecc.',
      sortOrder: 4,
      prerequisites: ['Dipendenti'],
      icon: Icons.summarize_outlined,
    ),
    DataImportHubEntry(
      id: 'vestiario_fabbisogno',
      sectionId: 'dpi',
      sectionLabel: 'DPI e Vestiario',
      title: 'Fabbisogno taglie',
      description: 'Taglie per articolo (base calcolo fabbisogno annuo).',
      sortOrder: 5,
      prerequisites: ['Dipendenti'],
      icon: Icons.straighten_outlined,
    ),
    DataImportHubEntry(
      id: 'vestiario_inventario',
      sectionId: 'dpi',
      sectionLabel: 'DPI e Vestiario',
      title: 'Inventario vestiario',
      description: 'Giacenze magazzino vestiario per articolo e taglia.',
      sortOrder: 6,
      icon: Icons.warehouse_outlined,
    ),
  ];

  static List<DataImportHubSection> sortedSections() {
    final list = List<DataImportHubSection>.from(sections)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  static List<DataImportHubEntry> entriesForSection(String sectionId) {
    return entries
        .where((e) => e.sectionId == sectionId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  static DataImportHubEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}
