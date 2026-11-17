-- Detalhes das notas e pagamentos usam os mesmos totais do conhecimento.
create or replace function td_cargas_private.distribuir_fretes(p_row jsonb) returns jsonb
language plpgsql immutable security invoker set search_path='' as $$
declare items jsonb:=coalesce(p_row->'freights','[]'); item jsonb; payment jsonb; idx integer; remaining bigint; amount bigint; available bigint; total bigint:=0;
begin
 if jsonb_array_length(items)=0 then return items; end if;
 for idx in 0..jsonb_array_length(items)-1 loop
  item=items->idx;total=total+(item->>'freight')::bigint;
  items=jsonb_set(items,array[idx::text],item||jsonb_build_object('received',0,'balance',(item->>'freight')::bigint));
 end loop;
 if total<>(p_row->>'freight')::bigint then raise exception 'A soma das notas diverge do conhecimento'; end if;
 for payment in select value from jsonb_array_elements(coalesce(p_row->'payments','[]')) loop
  remaining=(payment->>'amount')::bigint;
  if remaining<=0 then raise exception 'Pagamento inválido'; end if;
  for idx in 0..jsonb_array_length(items)-1 loop
   item=items->idx;
   if nullif(payment->>'freightId','') is not null and item->>'id'<>payment->>'freightId' then continue; end if;
   available=(item->>'balance')::bigint;amount=least(remaining,available);
   items=jsonb_set(items,array[idx::text],item||jsonb_build_object('received',(item->>'received')::bigint+amount,'balance',available-amount));
   remaining=remaining-amount;exit when remaining=0;
  end loop;
  if remaining<>0 then raise exception 'Pagamento excede o saldo da nota ou nota não encontrada'; end if;
 end loop;
 return items;
end $$;
revoke all on function td_cargas_private.distribuir_fretes(jsonb) from public,anon;
grant execute on function td_cargas_private.distribuir_fretes(jsonb) to authenticated;

create or replace function public.td_salvar_fretes(p_documents jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb;m jsonb;r jsonb;items jsonb;item jsonb;idx integer;total bigint;count_saved integer:=0;
begin
 if auth.uid() is null or not manifestos_private.is_admin() then raise exception 'Apenas administradores podem vincular notas/fretes'; end if;
 if jsonb_typeof(p_documents) is distinct from 'array' or jsonb_array_length(p_documents) not between 1 and 1000 then raise exception 'Lista de conhecimentos inválida'; end if;
 if (select count(*) from jsonb_array_elements(p_documents))<>(select count(distinct jsonb_build_array(e->>'manifestId',e->>'rowId')) from jsonb_array_elements(p_documents) e) then raise exception 'Conhecimento duplicado na importação'; end if;
 -- Ordem estável dos bloqueios para importações simultâneas.
 for d in select value from jsonb_array_elements(p_documents) order by value->>'manifestId',value->>'rowId' loop
  select data into m from public.td_manifestos where id=d->>'manifestId' for update;
  if m is null then raise exception 'Manifesto não encontrado'; end if;
  select value,(ordinality-1)::integer into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=d->>'rowId';
  if r is null then raise exception 'Conhecimento não encontrado no manifesto'; end if;
  items=d->'items';
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 2000 then raise exception 'Lista de notas/fretes inválida'; end if;
  if jsonb_array_length(items)<>(select count(distinct e->>'id') from jsonb_array_elements(items) e) then raise exception 'Notas/fretes duplicados'; end if;
  total=0;
  for item in select value from jsonb_array_elements(items) loop
   if jsonb_typeof(item) is distinct from 'object' or nullif(trim(item->>'id'),'') is null or length(item->>'id')>120 or nullif(trim(item->>'noteNumber'),'') is null or length(item->>'noteNumber')>60 or length(coalesce(item->>'sender',''))>200 or length(coalesce(item->>'tracking',''))>80 then raise exception 'Dados da nota/frete inválidos'; end if;
   if jsonb_typeof(item->'freight') is distinct from 'number' or (item->>'freight')::numeric<>trunc((item->>'freight')::numeric) or (item->>'freight')::numeric not between 0 and 100000000000 or jsonb_typeof(item->'volumes') is distinct from 'number' or (item->>'volumes')::numeric<>trunc((item->>'volumes')::numeric) or (item->>'volumes')::numeric not between 0 and 1000000 then raise exception 'Frete ou volumes inválidos'; end if;
   total=total+(item->>'freight')::bigint;
  end loop;
  if total<>(r->>'freight')::bigint then raise exception 'A soma das notas deve ser igual ao frete do conhecimento %',r->>'id'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(r->'payments','[]')) p where nullif(p->>'freightId','') is not null) and items is distinct from r->'freights' then raise exception 'Notas com pagamentos individuais não podem ser alteradas'; end if;
  if items is not distinct from r->'freights' then continue; end if;
  r=jsonb_set(r,'{freights}',items);
  perform td_cargas_private.distribuir_fretes(r);
  update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=d->>'manifestId';
  count_saved=count_saved+1;
 end loop;
 return jsonb_build_object('ok',true,'updated',count_saved);
end $$;
revoke all on function public.td_salvar_fretes(jsonb) from public,anon;
grant execute on function public.td_salvar_fretes(jsonb) to authenticated;

create or replace function public.td_registrar_pagamento(p_manifest_id text,p_row_id text,p_freight_id text,p_type text,p_amount bigint,p_note text,p_date text,p_method text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;m jsonb;r jsonb;item jsonb;idx integer;balance bigint;amount bigint;entry jsonb;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado'; end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 if m is null then raise exception 'Manifesto não encontrado'; end if;
 select value,(ordinality-1)::integer into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=p_row_id;
 if r is null or (p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade))) then raise exception 'Conhecimento fora da sua cidade ou não encontrado'; end if;
 balance=(r->>'freight')::bigint-coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),0);
 if nullif(p_freight_id,'') is not null then
  select value into item from jsonb_array_elements(td_cargas_private.distribuir_fretes(r)) where value->>'id'=p_freight_id;
  if item is null then raise exception 'Nota/frete não encontrado'; end if;
  balance=least(balance,(item->>'balance')::bigint);
 end if;
 if p_type is null or p_type not in ('integral','parcial') then raise exception 'Tipo de pagamento inválido'; end if;
 amount=case when p_type='integral' then balance else p_amount end;
 if amount is null or amount<=0 or amount>balance then raise exception 'Valor maior que o saldo ou inválido'; end if;
 if p_type='parcial' and (amount>=balance or nullif(trim(p_note),'') is null) then raise exception 'Pagamento parcial exige justificativa e valor inferior ao saldo'; end if;
 if p_date is null or p_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Data inválida'; end if;
 perform p_date::date;
 if length(coalesce(p_note,''))>2000 then raise exception 'Justificativa muito longa'; end if;
 if p_method is null or p_method not in ('Pix','Dinheiro','Transferência','Cartão','Boleto','Outro') then raise exception 'Forma de pagamento inválida'; end if;
 entry=jsonb_build_object('id',gen_random_uuid(),'amount',amount,'note',case when p_type='parcial' then trim(p_note) else 'Quitação do saldo' end,'type',p_type,'operator',p.nome,'operatorEmail',p.email,'operatorId',auth.uid(),'date',p_date,'method',p_method,'createdAt',now(),'scope',case when item is null then 'knowledge' else 'freight' end);
 if item is not null then entry=entry||jsonb_build_object('freightId',p_freight_id,'noteNumber',item->>'noteNumber','tracking',item->>'tracking'); end if;
 r=jsonb_set(r,'{payments}',coalesce(r->'payments','[]')||jsonb_build_array(entry));
 perform td_cargas_private.distribuir_fretes(r);
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.td_registrar_pagamento(text,text,text,text,bigint,text,text,text) from public,anon;
grant execute on function public.td_registrar_pagamento(text,text,text,text,bigint,text,text,text) to authenticated;

create or replace function td_cargas_private.listar_manifestos() returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos; result jsonb='[]'; m record; filtered jsonb;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null then raise exception 'Acesso não autorizado'; end if;
 for m in select * from public.td_manifestos order by id desc loop
  if p.perfil='admin' then result=result||jsonb_build_array(m.data||jsonb_build_object('revision',m.revision));
  elsif p.perfil='entregador' and nullif(trim(p.cidade),'') is not null then
   select coalesce(jsonb_agg(jsonb_build_object('id',r->>'id','client',r->>'client','city',r->>'city','kind',r->>'kind','volumes',r->'volumes','freight',r->'freight','freights',coalesce(r->'freights','[]'),'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',pay->'amount','freightId',pay->'freightId')) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),'[]'),'conferences',coalesce((select jsonb_agg(jsonb_build_object('operator',c->'operator','createdAt',c->'createdAt')) from jsonb_array_elements(coalesce(r->'conferences','[]')) c),'[]'))),'[]') into filtered
   from jsonb_array_elements(m.data->'rows') r where td_cargas_private.normalizar_cidade(r->>'city')=td_cargas_private.normalizar_cidade(p.cidade);
   if jsonb_array_length(filtered)>0 then result=result||jsonb_build_array(jsonb_build_object('id',m.id,'date',m.data->'date','time',m.data->'time','route',m.data->'route','vessel',m.data->'vessel','rows',filtered)); end if;
  end if;
 end loop;
 return result;
end $$;
