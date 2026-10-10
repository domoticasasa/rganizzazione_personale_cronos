alter table public.estintori
  add column if not exists richiesta_sostituzione boolean not null default false,
  add column if not exists richiesta_sostituzione_at timestamptz,
  add column if not exists richiesta_sostituzione_by_user_uuid uuid references public.users(id_uuid) on delete set null;

create index if not exists idx_estintori_richiesta_sostituzione
  on public.estintori (richiesta_sostituzione, richiesta_sostituzione_at);

alter table public.logistica_casette_ps
  add column if not exists richiesta_sostituzione boolean not null default false,
  add column if not exists richiesta_sostituzione_at timestamptz,
  add column if not exists richiesta_sostituzione_by_user_uuid uuid references public.users(id_uuid) on delete set null;

create index if not exists idx_logistica_casette_ps_richiesta_sostituzione
  on public.logistica_casette_ps (richiesta_sostituzione, richiesta_sostituzione_at);
