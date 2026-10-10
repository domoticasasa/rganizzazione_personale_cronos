alter table public.logistica_mdo_ferroviari
  add column if not exists doc_carte_circolazione_check boolean not null default false,
  add column if not exists doc_carte_circolazione_checked_at timestamptz,
  add column if not exists doc_carte_circolazione_checked_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  add column if not exists doc_manuale_uso_manutenzione_check boolean not null default false,
  add column if not exists doc_manuale_uso_manutenzione_checked_at timestamptz,
  add column if not exists doc_manuale_uso_manutenzione_checked_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  add column if not exists doc_libro_bordo_check boolean not null default false,
  add column if not exists doc_libro_bordo_checked_at timestamptz,
  add column if not exists doc_libro_bordo_checked_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  add column if not exists doc_diario_manutenzione_check boolean not null default false,
  add column if not exists doc_diario_manutenzione_checked_at timestamptz,
  add column if not exists doc_diario_manutenzione_checked_by_user_uuid uuid references public.users(id_uuid) on delete set null;
