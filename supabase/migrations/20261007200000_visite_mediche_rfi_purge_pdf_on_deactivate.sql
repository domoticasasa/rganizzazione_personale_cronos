-- Quando una visita RFI viene disattivata (anche dall’automatismo post-data),
-- cancella il PDF dallo storage e azzera i campi allegato.

create or replace function public.purge_visite_mediche_rfi_pdf_on_leave_active()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  -- DELETE riga: rimuovi file storage
  if tg_op = 'DELETE' then
    if coalesce(nullif(trim(old.pdf_file_path), ''), '') <> '' then
      delete from storage.objects
      where bucket_id = 'visite_mediche_rfi'
        and name = old.pdf_file_path;
    end if;
    return old;
  end if;

  -- UPDATE: passa da attiva a non attiva → togli PDF
  if tg_op = 'UPDATE'
     and old.active is true
     and new.active is false then
    if coalesce(nullif(trim(old.pdf_file_path), ''), '') <> '' then
      delete from storage.objects
      where bucket_id = 'visite_mediche_rfi'
        and name = old.pdf_file_path;
    end if;
    new.pdf_file_path := null;
    new.pdf_file_name := null;
    new.pdf_mime_type := null;
    new.pdf_file_size := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_purge_visite_mediche_rfi_pdf
  on public.visite_mediche_rfi;
drop trigger if exists trg_purge_visite_mediche_rfi_pdf_on_leave_active
  on public.visite_mediche_rfi;

create trigger trg_purge_visite_mediche_rfi_pdf_on_leave_active
before update or delete on public.visite_mediche_rfi
for each row
execute function public.purge_visite_mediche_rfi_pdf_on_leave_active();

-- Rimuove la vecchia funzione solo-delete se non più usata.
drop function if exists public.purge_visite_mediche_rfi_pdf_on_delete();

notify pgrst, 'reload schema';
