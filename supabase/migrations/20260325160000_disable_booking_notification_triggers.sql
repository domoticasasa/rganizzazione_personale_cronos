-- Disabilita trigger che inseriscono notifiche automatiche su bookings
-- (per evitare doppi invii rispetto alle Edge Function: admin-send-notification).
--
-- Lasciamo attivi:
-- - trigger di stamp updated_by (set_updated_by_from_jwt)
-- - trigger push su notifications (push_notifications_webhook)

-- Hotel/Pernottamenti
ALTER TABLE public.bookings DISABLE TRIGGER trg_new_booking;
ALTER TABLE public.bookings DISABLE TRIGGER trg_update_booking;
ALTER TABLE public.bookings DISABLE TRIGGER trg_delete_booking;

-- Treni
ALTER TABLE public.bookings_treno DISABLE TRIGGER trg_new_booking_treno;
ALTER TABLE public.bookings_treno DISABLE TRIGGER trg_update_booking_treno;
ALTER TABLE public.bookings_treno DISABLE TRIGGER trg_delete_booking_treno;

-- Aerei
ALTER TABLE public.bookings_aereo DISABLE TRIGGER trg_new_booking_aereo;
ALTER TABLE public.bookings_aereo DISABLE TRIGGER trg_update_booking_aereo;
ALTER TABLE public.bookings_aereo DISABLE TRIGGER trg_delete_booking_aereo;

