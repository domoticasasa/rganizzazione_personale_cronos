-- POS: DT e Assistente DT possono inserire / modificare / eliminare
-- (stesso permesso già usato in app da canManagePosDipendentiLista).

create or replace function public.is_pos_commessa_dipendenti_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.cronos_has_role(
      'admin',
      'admin_generale',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_formazione',
      'uqsa',
      'dt',
      'assistente_dt'
    )
    or public.has_custom_page_access('pos_dipendenti_lista');
$$;

grant execute on function public.is_pos_commessa_dipendenti_manager() to authenticated;
