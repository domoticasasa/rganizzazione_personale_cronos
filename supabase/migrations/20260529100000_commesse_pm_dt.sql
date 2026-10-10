-- Commesse: PM e DT (da 13-Attribuzione commesse 14-05-26.xlsx)
-- Nota: TE-23-24 nel file aveva 2 righe in conflitto: usato ultimo valore.
-- DT puo' contenere piu' DT (es. 'CASTRONOVO (LFM) - CIBUC (TE)').

alter table public.commesse
  add column if not exists pm text,
  add column if not exists dt text;

update public.commesse set pm='GRIPPO', dt='NICASTRO' where upper(nome)='IS-01-22' or upper(nome) like 'IS-01-22 %';
update public.commesse set pm='PIZZORNO', dt='CIBUC' where upper(nome)='IS-01-24' or upper(nome) like 'IS-01-24 %';
update public.commesse set pm='SCOPECE', dt='CASTRONOVO' where upper(nome)='IS-01-25' or upper(nome) like 'IS-01-25 %';
update public.commesse set pm='BERNINI', dt='BRUNI' where upper(nome)='IS-01-26' or upper(nome) like 'IS-01-26 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='IS-02-24' or upper(nome) like 'IS-02-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='IS-02-25' or upper(nome) like 'IS-02-25 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='IS-04-24' or upper(nome) like 'IS-04-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='LFM-01-22' or upper(nome) like 'LFM-01-22 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='LFM-01-25' or upper(nome) like 'LFM-01-25 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='LFM-01-26' or upper(nome) like 'LFM-01-26 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='LFM-02-24' or upper(nome) like 'LFM-02-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='LFM-02-25' or upper(nome) like 'LFM-02-25 %';
update public.commesse set pm='SCOPECE', dt='CASTRONOVO' where upper(nome)='LFM-02-26' or upper(nome) like 'LFM-02-26 %';
update public.commesse set pm='BERNINI', dt='CASTRONOVO (LFM-IS) - CIBUC (TE)' where upper(nome)='MLD-01-23' or upper(nome) like 'MLD-01-23 %';
update public.commesse set pm='GRIPPO', dt='CIBUC' where upper(nome)='MLD-01-24' or upper(nome) like 'MLD-01-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO (LFM) - CIBUC (TE)' where upper(nome)='MLD-01-25' or upper(nome) like 'MLD-01-25 %';
update public.commesse set pm='SCOPECE', dt='(da definire)' where upper(nome)='MLD-02-22' or upper(nome) like 'MLD-02-22 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='MLD-02-23' or upper(nome) like 'MLD-02-23 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO (LFM) - CIBUC (TE)' where upper(nome)='MLD-02-24' or upper(nome) like 'MLD-02-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO (LFM) - CIBUC (TE)' where upper(nome)='MLD-02-25' or upper(nome) like 'MLD-02-25 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='MLD-03-21' or upper(nome) like 'MLD-03-21 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO (LFM) - CIBUC (TE)' where upper(nome)='MLD-03-24' or upper(nome) like 'MLD-03-24 %';
update public.commesse set pm='GRIPPO', dt='BRUNI' where upper(nome)='MLD-04-21' or upper(nome) like 'MLD-04-21 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO (LFM) - CIBUC (TE)' where upper(nome)='MLD-04-24' or upper(nome) like 'MLD-04-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO (LFM) - CIBUC (TE)' where upper(nome)='MLD-04-25' or upper(nome) like 'MLD-04-25 %';
update public.commesse set pm='SCOPECE', dt='CASTRONOVO' where upper(nome)='SSE-01-25' or upper(nome) like 'SSE-01-25 %';
update public.commesse set pm='GRIPPO', dt='BRUNI' where upper(nome)='TE-01-19' or upper(nome) like 'TE-01-19 %';
update public.commesse set pm='BERNINI', dt='BRUNI' where upper(nome)='TE-01-24' or upper(nome) like 'TE-01-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='TE-01-25' or upper(nome) like 'TE-01-25 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-01-26' or upper(nome) like 'TE-01-26 %';
update public.commesse set pm='GRIPPO', dt='BRUNI' where upper(nome)='TE-02-23' or upper(nome) like 'TE-02-23 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-02-24' or upper(nome) like 'TE-02-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO (LFM) - CIBUC (TE)' where upper(nome)='TE-02-25' or upper(nome) like 'TE-02-25 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-02-26' or upper(nome) like 'TE-02-26 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-03-24' or upper(nome) like 'TE-03-24 %';
update public.commesse set pm='BERNINI', dt='BRUNI' where upper(nome)='TE-04-24' or upper(nome) like 'TE-04-24 %';
update public.commesse set pm='BERNINI', dt='BRUNI' where upper(nome)='TE-04-25' or upper(nome) like 'TE-04-25 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-04-26' or upper(nome) like 'TE-04-26 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='TE-05-24' or upper(nome) like 'TE-05-24 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-05-25' or upper(nome) like 'TE-05-25 %';
update public.commesse set pm='GRIPPO', dt='CIBUC' where upper(nome)='TE-06-22' or upper(nome) like 'TE-06-22 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-06-23' or upper(nome) like 'TE-06-23 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-07-24' or upper(nome) like 'TE-07-24 %';
update public.commesse set pm='BERNINI', dt='BRUNI' where upper(nome)='TE-07-25' or upper(nome) like 'TE-07-25 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-08-23' or upper(nome) like 'TE-08-23 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-08-24' or upper(nome) like 'TE-08-24 %';
update public.commesse set pm='PIZZORNO', dt='CIBUC' where upper(nome)='TE-09-22' or upper(nome) like 'TE-09-22 %';
update public.commesse set pm='BERNINI', dt='BRUNI' where upper(nome)='TE-09-23' or upper(nome) like 'TE-09-23 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-09-24' or upper(nome) like 'TE-09-24 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-09-25' or upper(nome) like 'TE-09-25 %';
update public.commesse set pm='PIZZORNO', dt='CIBUC' where upper(nome)='TE-10-22' or upper(nome) like 'TE-10-22 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-10-25' or upper(nome) like 'TE-10-25 %';
update public.commesse set pm='GRIPPO', dt='BRUNI' where upper(nome)='TE-11-24' or upper(nome) like 'TE-11-24 %';
update public.commesse set pm='GRIPPO', dt='CIBUC' where upper(nome)='TE-12-24' or upper(nome) like 'TE-12-24 %';
update public.commesse set pm='PIZZORNO', dt='CIBUC' where upper(nome)='TE-13-24' or upper(nome) like 'TE-13-24 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-14-24' or upper(nome) like 'TE-14-24 %';
update public.commesse set pm='GRIPPO', dt='CIBUC' where upper(nome)='TE-15-24' or upper(nome) like 'TE-15-24 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-16-24' or upper(nome) like 'TE-16-24 %';
update public.commesse set pm='GRIPPO', dt='BRUNI' where upper(nome)='TE-17-24' or upper(nome) like 'TE-17-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='TE-21-24' or upper(nome) like 'TE-21-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='TE-22-24' or upper(nome) like 'TE-22-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='TE-23-24' or upper(nome) like 'TE-23-24 %';
update public.commesse set pm='SCOPECE', dt='NICASTRO' where upper(nome)='TE-24-24' or upper(nome) like 'TE-24-24 %';
update public.commesse set pm='BERNINI', dt='BRUNI' where upper(nome)='TE-25-24' or upper(nome) like 'TE-25-24 %';
update public.commesse set pm='SCOPECE', dt='NICASTRO' where upper(nome)='TE-26-24' or upper(nome) like 'TE-26-24 %';
update public.commesse set pm='BERNINI', dt='CIBUC' where upper(nome)='TE-28-24' or upper(nome) like 'TE-28-24 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='TG-01-24' or upper(nome) like 'TG-01-24 %';
update public.commesse set pm='BERNINI', dt='CASTRONOVO' where upper(nome)='TLC-01-22' or upper(nome) like 'TLC-01-22 %';
update public.commesse set pm='PIZZORNO', dt='BRUNI' where upper(nome)='TLC-01-25' or upper(nome) like 'TLC-01-25 %';
update public.commesse set pm='SCOPECE', dt='CASTRONOVO' where upper(nome)='TLC-03-25' or upper(nome) like 'TLC-03-25 %';
update public.commesse set pm='PIZZORNO', dt='CASTRONOVO' where upper(nome)='TLC-05-20' or upper(nome) like 'TLC-05-20 %';
