-- Ajustes auditados em centavos; preserva recebimentos e o prazo original.
create or replace function td_cargas_private.ajustar_frete(p_manifest_id text,p_row_id text,p_value bigint,p_kind text,p_reason text,p_expected_freight bigint,p_expected_paid bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;m jsonb;r jsonb;idx integer;received bigint;before_value bigint;items jsonb;item jsonb;i integer;remaining bigint;weight bigint;allocated bigint:=0;part bigint;last_idx integer;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado'; end if;
 if p_value is null or p_value<1 or p_value>100000000000 or p_kind is null or p_kind not in ('correction','discount') or nullif(trim(p_reason),'') is null or length(trim(p_reason))>2000 then raise exception 'Informe o novo valor e a justificativa';end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 if m is null then raise exception 'Manifesto não encontrado';end if;
 select value,(ordinality-1)::integer into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=p_row_id;
 if r is null or (p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade))) then raise exception 'Conhecimento fora da sua cidade ou não encontrado';end if;
 before_value=(r->>'freight')::bigint;
 received=coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),0);
 if p_expected_freight is distinct from before_value or p_expected_paid is distinct from received then raise exception 'Os valores foram atualizados por outro usuário. Reabra o conhecimento antes de ajustar';end if;
 if before_value<=received then raise exception 'Conhecimento já quitado';end if;
 if nullif(r->>'collectionDueAt','') is not null and (r->>'collectionDueAt')::timestamptz<=statement_timestamp() then raise exception 'Conhecimento bloqueado. Solicite a liberação do administrador';end if;
 if p_value<received or p_value=before_value or (p_kind='discount' and p_value>=before_value) then raise exception 'Valor inválido: respeite o recebido e informe um valor diferente; desconto deve reduzir o frete';end if;
 -- Redistribui apenas saldos de notas em aberto, sem modificar valores já pagos.
 items=td_cargas_private.distribuir_fretes(r);
 if jsonb_array_length(items)>0 then
  remaining=p_value-received;weight=before_value-received;
  select max(ordinality-1)::integer into last_idx from jsonb_array_elements(items) with ordinality where (value->>'balance')::bigint>0;
  for i in 0..jsonb_array_length(items)-1 loop
   item=items->i;
   part=case when i=last_idx then remaining-allocated else floor(remaining::numeric*(item->>'balance')::bigint/weight)::bigint end;
   allocated=allocated+part;
   item=(item-'balance'-'received')||jsonb_build_object('originalFreight',coalesce(item->'originalFreight',item->'freight'),'freight',(items->i->>'received')::bigint+part);
   items=jsonb_set(items,array[i::text],item);
  end loop;
  r=jsonb_set(r,'{freights}',items);
 end if;
 r=r||jsonb_build_object('originalFreight',coalesce(r->'originalFreight',r->'freight'),'freight',p_value,'freightAdjustments',coalesce(r->'freightAdjustments','[]')||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'kind',p_kind,'before',before_value,'after',p_value,'reason',trim(p_reason),'operatorId',auth.uid(),'operator',p.nome,'createdAt',statement_timestamp())));
 perform td_cargas_private.distribuir_fretes(r);
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function td_cargas_private.ajustar_frete(text,text,bigint,text,text,bigint,bigint) from public,anon;
grant execute on function td_cargas_private.ajustar_frete(text,text,bigint,text,text,bigint,bigint) to authenticated;
create or replace function public.td_ajustar_frete(p_manifest_id text,p_row_id text,p_value bigint,p_kind text,p_reason text,p_expected_freight bigint,p_expected_paid bigint) returns jsonb language sql security invoker set search_path='' as $$select td_cargas_private.ajustar_frete(p_manifest_id,p_row_id,p_value,p_kind,p_reason,p_expected_freight,p_expected_paid);$$;
revoke all on function public.td_ajustar_frete(text,text,bigint,text,text,bigint,bigint) from public,anon;
grant execute on function public.td_ajustar_frete(text,text,bigint,text,text,bigint,bigint) to authenticated;
-- A tela aberta antes de um ajuste não pode confirmar um valor desatualizado.
create or replace function td_cargas_private.pagar_conhecimento_versao(p_manifest_id text,p_row_id text,p_freight_id text,p_type text,p_amount bigint,p_note text,p_date text,p_method text,p_expected_freight bigint,p_expected_paid bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;r jsonb;received bigint;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado';end if;
 perform 1 from public.td_manifestos where id=p_manifest_id for update;
 select value into r from public.td_manifestos m cross join lateral jsonb_array_elements(m.data->'rows') where m.id=p_manifest_id and value->>'id'=p_row_id;
 if r is null or (p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade))) then raise exception 'Conhecimento fora da sua cidade ou não encontrado';end if;
 received=coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),0);
 if p_expected_freight is distinct from (r->>'freight')::bigint or p_expected_paid is distinct from received then raise exception 'Os valores foram atualizados. Reabra o pagamento para conferir o saldo';end if;
 return public.td_registrar_pagamento(p_manifest_id,p_row_id,p_freight_id,p_type,p_amount,p_note,p_date,p_method);
end $$;
revoke all on function td_cargas_private.pagar_conhecimento_versao(text,text,text,text,bigint,text,text,text,bigint,bigint) from public,anon;
grant execute on function td_cargas_private.pagar_conhecimento_versao(text,text,text,text,bigint,text,text,text,bigint,bigint) to authenticated;
create or replace function public.td_pagar_conhecimento_versao(p_manifest_id text,p_row_id text,p_freight_id text,p_type text,p_amount bigint,p_note text,p_date text,p_method text,p_expected_freight bigint,p_expected_paid bigint) returns jsonb language sql security invoker set search_path='' as $$select td_cargas_private.pagar_conhecimento_versao(p_manifest_id,p_row_id,p_freight_id,p_type,p_amount,p_note,p_date,p_method,p_expected_freight,p_expected_paid);$$;
revoke all on function public.td_pagar_conhecimento_versao(text,text,text,text,bigint,text,text,text,bigint,bigint) from public,anon;
grant execute on function public.td_pagar_conhecimento_versao(text,text,text,text,bigint,text,text,text,bigint,bigint) to authenticated;

CREATE OR REPLACE FUNCTION td_cargas_private.listar_manifestos()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.perfis_manifestos; result jsonb='[]'; m record; filtered jsonb;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null then raise exception 'Acesso não autorizado'; end if;
 for m in select * from public.td_manifestos order by id desc loop
  if p.perfil='admin' then result=result||jsonb_build_array(m.data||jsonb_build_object('revision',m.revision));
  elsif p.perfil='entregador' and nullif(trim(p.cidade),'') is not null then
   select coalesce(jsonb_agg(jsonb_build_object('id',r->>'id','client',r->>'client','city',r->>'city','kind',r->>'kind','receivedAt',r->'receivedAt','collectionDueAt',r->'collectionDueAt','volumes',r->'volumes','freight',r->'freight','originalFreight',r->'originalFreight','freights',coalesce(r->'freights','[]'),'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',pay->'amount','freightId',pay->'freightId')) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),'[]'),'conferences',coalesce((select jsonb_agg(jsonb_build_object('operator',c->'operator','createdAt',c->'createdAt')) from jsonb_array_elements(coalesce(r->'conferences','[]')) c),'[]'))),'[]') into filtered
   from jsonb_array_elements(m.data->'rows') r where td_cargas_private.normalizar_cidade(r->>'city')=td_cargas_private.normalizar_cidade(p.cidade);
   if jsonb_array_length(filtered)>0 then result=result||jsonb_build_array(jsonb_build_object('id',m.id,'date',m.data->'date','time',m.data->'time','route',m.data->'route','vessel',m.data->'vessel','rows',filtered)); end if;
  end if;
 end loop;
 return result;
end $function$
;
