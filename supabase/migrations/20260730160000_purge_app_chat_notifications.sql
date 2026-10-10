-- Rimuove dalla pagina Notifiche le entry generate dalla chat.
delete from public.notifications
where coalesce(meta->>'type', '') = 'app_chat'
   or coalesce(meta->>'action', '') in ('app_chat_dm', 'app_chat_group')
   or title like 'GESTOPRO Chat%';
