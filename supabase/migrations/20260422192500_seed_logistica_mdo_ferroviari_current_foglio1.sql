delete from public.logistica_mdo_ferroviari;

insert into public.logistica_mdo_ferroviari (
  matricola_interna, codice_identificativo_targa_rfi, descrizione_mezzo, descrizione_rumo, modello, equipment, matricola_costruttore, cantiere_attuale, commessa, dispositivo_shuntaggio_check, lanterna_bilux_check, fanali_coda_check, tabella_coda_check, torcia_fiamma_rossa_check, bandiera_rossa_asta_check, scarpe_fermacarro_check, chiave_tripla_snodata_check, barra_traino_check, vaschetta_raccolta_liquidi_check, active
) values
  ('A01', 'IT-RFI 140006-3', 'CARRO PIANALE', '107865-1 CP32 SVI RIMORCHIO NON SPECIFIC', 'CP 32', '10118333', '107865-1', 'TORINO STURA', 'TE-02-21', False, False, False, False, False, False, False, False, False, False, true),
  ('A01B', NULL, 'BETONIERA', NULL, 'SRY100', NULL, NULL, NULL, NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A02', 'IT-RFI 140007-1', 'CARRO PIANALE', '107865-2  CP32 SVI RIMORCHIO', 'CP 32', '10118334', '107865-2', 'TRIESTE', 'GCF', False, False, False, False, False, False, False, False, False, False, true),
  ('A03', 'IT-RFI 151242-0', 'MOTOCARRELLO CON GRU', 'DBCO 1964 21/4 RH6 ROBEL KLV51 AUTOCARR.', 'ROBEL V51', '10136949', 'DBCO 1964 21/4 RH6', 'STAZIONE DI TEL 
MERANO (BZ)', 'GCF', False, False, False, False, False, False, False, False, False, False, true),
  ('A04', 'IT-RFI 151239-7', 'MOTOCARRELLO CON GRU', 'AR 52 ROBEL AUTOCARRELLO GEO.RAIL', 'ROBEL AR 52-4', '10136946', 'AR 52', 'MARTINA FRANCA', 'TE-01-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A14SR', 'NON ISCRITTO NEL RUMO
 
W/D/ASL/TO/0044/0', 'MOTOSCALA CON TERRAZZINO
W/D/ASL/TO/0044/0', NULL, 'CM', NULL, 'CM 22', 'MOREGINE (NA)', 'TE-01-19', False, False, False, False, False, False, False, False, False, False, true),
  ('A74SR', 'IT-RFI 140815-8
NON ISCRITTO NEL RUMO', 'CARRO PIANALE
WDRCHRM1011M', NULL, 'SHOMA 313819', NULL, '3819', 'MOREGINE (NA)', 'TE-01-19', False, False, False, False, False, False, False, False, False, False, true),
  ('A07', 'IT-RFI 260979-7', 'RIMORCHIO SCALA MOTORIZZATO', '604390-1 RSM9 SCALA MOTORIZZATA SVI SPA', 'RSM 9 SVI 604390-1', '10136942', '604390-1', 'MARTINA FRANCA', 'TE-01-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A08', 'IT-RFI 260981-2', 'RIMORCHIO SCALA MOTORIZZATO', '604390-3 RSM9 SCALA MOTORIZZATA SVI SPA', 'RSM 9 SVI 604390-3', '10136945', '604390-3', 'MARTINA FRANCA', 'TE-01-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A09', 'IT-RFI 261019-0', 'RIMORCHIO SCALA MOTORIZZATO', '020/810 SIRTI A.M.O. SC MOTORIZZ. SIRTI', 'RSM SIRTI AMO/020-810861', '10137068', '020/810861', 'SO.CO.FER', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A10', 'IT-RFI 260982-0', 'RIMORCHIO SCALA MOTORIZZATO', '7174 PVM03 SCALA MOTORIZZATA NUOVA RALFO', 'RSM NUOVA RALFO
PVM03/7174', '10136958', '7174', 'TECHNORAIL', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A11', 'IT-RFI 140113-6', 'CARRO PIANALE', '441030-6 CP 45 L SVI RIMORCHIO', 'CP 45 SVI Ribassato 
(EX. SALC)', '10122043', '441030-6', 'GCF INTERNO - CODIGORO (FE)', 'OFFICINA', False, False, False, False, False, False, False, False, False, False, true),
  ('A12', 'IT-RFI 140115-2', 'CARRO PIANALE', '441030-8 CP 45 L SVI RIMORCHIO', 'CP 45 SVI Ribassato 
(EX. SALC)', '10122045', '441030-8', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A13', 'IT-RFI 140114-4', 'CARRO PIANALE', '441030-7 CP45L SVI RIMORCHIO', 'CP 45 SVI Ribassato 
(EX. SALC)', '10122044', '441030-7', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A75SR', 'IT-RFI 151434-3
NON ISCRITTO NEL RUMO', 'MOTOCARRELLO CON GRU 
WDAGRRM1007Q', NULL, 'KLV -53', NULL, '54-13-1RN27', 'MOREGINE (NA)', 'TE-01-19', False, False, False, False, False, False, False, False, False, False, true),
  ('A05', 'IT-RFI 261020-7', 'RIMORCHIO SCALA MOTORIZZATO', '810862 SIRTI A.M.O. SC MOTORIZ SIRTI', 'RSM SIRTI AMO/810862', '10137069', '810862', 'TORRE ANNUNZIATA (NA)', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A16SR', 'NON ISCRITTO NEL RUMO', 'MOTOCARRELLO CON GRU', NULL, 'ROBEL KLV51', NULL, 'SV 75/87', 'CLES
TRENTINO TRASPORTI', 'LFM-01-21', False, False, False, False, False, False, False, False, False, False, true),
  ('A17', 'IT-RFI 250813-9', 'CARRO RECUPERATORE', '1602351-6 CRC 6000 SVI  SVOLGIBOBINE', 'CRC 6000 SVOLGIBOBINE SVI', '10204950', '1602351-6', 'PIOLTELLO', 'GCF', False, False, False, False, False, False, False, False, False, False, true),
  ('A18', 'IT-RFI 161628-0', 'AUTOSCALA POLIVALENTE CON GRU E TERRAZZINO', '1812668-4 APV 320 D SVI AUTOSCALA', 'APV 320 D SVI', '10218525', '1812668-4', 'BACCINO VENETO
MONTEBELLUNA (TV)', 'TE-06-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A19', 'IT-RFI 152329-5', 'MOTOCARRELLO CON GRU', '1903844-13 AGR 220 SVI AUTOCARRELLO', 'AGR 220 SVI', '10226104', '1903844-13', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A20', 'IT-RFI 161556-3', 'MOTOCARRELLO CON GRU E TERRAZZINO', '51-9329 ROBEL AUTOSCALA AS', 'GLEISMAC (CGF)', '10155473', '51-9329', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A21', 'IT-RFI 161636-3', 'AUTOSCALA POLIVALENTE CON GRU E TERRAZZINO', '1812668-5 APV 320 D SVI AUTOSCALA', 'APV 320 D SVI', '10218991', '1812668-5', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A22', 'IT-RFI 261893-8', 'PONTE DI TESATURA CON TERRAZZINO', '1602352-6 PT 500SP.13-100 SVI', 'PT 500 SPAZIO 13-100 SVI 1602352-6', '10214538', '1602352-6', 'BACCINO VENETO
MONTEBELLUNA (TV)', 'TE-06-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A23', 'IT-RFI 261881-3', 'RIMORCHIO SCALA MOTORIZZATO', '501055-20 RSM 12 SVI SCALA MOTORIZZATA', 'RSM 12 SVI 501055-20', '10207716', '501055-20', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A24', 'IT-RFI 261883-9', 'RIMORCHIO SCALA MOTORIZZATO', '501055-21 RSM 12 SVI SCALA MOTORIZZATA', 'RSM 12 SVI 501055-21', '10207718', '501055-21', 'STAZIONE DI TEL 
MERANO (BZ)', 'TE-09-23', False, False, False, False, False, False, False, False, False, False, true),
  ('A25', 'IT-RFI 261900-1', 'RIMORCHIO SCALA MOTORIZZATO', '501055-22 RSM 12 SVI scala motor.', 'RSM 12 SVI 501055-22', '10218059', '501055-22', 'STAZIONE DI TEL 
MERANO (BZ)', 'TE-09-23', False, False, False, False, False, False, False, False, False, False, true),
  ('A26', 'IT-RFI 250819-7', 'CARRO RECUPERATORE', '501056-3 CBF 2 M 4.5 SVI  SVOLGIBOBINE', 'CBF 2 SVI 501056-3  M 4.5', '10207719', '501056-3', 'BERGAMO', 'TE-02-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A27', 'IT-RFI 140094-8', 'CARRO PIANALE', '441030-4 CP 45 L SVI SPA RIMORCHIO PIAN', 'CP 45 SVI Ribassato 
(EX. SALC)', '10121619', '441030-4', 'GCF RUMO - STASTELGUELFO (PR)', 'OFFICINA', False, False, False, False, False, False, False, False, False, False, true),
  ('A28', 'IT-RFI 152306-3', 'MOTOCARRELLO CON GRU', '412020-7 AGR500 SVI AUTOCARRELLO', 'AGR 500', '10220982', '412020-7', 'STAZIONE DI TEL 
MERANO (BZ)', 'TE-09-23', False, False, False, False, False, False, False, False, False, False, true),
  ('A29', 'IT-RFI 141378-5', 'CARRO PIANALE', '1504121-35 CP 45 L SVI SPA', 'CP 45 L SVI', '10214695', '1504121-35', 'STAZIONE DI TEL 
MERANO (BZ)', 'TE-09-23', False, False, False, False, False, False, False, False, False, False, true),
  ('A30', 'IT-RFI 141379-3', 'CARRO PIANALE', '1504121-36 CP 45 L SVI SPA', 'CP 45 L SVI 1504121-36', '10214696', '1504121-36', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A31', 'IT-RFI 261918-4', 'RIMORCHIO SCALA MOTORIZZATO', '501055-51 RSM 12 SVI Scala Motorizzata', 'RSM 12 SVI
501055-51', '10227379', '501055-51', 'BERGAMO', 'TE-02-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A32', 'IT-RFI 261917-6', 'RIMORCHIO SCALA MOTORIZZATO', '501055-50 RSM 12 SVI Scala Motorizzata', 'RSM 12 SVI 
501055-50', '10227328', '501055-50', 'STAZIONE DI TEL 
MERANO (BZ)', 'TE-09-23', False, False, False, False, False, False, False, False, False, False, true),
  ('A33-BLE', NULL, 'AUTOBOTTE PER PRODUZIONE CALCESTRUZZO', NULL, 'BLEND SEVENTY + ROMPISACCO', NULL, NULL, 'SEDE CAIRO', 'LOGISTICA', False, False, False, False, False, False, False, False, False, False, true),
  ('A34', 'IT-RFI 270692-3', 'LOCOMOTORE', '26091 KOF II O&K LOCOMOTORE', 'KOF II GLEISMAC', '10170668', '26091', 'STAZIONE DI TEL 
MERANO (BZ)', 'TE-09-23', False, False, False, False, False, False, False, False, False, False, true),
  ('A35SR', 'NON ISCRITTO NEL RUMO', 'CARRO PIANALE', NULL, 'KLA 03', NULL, '3496', 'CLES
TRENTINO TRASPORTI', 'LFM-01-21', False, False, False, False, False, False, False, False, False, False, true),
  ('A36', 'IT-RFI 171603-0', 'CARRO PIANALE', '297 FERROVIE ESTERE CARRO PIANALE', '2 ASSI P811S', '10135343', '297', 'ITALY RAIL', 'OFFICINA', False, False, False, False, False, False, False, False, False, False, true),
  ('A37', 'IT-RFI 270488-6', 'LOCOMOTORE', '26349 Locom. Orenstein & Koppel KOF III', 'KOF III  MV 6 B', '10139929', '26349', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A38', 'IT-RFI 141407-2', 'CARRO PIANALE', 'H0072 H850/25 GleisFrei Rimorchio', 'H850/25', '10218724', 'H0072', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A39', 'IT-RFI 173795-3', 'CARRO PIANALE', '1901689-22  CP 34 SVI CARRO', 'CP 34 SVI RIbassato', '10218585', '1901689-22', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A40', 'IT-RFI 141409-8', 'CARRO PIANALE', '1504121-42 CP 45 L SVI RIMORCHIO', 'CP 45 SVI Ribassato', '10218731', '1504121-42', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A41', 'IT-RFI 173793-7', 'CARRO PIANALE', '1901689-21  CP 34 SVI CARRO', 'CP 34 SVI Ribassato', '10218582', '1901689-21', 'MANDURIA
CAMPI S.', 'TE-04-19', False, False, False, False, False, False, False, False, False, False, true),
  ('A42-BLE', NULL, 'AUTOBOTTE PER PRODUZIONE CALCESTRUZZO', NULL, 'BLEND SEVENTY + ROMPISACCO', NULL, NULL, 'SEDE CAIRO', 'LOGISTICA', False, False, False, False, False, False, False, False, False, False, true),
  ('A43', 'IT-RFI 140095-6', 'CARRO PIANALE', '441030-5 CP 45 L SVI SPA RIMORCHIO PIAN', 'CP 45 SVI Ribassato 
(EX. SALC)', '10121621', '441030-5', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A44', 'IT-RFI 173812-5', 'CARRO PIANALE', '1901689-23  CP 34 SVI CARRO', 'CP 34 SVI Ribassato', '10219913', '1901689-23', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A45', 'IT-RFI 173814-1', 'CARRO PIANALE', '1901689-24  CP 34 SVI CARRO', 'CP 34 SVI Ribassato', '10219916', '1901689-24', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A46', 'IT-RFI 173819-1', 'CARRO PIANALE', '1901689-25  CP 34 SVI CARRO', 'CP 34 SVI Ribassato', '10219938', '1901689-25', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A47', NULL, 'IMPALCATO FERROVIARIO', NULL, 'MONTATO SU CP34', NULL, NULL, 'ARQUATA SCRIVIA', 'LFM-01-22 dal 17/05/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A48', 'IT-RFI 080073-5', 'COMPLESSO DI TESATURA FRENATO', '1602353-8 CTF 7020 BS-100 SVI Carro tesa', 'CTF 7020  BS100', '10227938', '1602353-8', 'PIOLTELLO', 'GCF', False, False, False, False, False, False, False, False, False, False, true),
  ('A49', 'IT-RFI 080072-7', 'COMPLESSO DI TESATURA FRENATO', '1602353-7 CTF 7020 BS-100 SVI Carro tesa', 'CTF 7020  BS100', '10227937', '1602353-7', 'PIOLTELLO', 'GCF', False, False, False, False, False, False, False, False, False, False, true),
  ('A50', 'IT-RFI 140096-4', 'CARRO PIANALE', '441030-3 CP 45 L SVI SPA RIMORCHIO PIAN.', 'CP 45 SVI Ribassato 
(EX. SALC)', '10121622', '441030-3', 'GRIZZANO MORANDI (BO)', 'GCF', False, False, False, False, False, False, False, False, False, False, true),
  ('A50C', NULL, 'CISTERNA ACQUA 20.000LT - ASSOCIATA AD A50-CP45', NULL, NULL, NULL, NULL, 'POMEZIA', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A51', 'IT-RFI 261185-9', 'RIMORCHIO SCALA MOTORIZZATO', '046 GLEISMAC AS6G-SG SCALA MOTORIZZATA', 'RSM AS6G-SG', '10139891', '46', 'TORINO STURA', 'TE-02-21', False, False, False, False, False, False, False, False, False, False, true),
  ('A52', 'IT-RFI 261184-1', 'RIMORCHIO SCALA MOTORIZZATO', '045 GLEISMAC AS6G-SG SCALA MOTORIZZATA', 'RSM AS6G-SG', '10139890', '45', 'BERGAMO', 'IS-01-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A53', 'IT-RFI 250449-2', 'CARRO RECUPERATORE', '601 SVOLGIBOBINE STARFER', 'STARFER 
(EX ELFER)', '10139846', '601', 'SO.CO.FER', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A54', 'IT-RFI 151432-7', 'MOTOCARRELLO CON GRU', '30529 KLV53 WAGGON UNION AUTOCARRELLO', 'KLV53 
WAGGON UNION', '10139635', '30529', 'TORINO STURA', 'TE-02-21', False, False, False, False, False, False, False, False, False, False, true),
  ('A55', 'IT-RFI 151430-1', 'MOTOCARRELLO CON GRU', '1275/2 AUTOCARRELLO CON GRU COMETI', 'CMT 120', '10139633', '1275/2', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A56', 'IT-RFI 151429-4', 'MOTOCARRELLO CON GRU E TERRAZZINO', 'M25014 CF250G AUTOCAR. CON GRU GLEISMAC', 'GLEISMAC CF250G', '10139632', 'M25014', 'RI.MA', 'OFFICINA', False, False, False, False, False, False, False, False, False, False, true),
  ('A57', 'IT-RFI 140816-6', 'CARRO PIANALE', '31 RIMORCHIO SCHOMA', 'SHOMA
(EX ELFER)', '10139450', '31', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A58', 'IT-RFI 140814-0', 'CARRO PIANALE', '3782 KLA SCHOMA  RIMORCHIO', 'SHOMA KLA', '10139448', '3782', 'ITALIA MANUTENZIONI', 'OFFICINA', False, False, False, False, False, False, False, False, False, False, true),
  ('A59', 'IT-RFI 140812-4', 'CARRO PIANALE', '2210/2  RIMORCHIO COMETI', 'COMETI', '10139446', '2210/2', 'LAVENO', 'TE-08-23', False, False, False, False, False, False, False, False, False, False, true),
  ('A06', 'IT-RFI 261036-4', 'RIMORCHIO SCALA MOTORIZZATO', '813406 SIRTI A.M.O. SC MOTORIZ SIRTI', 'RSM SIRTI AMO/813406', '10137085', '813406', 'TORRE ANNUNZIATA (NA)', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A61', 'IT-RFI 261189-1', 'RIMORCHIO SCALA MOTORIZZATO', '2152/7 F 82 SCALA MOTORIZZATA FIPEM', 'RSM FIPEM', '10139895', '2152/7', 'SO.CO.FER', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A62', 'IT-RFI 261188-3', 'RIMORCHIO SCALA MOTORIZZATO', '2152/6  F.82 FIPEM SCALA MOTORIZZATA', 'RSM FIPEM', '10139894', '2152/6', 'SO.CO.FER', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A63ST', 'IT-RFI 261187-5', 'RIMORCHIO SCALA MOTORIZZATO - TRAMVIARIO', '2296/6 FIPEM F87 SCALA MOTORIZZATA', 'FIPEM', '10139893', '2296/6', 'SO.CO.FER', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A64', 'IT-RFI 261183-3', 'RIMORCHIO SCALA MOTORIZZATO', '044 GLEISMAC AS6G-SG SCALA MOTORIZZATA', 'RSM AS6G-SG 
(EX ELFER)', '10139889', '44', 'TECHNORAIL', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A65', 'IT-RFI 261182-5', 'RIMORCHIO SCALA MOTORIZZATO', '043 GLEISMAC AS6G-SG SCALA MOTORIZZATA', 'RSM AS6G-SG 
(EX ELFER)', '10139888', '43', 'TECHNORAIL', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A66', 'IT-RFI 151435-1', 'MOTOCARRELLO CON GRU', '54-135RW52 KLV53 ROBELAUTOCARRELLO', 'KLV53 
ROBEL', '10139638', '54-135RW52', 'MARTINA FRANCA', 'TE-01-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A67', 'IT-RFI 151433-5', 'MOTOCARRELLO CON GRU', '18433 KLV 53 AUTOCARRELLO WAGGON UNION', 'KLV53 WAGGON UNION', '10139636', '18433', 'BERGAMO', 'TE-02-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A68', 'IT-RFI 151431-9', 'MOTOCARRELLO CON GRU', 'NS 16 F 120 \FIPEM AUTOCARRELLO GRU', 'FIPEM', '10139634', 'NS 16 F 120', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A69', 'IT-RFI 140892-6', 'CARRO PIANALE', 'II-FN009 GEORAILSRL RIMORCHIO', 'CP GEORAIL 
(EX ELFER)', '10139526', 'II-FN009', 'ARQUATA SCRIVIA', 'LFM-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A70', 'IT-RFI 140817-4', 'CARRO PORTABOBINE (SENZA FRIZIONE)', '504 RIMORCHIO RECUP. Onofri e Paganelli', 'ONOFRI E PAGANELLI (EX ELFER)', '10139451', '504', 'SO.CO.FER', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A71', 'IT-RFI 140813-2', 'CARRO PIANALE (+ PILOTINA?)', '3992 RIMORCHIO SCHOMA', 'SHOMA', '10139447', '3992', 'MARTINA FRANCA', 'TE-01-24 dal 14/06/24', False, False, False, False, False, False, False, False, False, False, true),
  ('A72', 'IT-RFI 140811-6', 'CARRO PIANALE', 'RF1007/27ECCB19028 RIMORCHIO GLEISMAC RF', 'GLEISMAC RF 300(EX ELFER)', '10139445', 'RF1007/27', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A15SR', 'NON ISCRITTO NEL RUMO', 'CARRO SVOLGIBOBINE', NULL, 'CHFFS', NULL, NULL, 'TORRE ANNUNZIATA (NA)', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A60', 'IT-RFI 261190-8', 'RIMORCHIO SCALA MOTORIZZATO', '2259/4 SCALA MOTORIZZATA ELETT. FIPEM', 'RSM FIPEM', '10139896', '2259/4', 'TORRE ANNUNZIATA (NA)', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A73', 'IT-RFI 011258-6', 'CARICATORE STRADA/ROTAIA', '474377 CARICATORE S/R DONELLI KGT-V', 'DONELLI KGT-V', '10139291', '474377', 'TORRE ANNUNZIATA (NA)', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('A76', 'IT-RFI 260084-4', 'PONTE DI TESATURA CON TERRAZZINO', '444030 PT 500-SVI PONTE DI TESATURA', 'PT 500 - SVI', '10121878', '444030', 'BACCINO VENETO
MONTEBELLUNA (TV)', 'TE-06-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A77', 'IT-RFI 080010-7', 'CARRO DI TESATURA FRENATO 
MOTORIZZATO', '446030 CTF5000BS SVI CARRO TESATURA FREN', 'CTF 5000 BS SVI', '10126225', '446030', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A78', 'IT-RFI 080011-5', 'CARRO DI TESATURA FRENATO', '445030 CTF5000B SVI CARRO TESATURA', 'CTF 5000 B SVI', '10126262', '445030', 'RI.MA', 'OFFICINA', False, False, False, False, False, False, False, False, False, False, true),
  ('A79', 'IT-RFI 141434-5', 'CARRO PIANALE', '1504121-50 CP 45L SVI SPA Rimorchio', 'CP 45 SVI Ribassato', '10231155', '1504121-50', 'MARTINA FRANCA', 'TE-01-24', False, False, False, False, False, False, False, False, False, False, true),
  ('A80', 'IT-RFI 141435-3', 'CARRO PIANALE', '1504121-51 CP 45L SVI Rimorchio', 'CP 45 SVI Ribassato', '10231156', '1504121-51', 'MONZA', 'TE-02-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A81', 'IT-RFI 170228-7', 'CARRO PIANALE', '101711-3 CP60 SVI CARRO', 'CP 60
(EX . SALC)', '10121577', '101711-3', 'LATINA', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A82', 'IT-RFI 170334-2', 'CARRO PIANALE', '101711-4 CP60 SVI CARRO PIANALE', 'CP 60
(EX . SALC)', '10124101', '101711-4', 'POMEZIA', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A83', 'IT-RFI 170345-9', 'CARRO PIANALE', '207237-1  CP60R SVI CARRO PIANALE RIB', 'CP C60R
(EX. SALC)', '10124658', '207237-1', 'LATINA', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('A84', 'IT-RFI 270063-6', 'LOCOMOTORE', '103775-3 LC 350 T SVI SPA LOCOMOTORE', 'LC350T
(EX. SALC)', '10121623', '103775-3', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('A85', 'IT-RFI 270075-1', 'LOCOMOTORE', '103775-4 LC 350 T SVI SPA  LOCOMOTORE', 'LC350T
(EX. SALC)', '10121975', '103775-4', 'POMEZIA', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('B01 
(Ex A02B)', NULL, 'BETONIERA', NULL, 'SRY100
MATR. 28062', NULL, '28062', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('B02
(Ex A38B)', NULL, 'BETONIERA', NULL, 'ARMEC HY 100
MATR. 401353', NULL, '401353', 'SEDE CAIRO', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('B03
(Ex A44B)
CETIP', NULL, 'BETONIERA', NULL, 'CIFA
MATR. 41117', NULL, '41117', 'R.D.A.
MARCIANISE', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('B04
(Ex A59B)', NULL, 'BETONIERA', NULL, NULL, NULL, NULL, 'LAVENO', 'TE-08-23', False, False, False, False, False, False, False, False, False, False, true),
  ('B05
(Ex A69B)', NULL, 'BETONIERA', NULL, '(EX ELFER)', NULL, NULL, 'R.D.A.
MARCIANISE', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('B06
(Ex A72B)', NULL, 'BETONIERA', NULL, 'CIFA SRY 1000 D10
MATR. 26100', NULL, '26100', 'TORRE ANNUNZIATA (NA)', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('B07
(Ex A11B)', NULL, 'BETONIERA', NULL, 'CIFA SRY 1100
MATR. 54624', NULL, '54624', 'ROCCHETTA/POTENZA', 'TE-04-24 DAL 01/07/24', False, False, False, False, False, False, False, False, False, False, true),
  ('B08
(Ex A13B)', NULL, 'BETONIERA 10MC', NULL, 'CIFA SRY 1100
MATR. 54623', NULL, '54623', 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('B09', NULL, 'BETONIERA', NULL, 'CIFA
MATR. 58334', NULL, '58334', 'POMEZIA', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('B10', NULL, 'BETONIERA', NULL, 'CIFA
MATR. 54622', NULL, '54622', 'POMEZIA', NULL, False, False, False, False, False, False, False, False, False, False, true),
  ('I02', NULL, 'IMPALCATO FERROVIARIO', NULL, NULL, NULL, NULL, 'SEDE CAIRO', 'SEDE DAL 17/05/24', False, False, False, False, False, False, False, False, False, False, true),
  ('P01', NULL, 'PILOTINA', NULL, 'PLUSCAB+', NULL, NULL, 'ITALIA MANUTENZIONI', 'OFFICINA', False, False, False, False, False, False, False, False, False, False, true),
  ('P02', NULL, 'PILOTINA', NULL, NULL, NULL, NULL, 'TORRE ANNUNZIATA (NA)', 'SEDE', False, False, False, False, False, False, False, False, False, False, true),
  ('P03', NULL, 'PILOTINA', NULL, NULL, NULL, NULL, 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true),
  ('S01', NULL, 'SCIVOLO POSA CUNICOLI', NULL, NULL, NULL, NULL, 'CANICATTI''', 'IS-01-22', False, False, False, False, False, False, False, False, False, False, true);