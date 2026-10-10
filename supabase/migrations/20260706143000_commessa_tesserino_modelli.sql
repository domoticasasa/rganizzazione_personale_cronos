-- Modelli tesserino per commessa (righe aggiuntive variabili) + storage su personale.

alter table public.personale
  add column if not exists tesserino_righe_extra jsonb,
  add column if not exists tesserino_commessa_id_uuid uuid references public.commesse (id_uuid) on delete set null;

comment on column public.personale.tesserino_righe_extra is
  'Righe libere in fondo al tesserino (array JSON di stringhe).';
comment on column public.personale.tesserino_commessa_id_uuid is
  'Commessa di riferimento per il modello tesserino applicato.';

create table if not exists public.commessa_tesserino_modelli (
  id_uuid uuid primary key default gen_random_uuid(),
  commessa_id_uuid uuid not null references public.commesse (id_uuid) on delete cascade,
  righe_extra jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint commessa_tesserino_modelli_righe_array check (jsonb_typeof(righe_extra) = 'array')
);

create unique index if not exists commessa_tesserino_modelli_commessa_uq
  on public.commessa_tesserino_modelli (commessa_id_uuid);

create or replace function public.set_commessa_tesserino_modelli_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_commessa_tesserino_modelli_audit on public.commessa_tesserino_modelli;
create trigger trg_commessa_tesserino_modelli_audit
before insert or update on public.commessa_tesserino_modelli
for each row execute function public.set_commessa_tesserino_modelli_audit();

alter table public.commessa_tesserino_modelli enable row level security;

drop policy if exists commessa_tesserino_modelli_select on public.commessa_tesserino_modelli;
create policy commessa_tesserino_modelli_select
on public.commessa_tesserino_modelli
for select
to authenticated
using (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_formazione',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('tesserini')
  or public.has_custom_page_access('tesserino')
);

drop policy if exists commessa_tesserino_modelli_write on public.commessa_tesserino_modelli;
create policy commessa_tesserino_modelli_write
on public.commessa_tesserino_modelli
for all
to authenticated
using (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_formazione',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('tesserini')
)
with check (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_formazione',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('tesserini')
);
