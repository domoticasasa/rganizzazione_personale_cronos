-- Regola numero tesserino: PREFIX(6) = 3 lettere cognome + 3 lettere nome;
-- suffisso SSNNN (serie 01..99, progressivo 001). Omònimi: PATGIU01001 → PATGIU02001.

create or replace function public.personale_tesserino_letters(src text, n int)
returns text
language plpgsql
immutable
as $$
declare
  i int;
  ch text;
  out text := '';
  norm text;
begin
  if n <= 0 then
    return '';
  end if;
  norm := upper(regexp_replace(coalesce(src, ''), '[^[:alpha:]]', '', 'g'));
  i := 1;
  while length(out) < n and i <= length(norm) loop
    ch := substr(norm, i, 1);
    if ch ~ '^[A-Z]$' then
      out := out || ch;
    elsif ch in ('À', 'Á', 'Â', 'Ä', 'Ã') then
      out := out || 'A';
    elsif ch in ('È', 'É', 'Ê', 'Ë') then
      out := out || 'E';
    elsif ch in ('Ì', 'Í', 'Î', 'Ï') then
      out := out || 'I';
    elsif ch in ('Ò', 'Ó', 'Ô', 'Ö') then
      out := out || 'O';
    elsif ch in ('Ù', 'Ú', 'Û', 'Ü') then
      out := out || 'U';
    elsif ch = 'Ç' then
      out := out || 'C';
    elsif ch = 'Ñ' then
      out := out || 'N';
    end if;
    i := i + 1;
  end loop;
  while length(out) < n loop
    out := out || 'X';
  end loop;
  return out;
end;
$$;

create or replace function public.personale_tesserino_prefix(p_full_name text)
returns text
language plpgsql
immutable
as $$
declare
  parts text[];
  cognome text;
  nome text;
begin
  parts := regexp_split_to_array(trim(coalesce(p_full_name, '')), '\s+');
  if parts is null or coalesce(array_length(parts, 1), 0) = 0 then
    return 'XXXXXX';
  end if;
  cognome := parts[1];
  if coalesce(array_length(parts, 1), 0) = 1 then
    nome := '';
  else
    nome := array_to_string(parts[2:array_length(parts, 1)], ' ');
  end if;
  return public.personale_tesserino_letters(cognome, 3)
    || public.personale_tesserino_letters(nome, 3);
end;
$$;

create or replace function public.personale_next_numero_tesserino(
  p_prefix text,
  p_exclude_id bigint default null
)
returns text
language plpgsql
stable
as $$
declare
  p text := upper(trim(coalesce(p_prefix, '')));
  max_serie int := 0;
  r record;
  serie int;
  code text;
begin
  if length(p) < 6 then
    p := 'XXXXXX';
  end if;

  for r in
    select numero_tesserino
    from public.personale
    where numero_tesserino is not null
      and trim(numero_tesserino) <> ''
      and upper(trim(numero_tesserino)) ~ ('^' || p || '[0-9]{5}$')
      and (p_exclude_id is null or id <> p_exclude_id)
  loop
    code := upper(trim(r.numero_tesserino));
    serie := substring(code from length(p) + 1 for 2)::int;
    if serie > max_serie then
      max_serie := serie;
    end if;
  end loop;

  return p || lpad((max_serie + 1)::text, 2, '0') || '001';
end;
$$;

create or replace function public.personale_set_numero_tesserino_trigger()
returns trigger
language plpgsql
as $$
begin
  if new.numero_tesserino is not null and trim(new.numero_tesserino) <> '' then
    return new;
  end if;
  new.numero_tesserino := public.personale_next_numero_tesserino(
    public.personale_tesserino_prefix(new.full_name),
    new.id
  );
  return new;
end;
$$;

drop trigger if exists trg_personale_numero_tesserino on public.personale;
drop trigger if exists personale_numero_tesserino_trigger on public.personale;

create trigger trg_personale_numero_tesserino
before insert or update of full_name, numero_tesserino
on public.personale
for each row
execute function public.personale_set_numero_tesserino_trigger();

create unique index if not exists personale_numero_tesserino_unique
  on public.personale (numero_tesserino)
  where numero_tesserino is not null and trim(numero_tesserino) <> '';

comment on function public.personale_next_numero_tesserino(text, bigint) is
  'Prossimo N. tesserino: prefisso 6 lettere + serie incrementale (01,02,…) + 001.';
