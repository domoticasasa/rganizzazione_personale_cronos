-- Accettazione regole/copyright GESTOPRO: prova per utente (cross-device).

alter table public.users
  add column if not exists copyright_accepted_at timestamptz,
  add column if not exists copyright_notice_version text;

comment on column public.users.copyright_accepted_at is
  'Quando l''utente ha confermato Regole e copyright (OK / Ho capito).';
comment on column public.users.copyright_notice_version is
  'Versione del testo regole accettato (es. v1).';

create or replace function public.has_accepted_gestopro_copyright(
  p_notice_version text default 'v1'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  return exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and u.copyright_accepted_at is not null
      and coalesce(u.copyright_notice_version, '') = coalesce(p_notice_version, 'v1')
  );
end;
$$;

create or replace function public.accept_gestopro_copyright(
  p_notice_version text default 'v1'
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz := timezone('utc', now());
  v_ver text := coalesce(nullif(trim(p_notice_version), ''), 'v1');
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  update public.users u
  set
    copyright_accepted_at = v_at,
    copyright_notice_version = v_ver
  where u.auth_id = auth.uid();

  if not found then
    raise exception 'user profile not found';
  end if;

  return v_at;
end;
$$;

grant execute on function public.has_accepted_gestopro_copyright(text) to authenticated;
grant execute on function public.accept_gestopro_copyright(text) to authenticated;

comment on function public.has_accepted_gestopro_copyright(text) is
  'True se l''utente autenticato ha già accettato la versione indicata delle regole GESTOPRO.';
comment on function public.accept_gestopro_copyright(text) is
  'Registra su public.users l''accettazione delle regole/copyright GESTOPRO.';
