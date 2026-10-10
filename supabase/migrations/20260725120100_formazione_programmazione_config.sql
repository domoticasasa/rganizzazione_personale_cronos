-- Configurazione condivisa programmazione corsi (es. auto-rimozione RFI).



create table if not exists public.formazione_programmazione_config (

  config_key text primary key,

  config_value jsonb not null default 'true'::jsonb,

  updated_at timestamptz not null default now(),

  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null

);



comment on table public.formazione_programmazione_config is

  'Flag e impostazioni globali per le schermate programmazione corsi.';



insert into public.formazione_programmazione_config (config_key, config_value)

values ('rfi_auto_purge_after_course_end', 'true'::jsonb)

on conflict (config_key) do nothing;



grant select, insert, update, delete on public.formazione_programmazione_config to authenticated;



alter table public.formazione_programmazione_config enable row level security;



drop policy if exists formazione_programmazione_config_select on public.formazione_programmazione_config;

create policy formazione_programmazione_config_select

on public.formazione_programmazione_config

for select

to authenticated

using (true);



drop policy if exists formazione_programmazione_config_write on public.formazione_programmazione_config;

create policy formazione_programmazione_config_write

on public.formazione_programmazione_config

for all

to authenticated

using (

  exists (

    select 1 from public.users u

    where u.auth_id = auth.uid()

      and lower(coalesce(u.role, '')) in (

        'admin',

        'admin_generale',

        'admin_formazione',

        'admin_pernottamenti',

        'admin_trenoaereo',

        'admin_dpi',

        'uqsa',

        'dt',

        'assistente_dt'

      )

  )

)

with check (

  exists (

    select 1 from public.users u

    where u.auth_id = auth.uid()

      and lower(coalesce(u.role, '')) in (

        'admin',

        'admin_generale',

        'admin_formazione',

        'admin_pernottamenti',

        'admin_trenoaereo',

        'admin_dpi',

        'uqsa',

        'dt',

        'assistente_dt'

      )

  )

);

