-- Stabilizza "Inserito da" su bookings:
-- autore creazione separato da updated_by (ultimo modificatore).

alter table public.bookings
  add column if not exists created_by text;

-- Backfill storico:
-- 1) se c'e' updated_by usiamo quello
-- 2) altrimenti dt_user_uuid
update public.bookings
set created_by = coalesce(
  nullif(trim(created_by), ''),
  nullif(trim(updated_by::text), ''),
  nullif(trim(dt_user_uuid::text), '')
)
where coalesce(trim(created_by), '') = '';

