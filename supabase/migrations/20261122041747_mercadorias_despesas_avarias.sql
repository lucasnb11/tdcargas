-- Mercadorias: divisão administrativa antes de baixas, pagamentos e ajustes por item.
create or replace function td_cargas_private.gerenciar_mercadorias(p_manifest_id text,p_row_id text,p_items jsonb,p_expected_freight bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
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
  if nullif(trim(i->>'id'),'') is null or length(i->>'id')>120 or nullif(trim(i->>'description'),'') is null or length(i->>'description')>200 or coalesce(i->>'category','') not in ('Bebidas','Estiva','Outros') or (i->>'freight') is null or jsonb_typeof(i->'freight')<>'number' or (i->>'freight')::numeric<>trunc((i->>'freight')::numeric) or (i->>'freight')::numeric not between 1 and 100000000000 or (i->>'volumes') is null or jsonb_typeof(i->'volumes')<>'number' or (i->>'volumes')::numeric<>trunc((i->>'volumes')::numeric) or (i->>'volumes')::numeric not between 1 and 1000000 then raise exception 'Mercadoria inválida: informe descrição, categoria, volumes e frete';end if;
  items=items||jsonb_build_array(jsonb_build_object('id',i->>'id','description',trim(i->>'description'),'category',i->>'category','volumes',(i->>'volumes')::int,'freight',(i->>'freight')::bigint,'noteNumber',left(coalesce(nullif(i->>'noteNumber',''),p_row_id),60),'tracking',left(coalesce(i->>'tracking',''),80),'sender',left(coalesce(i->>'sender',''),200)));
 end loop;
 if jsonb_array_length(items)<>(select count(distinct value->>'id') from jsonb_array_elements(items)) then raise exception 'Mercadorias duplicadas';end if;
 if (select sum((value->>'freight')::bigint) from jsonb_array_elements(items))<>(r->>'freight')::bigint or (select sum((value->>'volumes')::bigint) from jsonb_array_elements(items))<>(r->>'volumes')::bigint then raise exception 'A soma dos fretes e dos volumes deve fechar com o conhecimento';end if;
 r=r||jsonb_build_object('freights',items,'itemsManaged',true,'merchandiseEvents',coalesce(r->'merchandiseEvents','[]')||jsonb_build_array(jsonb_build_object('operatorId',auth.uid(),'operator',p.nome,'createdAt',statement_timestamp(),'before',coalesce(r->'freights','[]'),'after',items)));
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
create or replace function td_cargas_private.ajustar_mercadoria(p_manifest_id text,p_row_id text,p_freight_id text,p_value bigint,p_kind text,p_reason text,p_expected_freight bigint,p_expected_paid bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;m jsonb;r jsonb;idx int;item jsonb;itemidx int;received bigint;itempaid bigint;before_value bigint;newtotal bigint;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado';end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 select value,(ordinality-1)::int into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=p_row_id;
 if r is null or (p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade))) then raise exception 'Conhecimento fora da sua cidade ou não encontrado';end if;
 received=coalesce((select sum((value->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]'))),0);
 if p_expected_freight is distinct from (r->>'freight')::bigint or p_expected_paid is distinct from received then raise exception 'Valores atualizados. Reabra a mercadoria';end if;
 if nullif(r->>'collectionDueAt','') is not null and (r->>'collectionDueAt')::timestamptz<=statement_timestamp() and (r->>'freight')::bigint>received then raise exception 'Conhecimento bloqueado. Solicite liberação do administrador';end if;
 select value,(ordinality-1)::int into item,itemidx from jsonb_array_elements(td_cargas_private.distribuir_fretes(r)) with ordinality where value->>'id'=p_freight_id;
 if item is null then raise exception 'Mercadoria não encontrada';end if;
 before_value=(item->>'freight')::bigint;itempaid=(item->>'received')::bigint;
 if p_value is null or p_value<1 or p_value>100000000000 or p_value<itempaid or p_value=before_value or before_value<=itempaid or nullif(trim(p_reason),'') is null or length(trim(p_reason))>2000 or p_kind is null or p_kind not in ('correction','discount') or (p_kind='discount' and p_value>=before_value) then raise exception 'Ajuste inválido: confira valor, saldo e justificativa';end if;
 newtotal=(r->>'freight')::bigint-before_value+p_value;
 if newtotal>100000000000 then raise exception 'Frete total acima do limite';end if;
 item=(r->'freights'->itemidx)||jsonb_build_object('originalFreight',coalesce(r->'freights'->itemidx->'originalFreight',item->'freight'),'freight',p_value);
 r=jsonb_set(r,array['freights',itemidx::text],item);
 r=r||jsonb_build_object('originalFreight',coalesce(r->'originalFreight',r->'freight'),'freight',newtotal,'freightAdjustments',coalesce(r->'freightAdjustments','[]')||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'kind',p_kind,'freightId',p_freight_id,'itemDescription',coalesce(item->>'description',item->>'noteNumber'),'before',before_value,'after',p_value,'reason',trim(p_reason),'operatorId',auth.uid(),'operator',p.nome,'createdAt',statement_timestamp())));
 perform td_cargas_private.distribuir_fretes(r);
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
-- Registro financeiro independente dos fretes e dos pagamentos de clientes.
create table public.td_operacoes(
 id uuid primary key,manifest_id text not null references public.td_manifestos(id),city text not null,
 row_id text,freight_id text,kind text not null check(kind in ('expense','damage')),
 status text not null check(status in ('pending','approved','rejected','paid')),
 data jsonb not null,events jsonb not null default '[]',created_by uuid not null,created_at timestamptz not null default now()
);
create index td_operacoes_trip_city on public.td_operacoes(manifest_id,city,created_at desc);
alter table public.td_operacoes enable row level security;
revoke all on public.td_operacoes from anon,authenticated;
grant select on public.td_operacoes to authenticated;
create policy td_operacoes_read on public.td_operacoes for select to authenticated using(exists(select 1 from public.perfis_manifestos p where p.id=(select auth.uid()) and p.ativo and (p.perfil='admin' or (p.perfil='entregador' and nullif(trim(p.cidade),'') is not null and td_cargas_private.normalizar_cidade(p.cidade)=city))));
-- Imagens privadas. URLs temporárias são emitidas apenas depois de verificar o registro.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('td-comprovantes','td-comprovantes',false,3145728,array['image/jpeg','image/png','image/webp']);
create policy td_receipt_insert on storage.objects for insert to authenticated with check(bucket_id='td-comprovantes' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.perfis_manifestos p where p.id=(select auth.uid()) and p.ativo and p.perfil in ('admin','entregador')));
create policy td_receipt_read on storage.objects for select to authenticated using(bucket_id='td-comprovantes' and exists(select 1 from public.td_operacoes o where coalesce(o.data->'attachments','[]') ? name or coalesce(o.data->'paymentAttachments','[]') ? name));
create or replace function td_cargas_private.validar_anexos(p_paths jsonb) returns void language plpgsql security definer set search_path='' as $$
declare path text;
begin
 if p_paths is null or jsonb_typeof(p_paths)<>'array' or jsonb_array_length(p_paths)>3 then raise exception 'Anexe no máximo três fotos';end if;
 for path in select jsonb_array_elements_text(p_paths) loop
  if split_part(path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='td-comprovantes' and name=path) then raise exception 'Anexo inválido ou fora do seu acesso';end if;
 end loop;
end $$;
create or replace function td_cargas_private.operacao(p_action text,p_input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;m jsonb;r jsonb;item jsonb;e public.td_operacoes;entryid uuid;d jsonb;kind text;city text;stamp timestamptz:=statement_timestamp();amount bigint;event jsonb;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado';end if;
 entryid=(p_input->>'id')::uuid;
 if entryid is null then raise exception 'Identificador obrigatório';end if;
 if p_action='create' then
  -- O mesmo identificador nunca cria uma segunda saída de dinheiro.
  perform pg_advisory_xact_lock(hashtextextended(entryid::text,0));
  select * into e from public.td_operacoes where id=entryid;
  if e.id is not null then
   if e.created_by=auth.uid() then return jsonb_build_object('ok',true,'id',e.id);else raise exception 'Identificador já utilizado';end if;
  end if;
  kind=p_input->>'kind';d=p_input->'data';
  select data into m from public.td_manifestos where id=p_input->>'manifestId' for share;
  city=td_cargas_private.normalizar_cidade(p_input->>'city');
  if m is null or nullif(city,'') is null or not exists(select 1 from jsonb_array_elements(m->'rows') x where td_cargas_private.normalizar_cidade(x->>'city')=city) then raise exception 'Viagem ou cidade inválida';end if;
  if p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(p.cidade)<>city) then raise exception 'Cidade fora do seu acesso';end if;
  if kind is null or kind not in ('expense','damage') or nullif(trim(d->>'description'),'') is null or length(d->>'description')>2000 or jsonb_typeof(d->'amount') is distinct from 'number' or (d->>'amount')::numeric<>trunc((d->>'amount')::numeric) or (d->>'amount')::numeric not between 1 and 100000000000 then raise exception 'Informe descrição e valor válidos';end if;
  if coalesce(d->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida';end if;perform (d->>'date')::date;
  perform td_cargas_private.validar_anexos(d->'attachments');
  d=jsonb_build_object('description',trim(d->>'description'),'date',d->>'date','amount',(d->>'amount')::bigint,'attachments',d->'attachments','operator',p.nome);
  if kind='expense' then
   if coalesce(p_input->'data'->>'category','') not in ('Alimentação','Combustível','Manutenção','Outros') or coalesce(p_input->'data'->>'source','') not in ('Dinheiro das cobranças','Conta da empresa','Recurso próprio') then raise exception 'Categoria ou origem inválida';end if;
   d=d||jsonb_build_object('category',p_input->'data'->>'category','source',p_input->'data'->>'source','paidDate',d->>'date');
  else
   select value into r from jsonb_array_elements(m->'rows') where value->>'id'=p_input->>'rowId' and td_cargas_private.normalizar_cidade(value->>'city')=city;
   if r is null then raise exception 'Conhecimento não encontrado nesta cidade';end if;
   if nullif(p_input->>'freightId','') is not null then
    select value into item from jsonb_array_elements(coalesce(r->'freights','[]')) where value->>'id'=p_input->>'freightId';
    if item is null then raise exception 'Mercadoria não encontrada';end if;
   end if;
   if jsonb_typeof(p_input->'data'->'quantity') is distinct from 'number' or (p_input->'data'->>'quantity')::numeric<>trunc((p_input->'data'->>'quantity')::numeric) or (p_input->'data'->>'quantity')::numeric not between 1 and coalesce((item->>'volumes')::numeric,(r->>'volumes')::numeric) then raise exception 'Quantidade avariada inválida';end if;
   d=d||jsonb_build_object('quantity',(p_input->'data'->>'quantity')::int,'client',r->>'client','itemDescription',coalesce(item->>'description',item->>'noteNumber','Conhecimento completo'));
  end if;
  event=jsonb_build_object('action','create','operatorId',auth.uid(),'operator',p.nome,'createdAt',stamp);
  insert into public.td_operacoes(id,manifest_id,city,row_id,freight_id,kind,status,data,events,created_by) values(entryid,p_input->>'manifestId',city,case when kind='damage' then p_input->>'rowId' end,case when kind='damage' then nullif(p_input->>'freightId','') end,kind,case when kind='expense' then 'paid' else 'pending' end,d,jsonb_build_array(event),auth.uid());
 else
  select * into e from public.td_operacoes where id=entryid for update;
  if e.id is null or (p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(p.cidade)<>e.city)) then raise exception 'Registro fora do seu acesso';end if;
  if e.kind<>'damage' then raise exception 'Operação disponível apenas para avarias';end if;
  if e.status is distinct from p_input->>'expectedStatus' then raise exception 'Situação atualizada. Atualize a prestação de contas';end if;
  d=e.data;
  if p_action in ('approve','reject') then
   if p.perfil<>'admin' then raise exception 'Somente administradores podem analisar indenizações';end if;
   if e.status<>'pending' or nullif(trim(p_input->>'reason'),'') is null or length(p_input->>'reason')>2000 then raise exception 'Informe o motivo da análise de uma avaria pendente';end if;
   if p_action='approve' then
    if jsonb_typeof(p_input->'amount') is distinct from 'number' or (p_input->>'amount')::numeric<>trunc((p_input->>'amount')::numeric) or (p_input->>'amount')::numeric not between 1 and (d->>'amount')::numeric then raise exception 'Valor aprovado deve ser positivo e até o solicitado';end if;
    d=d||jsonb_build_object('approvedAmount',(p_input->>'amount')::bigint);e.status='approved';
   else e.status='rejected';end if;
  elsif p_action='pay' then
   if e.status<>'approved' then raise exception 'A indenização precisa de aprovação antes do pagamento';end if;
   if coalesce(p_input->>'source','') not in ('Dinheiro das cobranças','Conta da empresa','Recurso próprio') or coalesce(p_input->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Informe a data e a origem do pagamento';end if;perform (p_input->>'date')::date;
   perform td_cargas_private.validar_anexos(p_input->'attachments');
   if jsonb_array_length(p_input->'attachments')=0 then raise exception 'Anexe um comprovante da indenização';end if;
   d=d||jsonb_build_object('source',p_input->>'source','paidDate',p_input->>'date','paidBy',p.nome,'paymentAttachments',p_input->'attachments');e.status='paid';
  else raise exception 'Operação inválida';end if;
  event=jsonb_build_object('action',p_action,'operatorId',auth.uid(),'operator',p.nome,'createdAt',stamp,'reason',p_input->>'reason','amount',d->'approvedAmount');
  update public.td_operacoes set status=e.status,data=d,events=events||jsonb_build_array(event) where id=entryid;
 end if;
 return jsonb_build_object('ok',true,'id',entryid);
end $$;
create or replace function public.td_operacao(p_action text,p_input jsonb) returns jsonb language sql security invoker set search_path='' as $$select td_cargas_private.operacao(p_action,p_input);$$;
create or replace function public.td_gerenciar_mercadorias(p_manifest_id text,p_row_id text,p_items jsonb,p_expected_freight bigint) returns jsonb language sql security invoker set search_path='' as $$select td_cargas_private.gerenciar_mercadorias(p_manifest_id,p_row_id,p_items,p_expected_freight);$$;
create or replace function public.td_ajustar_mercadoria(p_manifest_id text,p_row_id text,p_freight_id text,p_value bigint,p_kind text,p_reason text,p_expected_freight bigint,p_expected_paid bigint) returns jsonb language sql security invoker set search_path='' as $$select td_cargas_private.ajustar_mercadoria(p_manifest_id,p_row_id,p_freight_id,p_value,p_kind,p_reason,p_expected_freight,p_expected_paid);$$;
revoke all on function td_cargas_private.validar_anexos(jsonb) from public,anon,authenticated;
revoke all on function td_cargas_private.operacao(text,jsonb),public.td_operacao(text,jsonb),td_cargas_private.gerenciar_mercadorias(text,text,jsonb,bigint),public.td_gerenciar_mercadorias(text,text,jsonb,bigint),td_cargas_private.ajustar_mercadoria(text,text,text,bigint,text,text,bigint,bigint),public.td_ajustar_mercadoria(text,text,text,bigint,text,text,bigint,bigint) from public,anon;
grant execute on function td_cargas_private.operacao(text,jsonb),public.td_operacao(text,jsonb),td_cargas_private.gerenciar_mercadorias(text,text,jsonb,bigint),public.td_gerenciar_mercadorias(text,text,jsonb,bigint),td_cargas_private.ajustar_mercadoria(text,text,text,bigint,text,text,bigint,bigint),public.td_ajustar_mercadoria(text,text,text,bigint,text,text,bigint,bigint) to authenticated;

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
   select coalesce(jsonb_agg(jsonb_build_object('id',r->>'id','client',r->>'client','city',r->>'city','kind',r->>'kind','receivedAt',r->'receivedAt','collectionDueAt',r->'collectionDueAt','volumes',r->'volumes','freight',r->'freight','originalFreight',r->'originalFreight','freights',coalesce(r->'freights','[]'),'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',pay->'amount','method',pay->'method','freightId',pay->'freightId')) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),'[]'),'conferences',coalesce((select jsonb_agg(jsonb_build_object('operator',c->'operator','createdAt',c->'createdAt')) from jsonb_array_elements(coalesce(r->'conferences','[]')) c),'[]'))),'[]') into filtered
   from jsonb_array_elements(m.data->'rows') r where td_cargas_private.normalizar_cidade(r->>'city')=td_cargas_private.normalizar_cidade(p.cidade);
   if jsonb_array_length(filtered)>0 then result=result||jsonb_build_array(jsonb_build_object('id',m.id,'date',m.data->'date','time',m.data->'time','route',m.data->'route','vessel',m.data->'vessel','rows',filtered)); end if;
  end if;
 end loop;
 return result;
end $function$
;
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
end $function$
;
-- Restauração administrativa sem sobrescrever registros existentes.
create or replace function td_cargas_private.restaurar_operacoes(p_entries jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;e jsonb;restored int:=0;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo and perfil='admin';
 if auth.uid() is null or p.id is null then raise exception 'Apenas administradores podem restaurar';end if;
 if jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries)>10000 then raise exception 'Backup de operações inválido';end if;
 for e in select value from jsonb_array_elements(p_entries) loop
  if coalesce(e->>'kind','') not in ('expense','damage') or coalesce(e->>'status','') not in ('pending','approved','rejected','paid') or (e->>'kind'='expense' and e->>'status'<>'paid') or jsonb_typeof(e->'data'->'amount') is distinct from 'number' or (e->'data'->>'amount')::numeric<>trunc((e->'data'->>'amount')::numeric) or (e->'data'->>'amount')::numeric not between 1 and 100000000000 or jsonb_typeof(e->'events') is distinct from 'array' then raise exception 'Registro financeiro inválido no backup';end if;
  if e->>'kind'='damage' and e->>'status' in ('approved','paid') and (jsonb_typeof(e->'data'->'approvedAmount') is distinct from 'number' or (e->'data'->>'approvedAmount')::numeric<>trunc((e->'data'->>'approvedAmount')::numeric) or (e->'data'->>'approvedAmount')::numeric not between 1 and (e->'data'->>'amount')::numeric) then raise exception 'Indenização inválida no backup';end if;
  if not exists(select 1 from public.td_manifestos m cross join lateral jsonb_array_elements(m.data->'rows') r where m.id=e->>'manifest_id' and td_cargas_private.normalizar_cidade(r->>'city')=e->>'city' and (e->>'kind'='expense' or r->>'id'=e->>'row_id')) then raise exception 'Importe primeiro a viagem e o conhecimento do registro';end if;
  insert into public.td_operacoes(id,manifest_id,city,row_id,freight_id,kind,status,data,events,created_by,created_at) values((e->>'id')::uuid,e->>'manifest_id',e->>'city',e->>'row_id',e->>'freight_id',e->>'kind',e->>'status',e->'data',e->'events'||jsonb_build_array(jsonb_build_object('action','restore','operatorId',auth.uid(),'operator',p.nome,'createdAt',statement_timestamp())),(e->>'created_by')::uuid,(e->>'created_at')::timestamptz) on conflict(id) do nothing;
  if found then restored=restored+1;end if;
 end loop;
 return jsonb_build_object('restored',restored);
end $$;
create or replace function public.td_restaurar_operacoes(p_entries jsonb) returns jsonb language sql security invoker set search_path='' as $$select td_cargas_private.restaurar_operacoes(p_entries);$$;
revoke all on function td_cargas_private.restaurar_operacoes(jsonb),public.td_restaurar_operacoes(jsonb) from public,anon;
grant execute on function td_cargas_private.restaurar_operacoes(jsonb),public.td_restaurar_operacoes(jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.td_registrar_pagamento(p_manifest_id text, p_row_id text, p_freight_id text, p_type text, p_amount bigint, p_note text, p_date text, p_method text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if item is not null then entry=entry||jsonb_build_object('freightId',p_freight_id,'noteNumber',item->>'noteNumber','itemDescription',coalesce(item->>'description',item->>'noteNumber'),'tracking',item->>'tracking'); end if;
 r=jsonb_set(r,'{payments}',coalesce(r->'payments','[]')||jsonb_build_array(entry));
 perform td_cargas_private.distribuir_fretes(r);
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $function$
;
