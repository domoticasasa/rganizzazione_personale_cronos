-- Ordine globale tile/pulsanti dashboard (solo admin modifica; tutti leggono).

create table if not exists public.app_ui_layout_order (
  layout_key text primary key,
  item_keys jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null
);

comment on table public.app_ui_layout_order is
  'Ordine voci UI condiviso (es. dashboard admin). Solo admin possono aggiornare.';

grant select on public.app_ui_layout_order to authenticated;
grant insert, update, delete on public.app_ui_layout_order to authenticated;

alter table public.app_ui_layout_order enable row level security;

create or replace function public.is_cronos_admin_role()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_treno_aereo'
      )
  );
$$;

drop policy if exists app_ui_layout_order_select on public.app_ui_layout_order;
create policy app_ui_layout_order_select
on public.app_ui_layout_order
for select
to authenticated
using (true);

drop policy if exists app_ui_layout_order_write on public.app_ui_layout_order;
create policy app_ui_layout_order_write
on public.app_ui_layout_order
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());
