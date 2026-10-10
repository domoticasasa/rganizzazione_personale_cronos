-- Verifica integrita PDF firmato vs ledger (admin).

create or replace function public.doc_firma_verify_integrity(
  p_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sha text := lower(trim(coalesce(p_sha256, '')));
  v_matches jsonb := '[]'::jsonb;
  r record;
  v_hmac_ok boolean;
  v_payload text;
  v_expected text;
  v_count integer := 0;
begin
  if not public.is_doc_firma_admin() then
    raise exception 'forbidden';
  end if;

  if length(v_sha) < 32 then
    raise exception 'sha256 required';
  end if;

  for r in
    select
      a.id as assignment_id,
      a.batch_id,
      a.status,
      a.signed_at,
      a.signed_pdf_sha256,
      a.signature_meta,
      b.title as batch_title,
      e.id as evidence_id,
      e.evidence_hmac,
      e.server_ts as evidence_ts,
      e.payload as evidence_payload,
      e.document_seal as evidence_seal,
      e.page_codes as evidence_page_codes,
      e.original_sha256 as evidence_original_sha256
    from public.doc_firma_assignments a
    left join public.doc_firma_batches b on b.id = a.batch_id
    left join lateral (
      select *
      from public.doc_firma_evidence e0
      where e0.assignment_id = a.id
         or (
           e0.assignment_id is null
           and e0.signed_sha256 = a.signed_pdf_sha256
         )
      order by e0.created_at desc
      limit 1
    ) e on true
    where a.status = 'signed'
      and (
        lower(coalesce(a.signed_pdf_sha256, '')) = v_sha
        or lower(coalesce(a.signature_meta->>'signed_sha256', '')) = v_sha
      )
  loop
    v_count := v_count + 1;
    v_hmac_ok := null;
    if r.evidence_hmac is not null and r.evidence_payload is not null then
      v_payload := coalesce(
        r.evidence_payload->>'payload_canon',
        concat_ws(
          '|',
          coalesce(r.assignment_id::text, ''),
          coalesce(r.batch_id::text, ''),
          coalesce(r.evidence_original_sha256, r.signature_meta->>'original_sha256', ''),
          v_sha,
          coalesce(r.evidence_seal, r.signature_meta->>'document_seal', ''),
          coalesce(r.evidence_payload->>'ts_token_id', r.signature_meta->>'ts_token_id', ''),
          coalesce(r.evidence_payload->>'ts_nonce', r.signature_meta->>'ts_nonce', ''),
          coalesce(r.evidence_ts::text, r.signature_meta->>'server_timestamp', '')
        )
      );
      -- Se c'e' payload_canon usalo cosi' com'e'; altrimenti il rebuild puo' non coincidere
      -- se il formato e' quello salvato alla firma.
      if (r.evidence_payload ? 'payload_canon') then
        v_payload := r.evidence_payload->>'payload_canon';
      end if;
      v_expected := public.doc_firma_evidence_hmac(v_payload);
      v_hmac_ok := (v_expected = r.evidence_hmac);
    end if;

    v_matches := v_matches || jsonb_build_array(
      jsonb_build_object(
        'assignment_id', r.assignment_id,
        'batch_id', r.batch_id,
        'batch_title', r.batch_title,
        'status', r.status,
        'signed_at', r.signed_at,
        'signer_name', r.signature_meta->>'signer_name',
        'signer_email', r.signature_meta->>'signer_email',
        'document_seal', coalesce(r.evidence_seal, r.signature_meta->>'document_seal'),
        'server_timestamp', coalesce(r.evidence_ts::text, r.signature_meta->>'server_timestamp'),
        'page_codes', coalesce(r.evidence_page_codes, r.signature_meta->'page_codes'),
        'original_sha256', coalesce(r.evidence_original_sha256, r.signature_meta->>'original_sha256'),
        'hash_match', true,
        'evidence_id', r.evidence_id,
        'evidence_hmac_ok', v_hmac_ok,
        'protections', r.signature_meta->'protections'
      )
    );
  end loop;

  -- Cerca anche solo nel ledger (assignment gia' purged).
  if v_count = 0 then
    for r in
      select
        e.assignment_id,
        e.batch_id,
        e.signed_sha256,
        e.evidence_hmac,
        e.server_ts as evidence_ts,
        e.payload as evidence_payload,
        e.document_seal as evidence_seal,
        e.page_codes as evidence_page_codes,
        e.original_sha256 as evidence_original_sha256,
        e.id as evidence_id,
        b.title as batch_title
      from public.doc_firma_evidence e
      left join public.doc_firma_batches b on b.id = e.batch_id
      where lower(coalesce(e.signed_sha256, '')) = v_sha
      order by e.created_at desc
      limit 5
    loop
      v_count := v_count + 1;
      v_hmac_ok := null;
      if r.evidence_hmac is not null and (r.evidence_payload ? 'payload_canon') then
        v_expected := public.doc_firma_evidence_hmac(r.evidence_payload->>'payload_canon');
        v_hmac_ok := (v_expected = r.evidence_hmac);
      end if;
      v_matches := v_matches || jsonb_build_array(
        jsonb_build_object(
          'assignment_id', r.assignment_id,
          'batch_id', r.batch_id,
          'batch_title', r.batch_title,
          'status', 'evidence_only',
          'signed_at', r.evidence_ts,
          'signer_name', r.evidence_payload->>'signer_name',
          'signer_email', r.evidence_payload->>'signer_email',
          'document_seal', r.evidence_seal,
          'server_timestamp', r.evidence_ts,
          'page_codes', r.evidence_page_codes,
          'original_sha256', r.evidence_original_sha256,
          'hash_match', true,
          'evidence_id', r.evidence_id,
          'evidence_hmac_ok', v_hmac_ok,
          'protections', r.evidence_payload->'protections'
        )
      );
    end loop;
  end if;

  if v_count = 0 then
    return jsonb_build_object(
      'ok', false,
      'verdict', 'sconosciuto_o_manomesso',
      'file_sha256', v_sha,
      'matches', '[]'::jsonb,
      'message',
        'Nessun PDF firmato in CRONOS corrisponde a questo hash. '
        'Il file e sconosciuto oppure e stato modificato dopo la firma.'
    );
  end if;

  -- Se almeno un match ha HMAC false => manomesso; se HMAC null ma hash ok => integro (hash).
  if exists (
    select 1
    from jsonb_array_elements(v_matches) m
    where (m->>'evidence_hmac_ok') = 'false'
  ) then
    return jsonb_build_object(
      'ok', false,
      'verdict', 'manomesso',
      'file_sha256', v_sha,
      'matches', v_matches,
      'message',
        'Hash trovato ma la firma HMAC delle evidenze non torna: possibile manomissione dei metadati.'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'verdict', 'integro',
    'file_sha256', v_sha,
    'matches', v_matches,
    'message',
      'Il documento coincide byte-per-byte con un PDF firmato registrato in CRONOS. '
      'Integrita verificata tramite hash SHA-256 e, se presente, HMAC del ledger evidenze.'
  );
end;
$$;

grant execute on function public.doc_firma_verify_integrity(text) to authenticated;

comment on function public.doc_firma_verify_integrity(text) is
  'Admin: confronta SHA-256 PDF con assignment/evidence e verifica HMAC ledger.';
