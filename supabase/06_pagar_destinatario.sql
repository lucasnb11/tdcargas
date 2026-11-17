-- Quitação atômica dos saldos de um destinatário em um manifesto.
create or replace function public.td_pagar_destinatario(p_manifest_id text,p_recipient_key text,p_expected_amount bigint,p_expected_count integer,p_date text,p_method text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;m jsonb;r jsonb;idx integer;entry jsonb;row_ids text[]:=array[]::text[];row_id text;balance bigint;total bigint:=0;batch_id uuid:=gen_random_uuid();canonical_key text;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado'; end if;
 canonical_key=upper(regexp_replace(trim(p_recipient_key),'[[:space:]]+',' ','g'));
 if canonical_key is null or length(canonical_key) not between 1 and 200 or p_expected_amount is null or p_expected_amount<=0 or p_expected_count is null or p_expected_count<1 then raise exception 'Destinatário ou total inválido'; end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 if m is null then raise exception 'Manifesto não encontrado'; end if;
 for r in select value from jsonb_array_elements(m->'rows') loop
  if upper(regexp_replace(trim(r->>'client'),'[[:space:]]+',' ','g')) is distinct from canonical_key then continue; end if;
  if p.perfil='entregador' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade)) then continue; end if;
  balance=(r->>'freight')::bigint-coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),0);
  if balance<0 then raise exception 'Há um conhecimento com saldo inconsistente'; end if;
  if balance>0 then total=total+balance;row_ids=array_append(row_ids,r->>'id');end if;
 end loop;
 if cardinality(row_ids)=0 then raise exception 'Nenhum saldo em aberto para este destinatário no seu acesso'; end if;
 if total<>p_expected_amount or cardinality(row_ids)<>p_expected_count then raise exception 'O saldo ou a quantidade de conhecimentos mudou. Feche esta janela e confira os valores atualizados antes de pagar tudo'; end if;
 foreach row_id in array row_ids loop
  perform public.td_registrar_pagamento(p_manifest_id,row_id,null,'integral',null,null,p_date,p_method);
  select data into m from public.td_manifestos where id=p_manifest_id;
  select value,(ordinality-1)::integer into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=row_id;
  entry=(r->'payments'->-1)||jsonb_build_object('batchId',batch_id,'note','Quitação em lote do destinatário');
  r=jsonb_set(r,array['payments',(jsonb_array_length(r->'payments')-1)::text],entry);
  update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 end loop;
 return jsonb_build_object('ok',true,'count',cardinality(row_ids),'amount',total,'batchId',batch_id);
end $$;
revoke all on function public.td_pagar_destinatario(text,text,bigint,integer,text,text) from public,anon;
grant execute on function public.td_pagar_destinatario(text,text,bigint,integer,text,text) to authenticated;
