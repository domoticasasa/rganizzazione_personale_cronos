-- Admin/DT possono leggere token e subscription per diagnostica notifiche.
-- (Insert/update restano “solo i propri”.)

drop policy if exists "device tokens select staff" on public.device_tokens;
create policy "device tokens select staff"
on public.device_tokens
for select
to authenticated
using (
  exists (
    select 1
    from public.users me
    where (me.auth_id = auth.uid() or me.id_uuid = auth.uid())
      and lower(coalesce(me.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'dt',
        'assistente_dt'
      )
  )
);

drop policy if exists "web push select staff" on public.web_push_subscriptions;
create policy "web push select staff"
on public.web_push_subscriptions
for select
to authenticated
using (
  exists (
    select 1
    from public.users me
    where (me.auth_id = auth.uid() or me.id_uuid = auth.uid())
      and lower(coalesce(me.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'dt',
        'assistente_dt'
      )
  )
);
