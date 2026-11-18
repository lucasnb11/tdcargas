-- Confirmação de recebimento manual, prazo de 168 horas e liberação auditada.
create or replace function td_cargas_private.controlar_cobranca(p_manifest_id text,p_row_id text,p_action text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;m jsonb;r jsonb;idx integer;entry jsonb;balance bigint;stamp timestamptz:=statement_timestamp();
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado'; end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 if m is null then raise exception 'Manifesto não encontrado'; end if;
 select value,(ordinality-1)::integer into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=p_row_id;
 if r is null or (p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade))) then raise exception 'Conhecimento fora da sua cidade ou não encontrado'; end if;
 if p_action='receive' then
  -- Idempotente: repetir confirmação nunca renova um prazo vencido.
  if nullif(r->>'receivedAt','') is not null then return jsonb_build_object('ok',true); end if;
  r=r||jsonb_build_object('receivedAt',stamp,'collectionDueAt',stamp+interval '168 hours');
 elsif p_action='unlock' then
  if p.perfil<>'admin' then raise exception 'Somente administradores podem liberar pagamentos'; end if;
  balance=(r->>'freight')::bigint-coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),0);
  if balance<=0 or nullif(r->>'collectionDueAt','') is null or (r->>'collectionDueAt')::timestamptz>stamp then raise exception 'Este conhecimento não está bloqueado por vencimento'; end if;
  r=r||jsonb_build_object('collectionDueAt',stamp+interval '168 hours');
 else raise exception 'Operação inválida'; end if;
 entry=jsonb_build_object('action',p_action,'operatorId',auth.uid(),'operator',p.nome,'createdAt',stamp,'dueAt',r->'collectionDueAt');
 r=jsonb_set(r,'{collectionEvents}',coalesce(r->'collectionEvents','[]')||jsonb_build_array(entry));
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function td_cargas_private.controlar_cobranca(text,text,text) from public,anon;
grant execute on function td_cargas_private.controlar_cobranca(text,text,text) to authenticated;

-- A regra é aplicada à gravação: protege todas as RPCs, inclusive legada e lote.
create or replace function td_cargas_private.validar_prazo_cobranca() returns trigger
language plpgsql security invoker set search_path='' as $$
declare old_row jsonb;r jsonb;idx integer;before_paid bigint;after_paid bigint;stamp timestamptz:=statement_timestamp();
begin
 for r,idx in select value,(ordinality-1)::integer from jsonb_array_elements(new.data->'rows') with ordinality loop
  select value into old_row from jsonb_array_elements(old.data->'rows') where value->>'id'=r->>'id';
  if old_row is null then continue; end if;
  before_paid=coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(old_row->'payments','[]')) pay),0);
  after_paid=coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),0);
  if after_paid<=before_paid then continue; end if;
  if (old_row->>'freight')::bigint>before_paid and nullif(old_row->>'collectionDueAt','') is not null and (old_row->>'collectionDueAt')::timestamptz<=stamp then
   raise exception 'Conhecimento % bloqueado: prazo de cobrança vencido. Solicite a liberação do administrador.',r->>'id';
  end if;
  -- Qualquer recebimento que deixe saldo no conhecimento renova o prazo.
  -- A data informada no formulário nunca altera o relógio do servidor.
  if nullif(old_row->>'receivedAt','') is not null and (r->>'freight')::bigint>after_paid then
   r=r||jsonb_build_object('collectionDueAt',stamp+interval '168 hours');
   r=jsonb_set(r,'{collectionEvents}',coalesce(old_row->'collectionEvents','[]')||jsonb_build_array(jsonb_build_object('action','partial_payment','operatorId',auth.uid(),'createdAt',stamp,'dueAt',r->'collectionDueAt')));
   new.data=jsonb_set(new.data,array['rows',idx::text],r);
  end if;
 end loop;
 return new;
end $$;
revoke all on function td_cargas_private.validar_prazo_cobranca() from public,anon,authenticated;
drop trigger if exists td_validar_prazo_cobranca on public.td_manifestos;
create trigger td_validar_prazo_cobranca before update of data on public.td_manifestos for each row execute function td_cargas_private.validar_prazo_cobranca();

create or replace function td_cargas_private.listar_manifestos() returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos; result jsonb='[]'; m record; filtered jsonb;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null then raise exception 'Acesso não autorizado'; end if;
 for m in select * from public.td_manifestos order by id desc loop
  if p.perfil='admin' then result=result||jsonb_build_array(m.data||jsonb_build_object('revision',m.revision));
  elsif p.perfil='entregador' and nullif(trim(p.cidade),'') is not null then
   select coalesce(jsonb_agg(jsonb_build_object('id',r->>'id','client',r->>'client','city',r->>'city','kind',r->>'kind','receivedAt',r->'receivedAt','collectionDueAt',r->'collectionDueAt','volumes',r->'volumes','freight',r->'freight','freights',coalesce(r->'freights','[]'),'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',pay->'amount','freightId',pay->'freightId')) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),'[]'),'conferences',coalesce((select jsonb_agg(jsonb_build_object('operator',c->'operator','createdAt',c->'createdAt')) from jsonb_array_elements(coalesce(r->'conferences','[]')) c),'[]'))),'[]') into filtered
   from jsonb_array_elements(m.data->'rows') r where td_cargas_private.normalizar_cidade(r->>'city')=td_cargas_private.normalizar_cidade(p.cidade);
   if jsonb_array_length(filtered)>0 then result=result||jsonb_build_array(jsonb_build_object('id',m.id,'date',m.data->'date','time',m.data->'time','route',m.data->'route','vessel',m.data->'vessel','rows',filtered)); end if;
  end if;
 end loop;
 return result;
end $$;

create or replace function public.td_controlar_cobranca(p_manifest_id text,p_row_id text,p_action text) returns jsonb language sql security invoker set search_path='' as $$ select td_cargas_private.controlar_cobranca(p_manifest_id,p_row_id,p_action); $$;
revoke all on function public.td_controlar_cobranca(text,text,text) from public,anon;
grant execute on function public.td_controlar_cobranca(text,text,text) to authenticated;

