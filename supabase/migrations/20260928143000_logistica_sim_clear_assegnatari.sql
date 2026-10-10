-- Seed SIM: solo numeri, senza assegnatario precompilato
-- (le assegnazioni si caricano da Excel o si inseriscono a mano).

update public.logistica_sim
set
  assegnatario = null,
  data_assegnazione = null
where active = true
  and assegnatario is not null;
