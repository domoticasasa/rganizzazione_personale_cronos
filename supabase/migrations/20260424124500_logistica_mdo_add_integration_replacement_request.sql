alter table public.logistica_mdo_ferroviari
  add column if not exists richiesta_integrazione_sostituzione boolean not null default false,
  add column if not exists richiesta_integrazione_sostituzione_at timestamptz,
  add column if not exists richiesta_integrazione_sostituzione_by_user_uuid uuid references public.users(id_uuid) on delete set null;

create index if not exists idx_logistica_mdo_richiesta_integrazione_sostituzione
  on public.logistica_mdo_ferroviari (richiesta_integrazione_sostituzione, richiesta_integrazione_sostituzione_at);
