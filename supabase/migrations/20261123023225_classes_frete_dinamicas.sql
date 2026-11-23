-- Aceita as classes originais do PDF sem limitar o catálogo.
CREATE OR REPLACE FUNCTION td_cargas_private.gerenciar_mercadorias(p_manifest_id text, p_row_id text, p_items jsonb, p_expected_freight bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.perfis_manifestos;m jsonb;r jsonb;idx int;i jsonb;items jsonb='[]';
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil<>'admin' then raise exception 'Apenas administradores podem dividir as mercadorias';end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 select value,(ordinality-1)::int into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=p_row_id;
 if r is null then raise exception 'Conhecimento não encontrado';end if;
 if (r->>'freight')::bigint is distinct from p_expected_freight then raise exception 'Frete atualizado. Reabra o conhecimento';end if;
 if jsonb_array_length(coalesce(r->'payments','[]'))>0 or jsonb_array_length(coalesce(r->'freightAdjustments','[]'))>0 then raise exception 'A divisão deve ser feita antes dos pagamentos e ajustes';end if;
 if exists(select 1 from public.td_operacoes where manifest_id=p_manifest_id and row_id=p_row_id) then raise exception 'Conhecimento com avaria registrada não pode ser dividido novamente';end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Informe entre 1 e 100 mercadorias';end if;
 for i in select value from jsonb_array_elements(p_items) loop
  if nullif(trim(i->>'id'),'') is null or length(i->>'id')>120 or nullif(trim(i->>'description'),'') is null or length(i->>'description')>200 or jsonb_typeof(i->'category') is distinct from 'string' or nullif(trim(i->>'category'),'') is null or length(trim(i->>'category'))>40 or (i->>'freight') is null or jsonb_typeof(i->'freight')<>'number' or (i->>'freight')::numeric<>trunc((i->>'freight')::numeric) or (i->>'freight')::numeric not between 1 and 100000000000 or (i->>'volumes') is null or jsonb_typeof(i->'volumes')<>'number' or (i->>'volumes')::numeric<>trunc((i->>'volumes')::numeric) or (i->>'volumes')::numeric not between 1 and 1000000 then raise exception 'Mercadoria inválida: informe descrição, categoria, volumes e frete';end if;
  items=items||jsonb_build_array(jsonb_build_object('id',i->>'id','description',trim(i->>'description'),'category',trim(i->>'category'),'volumes',(i->>'volumes')::int,'freight',(i->>'freight')::bigint,'noteNumber',left(coalesce(nullif(i->>'noteNumber',''),p_row_id),60),'tracking',left(coalesce(i->>'tracking',''),80),'sender',left(coalesce(i->>'sender',''),200)));
 end loop;
 if jsonb_array_length(items)<>(select count(distinct value->>'id') from jsonb_array_elements(items)) then raise exception 'Mercadorias duplicadas';end if;
 if (select sum((value->>'freight')::bigint) from jsonb_array_elements(items))<>(r->>'freight')::bigint or (select sum((value->>'volumes')::bigint) from jsonb_array_elements(items))<>(r->>'volumes')::bigint then raise exception 'A soma dos fretes e dos volumes deve fechar com o conhecimento';end if;
 r=r||jsonb_build_object('freights',items,'itemsManaged',true,'merchandiseEvents',coalesce(r->'merchandiseEvents','[]')||jsonb_build_array(jsonb_build_object('operatorId',auth.uid(),'operator',p.nome,'createdAt',statement_timestamp(),'before',coalesce(r->'freights','[]'),'after',items)));
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $function$;

CREATE OR REPLACE FUNCTION public.td_salvar_fretes(p_documents jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if coalesce((r->>'itemsManaged')::boolean,false) or jsonb_array_length(coalesce(r->'freightAdjustments','[]'))>0 then raise exception 'Mercadorias divididas ou fretes ajustados não podem ser sobrescritos pela importação';end if;
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 2000 then raise exception 'Lista de notas/fretes inválida'; end if;
  if jsonb_array_length(items)<>(select count(distinct e->>'id') from jsonb_array_elements(items) e) then raise exception 'Notas/fretes duplicados'; end if;
  total=0;
  for item in select value from jsonb_array_elements(items) loop
   if jsonb_typeof(item) is distinct from 'object' or nullif(trim(item->>'id'),'') is null or length(item->>'id')>120 or nullif(trim(item->>'noteNumber'),'') is null or length(item->>'noteNumber')>60 or length(coalesce(item->>'sender',''))>200 or length(coalesce(item->>'tracking',''))>80 or (item ? 'category' and (jsonb_typeof(item->'category') is distinct from 'string' or nullif(trim(item->>'category'),'') is null or length(item->>'category')>40)) then raise exception 'Dados da nota/frete inválidos'; end if;
   if jsonb_typeof(item->'freight') is distinct from 'number' or (item->>'freight')::numeric<>trunc((item->>'freight')::numeric) or (item->>'freight')::numeric not between 0 and 100000000000 or jsonb_typeof(item->'volumes') is distinct from 'number' or (item->>'volumes')::numeric<>trunc((item->>'volumes')::numeric) or (item->>'volumes')::numeric not between 0 and 1000000 then raise exception 'Frete ou volumes inválidos'; end if;
   total=total+(item->>'freight')::bigint;
  end loop;
  if total<>(r->>'freight')::bigint then raise exception 'A soma das notas deve ser igual ao frete do conhecimento %',r->>'id'; end if;
  -- Para itens já vinculados, só aceita preencher a classificação quando a identidade e os valores permanecem idênticos.
  if exists(select 1 from jsonb_array_elements(coalesce(r->'payments','[]')) p where nullif(p->>'freightId','') is not null) or exists(select 1 from public.td_operacoes o where o.manifest_id=d->>'manifestId' and o.row_id=d->>'rowId' and o.freight_id is not null) then
   if (select jsonb_agg(jsonb_build_array(x->>'id',x->>'noteNumber',x->>'tracking',x->'freight',x->'volumes') order by ord) from jsonb_array_elements(coalesce(r->'freights','[]')) with ordinality a(x,ord)) is distinct from (select jsonb_agg(jsonb_build_array(x->>'id',x->>'noteNumber',x->>'tracking',x->'freight',x->'volumes') order by ord) from jsonb_array_elements(items) with ordinality a(x,ord)) then raise exception 'Mercadorias com pagamentos ou avarias vinculadas não podem ser substituídas'; end if;
   select jsonb_agg(old_item || case when new_item ? 'category' then jsonb_build_object('category',new_item->>'category','description',coalesce(nullif(old_item->>'description',''),new_item->>'category')) else '{}'::jsonb end order by ord) into items from jsonb_array_elements(r->'freights') with ordinality a(old_item,ord) join jsonb_array_elements(items) b(new_item) on old_item->>'id'=new_item->>'id';
  end if;
  if items is not distinct from r->'freights' then continue; end if;
  r=jsonb_set(r,'{freights}',items);
  perform td_cargas_private.distribuir_fretes(r);
  update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=d->>'manifestId';
  count_saved=count_saved+1;
 end loop;
 return jsonb_build_object('ok',true,'updated',count_saved);
end $function$;
