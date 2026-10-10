-- QR viaggio mezzo: accetta URL HTTPS `?vm=` (fotocamera nativa) oltre a CRONOS-VM:

create or replace function public.parse_viaggio_mezzo_qr_token(p_raw text)
returns text
language plpgsql
immutable
as $$
declare
  v_token text;
  v_vm text;
begin
  v_token := trim(coalesce(p_raw, ''));
  if v_token = '' then
    return null;
  end if;

  v_vm := substring(v_token from '[?&][Vv][Mm]=([^&#]+)');
  if v_vm is not null and trim(v_vm) <> '' then
    v_token := trim(v_vm);
  end if;

  if upper(v_token) like 'CRONOS-VM:%' then
    v_token := trim(substring(v_token from position(':' in v_token) + 1));
  end if;

  if v_token = '' then
    return null;
  end if;
  return v_token;
end;
$$;
