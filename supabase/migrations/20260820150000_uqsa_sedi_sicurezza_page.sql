insert into public.app_page_registry (page_key, label, active)
values
  (
    'uqsa_sedi_sicurezza',
    'UQSA — Sedi sicurezza (BOX/MDO · estintori/casette)',
    true
  )
on conflict (page_key) do update
set label = excluded.label,
    active = true;
