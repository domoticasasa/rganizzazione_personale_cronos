-- Aggiorna label pagina registry.
insert into public.app_page_registry (page_key, label, active)
values ('documenti_firma', 'Firma digitale', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;
