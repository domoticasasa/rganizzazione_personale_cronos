-- Nasconde account di servizio/controllo dalle liste (chat, DT, notifiche, ecc.)
-- senza disattivare login né permessi admin.

alter table public.users
  add column if not exists hidden_from_directory boolean not null default false;

comment on column public.users.hidden_from_directory is
  'Se true: non compare in elenchi/selettori app (chat, assegnazioni DT, notifiche test, …). Login e diritti restano attivi.';

create index if not exists users_hidden_from_directory_idx
  on public.users (hidden_from_directory)
  where hidden_from_directory = true;

-- Account admin di controllo omonimi al DT: nascondi solo ruoli admin* (non DT).
update public.users
set hidden_from_directory = true
where hidden_from_directory = false
  and lower(trim(coalesce(role, ''))) like 'admin%'
  and (
    lower(regexp_replace(trim(coalesce(full_name, '')), '\s+', ' ', 'g'))
      in (
        'cibuc alexandru',
        'alexandru cibuc',
        'cibuc alexandru (admin)',
        'alexandru admin cibuc',
        'alexandru cibuc admin'
      )
    or lower(trim(coalesce(username, ''))) like 'cibuc.alexandru%'
    or lower(trim(coalesce(username, ''))) like 'alexandru.cibuc%'
    or lower(trim(coalesce(username, ''))) like 'cibuc\_%' escape '\'
    or lower(trim(coalesce(username, ''))) in (
      'cibuc.alexandru',
      'alexandru.cibuc',
      'cibuc_alexandru',
      'admin.cibuc'
    )
  );
