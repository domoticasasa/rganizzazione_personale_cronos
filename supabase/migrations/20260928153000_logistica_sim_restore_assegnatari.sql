-- Ripristina assegnatari SIM dallo seed Excel originale
-- (erano stati azzerati; i numeri restano invariati).

update public.logistica_sim s
set
  assegnatario = v.assegnatario,
  data_assegnazione = coalesce(s.data_assegnazione, current_date),
  updated_at = now()
from (
  values
  ('3397998105', 'Afflitto G.'),
  ('3397952987', 'Afflitto G.'),
  ('3333231685', 'Alberghi R.'),
  ('3397997466', 'Antonaci G'),
  ('3397997637', 'Benzo A.'),
  ('3331895328', 'Bernini G.'),
  ('3349937052', 'Bernini G.'),
  ('3349937055', 'Bloise C.'),
  ('3349937049', 'Bruni G.'),
  ('3317472357', 'Bruni G.'),
  ('3355326782', 'Bruni G.'),
  ('3666365841', 'Caldarola L.'),
  ('3331895327', 'Castronovo P.'),
  ('3349937031', 'Castronovo P.'),
  ('3356174627', 'Casucci G.'),
  ('3397952979', 'Chiaravalloti M.'),
  ('3331895329', 'Cibuc A.'),
  ('3349937042', 'Cibuc A.'),
  ('3355238484', 'Cibuc A.'),
  ('3355220134', 'Cibuc A.'),
  ('3317472352', 'De Bonis T.'),
  ('3357953308', 'De Bonis T.'),
  ('3388296015', 'De Filippis D.'),
  ('3333275598', 'DISPONIBILE IN SEDE'),
  ('3317472354', 'Fracchia C.'),
  ('3331849774', 'Grippo P.'),
  ('3349937038', 'Grippo P.'),
  ('3351441361', 'Guarnaschella G.'),
  ('3349937033', 'Guarnaschella G.'),
  ('3383383382', 'Hysa A.'),
  ('3349937068', 'Mammucari I.'),
  ('3386740224', 'Manconi R.'),
  ('3349937036', 'MERLI ANDREA'),
  ('3386200627', 'MERLI ANDREA'),
  ('3356249919', 'Monti A.'),
  ('3317472362', 'Moro A.'),
  ('3386181689', 'Murgia S.'),
  ('3397952980', 'Nicastro M.'),
  ('3388296206', 'Patrucco A.'),
  ('3316167223', 'Pecorella D.'),
  ('3333222743', 'Pizzorno D.'),
  ('3356742107', 'Puccio V.'),
  ('3338086476', 'Ribaudo O.'),
  ('3387192156', 'Ribaudo O.'),
  ('3346038898', 'Rizzolo S.'),
  ('3349937043', 'Rizzolo S. (IN SEGUITO DISPONIBILE IN SEDE)'),
  ('3317472350', 'Scopece A.'),
  ('3356810678', 'Scopece F.'),
  ('3333209934', 'Shabestary M.'),
  ('3349937034', 'Tagliero A.'),
  ('3316126637', 'Tancredi V.'),
  ('3349937119', 'TAVANI (ROMA)'),
  ('3346034769', 'Vencia G.'),
  ('3349937123', 'Vencia G.'),
  ('3385018125', 'Vivian L.'),
  ('3666323020', 'Vivian L.'),
  ('3317472361', 'Xhima A.')
) as v(numero_linea, assegnatario)
where lower(trim(s.numero_linea)) = lower(trim(v.numero_linea))
  and s.active = true
  and (
    s.assegnatario is null
    or trim(s.assegnatario) = ''
  );
