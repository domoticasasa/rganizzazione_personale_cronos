insert into public.app_page_registry (page_key, label, active)
values ('mdo_check_riepilogo', 'Riepilogo check MDO', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;
