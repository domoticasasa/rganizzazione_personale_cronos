alter table public.logistica_mdo_ferroviari
  add column if not exists doc_verifica_annuale_check boolean not null default false,
  add column if not exists doc_verifica_annuale_checked_at timestamptz,
  add column if not exists doc_verifica_annuale_checked_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  add column if not exists doc_allegato_p_check boolean not null default false,
  add column if not exists doc_allegato_p_checked_at timestamptz,
  add column if not exists doc_allegato_p_checked_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  add column if not exists doc_verifica_annuale_richiesta_sostituzione boolean not null default false,
  add column if not exists doc_verifica_annuale_richiesta_sostituzione_at timestamptz,
  add column if not exists doc_verifica_annuale_richiesta_sostituzione_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  add column if not exists doc_allegato_p_richiesta_sostituzione boolean not null default false,
  add column if not exists doc_allegato_p_richiesta_sostituzione_at timestamptz,
  add column if not exists doc_allegato_p_richiesta_sostituzione_by_user_uuid uuid references public.users(id_uuid) on delete set null;
