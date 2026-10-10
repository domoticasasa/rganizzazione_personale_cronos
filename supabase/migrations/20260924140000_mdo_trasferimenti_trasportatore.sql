-- Trasportatore libero su trasferimenti MDO.

alter table public.logistica_mdo_trasferimenti
  add column if not exists trasportatore text;

comment on column public.logistica_mdo_trasferimenti.trasportatore is
  'Nome/ditta trasportatore (testo libero).';

-- Concessioni già presenti sulla tabella; ripetute per sicurezza post-Oct 2026.
grant select, insert, update, delete
  on public.logistica_mdo_trasferimenti to authenticated;
grant select, insert, update, delete
  on public.logistica_mdo_trasferimenti to service_role;
