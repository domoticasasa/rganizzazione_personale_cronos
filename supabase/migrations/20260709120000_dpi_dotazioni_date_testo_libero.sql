-- Produzione e revisione DPI: testo libero (es. solo mese/anno).

alter table public.dpi_dotazioni
  alter column data_produzione type text using
    case
      when data_produzione is null then null
      else to_char(data_produzione, 'DD-MM-YYYY')
    end,
  alter column data_revisione type text using
    case
      when data_revisione is null then null
      else to_char(data_revisione, 'DD-MM-YYYY')
    end;
