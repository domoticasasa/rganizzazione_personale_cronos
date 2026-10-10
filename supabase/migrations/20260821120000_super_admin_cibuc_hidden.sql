-- Super admin «Cibuc Alexandru (admin)»: ruolo pieno, nascosto da elenchi app.
-- Il dipendente omonimo (senza «(admin)») resta visibile.

alter table public.personale
  add column if not exists hidden_from_directory boolean not null default false;

comment on column public.personale.hidden_from_directory is
  'Se true: non compare in elenchi/selettori (formazione, attestati, tesserini, …).';

create index if not exists personale_hidden_from_directory_idx
  on public.personale (hidden_from_directory)
  where hidden_from_directory = true;

update public.users
set
  role = 'admin_generale',
  hidden_from_directory = true
where lower(trim(coalesce(role, ''))) not in ('dt', 'assistente_dt')
  and (
    lower(regexp_replace(trim(coalesce(full_name, '')), '\s+', ' ', 'g'))
      in (
        'cibuc alexandru (admin)',
        'alexandru cibuc (admin)',
        'alexandru admin cibuc',
        'alexandru cibuc admin'
      )
    or lower(trim(coalesce(username, ''))) in (
      'cibuc.alexandru.admin',
      'alexandru.cibuc.admin',
      'cibuc_alexandru_admin',
      'admin.cibuc',
      'cibuc.admin'
    )
    or lower(trim(coalesce(full_name, ''))) like '%(admin)%'
  );

update public.personale
set hidden_from_directory = true
where hidden_from_directory = false
  and (
    lower(regexp_replace(trim(coalesce(full_name, '')), '\s+', ' ', 'g'))
      in (
        'cibuc alexandru (admin)',
        'alexandru cibuc (admin)',
        'alexandru admin cibuc',
        'alexandru cibuc admin'
      )
    or lower(trim(coalesce(full_name, ''))) like '%(admin)%'
  );
