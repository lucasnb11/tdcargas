-- TD Cargas | Execute no SQL Editor do Supabase.
-- Preserva as contas e perfis existentes no projeto atual.
create schema if not exists manifestos_private;
revoke all on schema manifestos_private from public,anon;
grant usage on schema manifestos_private to authenticated;
create table if not exists public.perfis_manifestos(id uuid primary key references auth.users(id),email text not null unique,nome text not null,perfil text not null check(perfil in ('admin','entregador')),ativo boolean not null default true,proprietario boolean not null default false,cidade text,criado_em timestamptz not null default now(),atualizado_em timestamptz not null default now());
alter table public.perfis_manifestos add column if not exists cidade text;
alter table public.perfis_manifestos enable row level security;
revoke all on public.perfis_manifestos from public,anon,authenticated;
grant select on public.perfis_manifestos to authenticated;
CREATE OR REPLACE FUNCTION manifestos_private.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select auth.uid() is not null and exists(select 1 from public.perfis_manifestos where id=auth.uid() and perfil='admin' and ativo); $function$;


CREATE OR REPLACE FUNCTION manifestos_private.salvar_perfil(p_email text, p_nome text, p_perfil text, p_ativo boolean, p_cidade text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target_id uuid; canonical_email text; canonical_city text;
begin
 if auth.uid() is null or not manifestos_private.is_admin() then raise exception 'Acesso não autorizado'; end if;
 if p_perfil not in ('admin','entregador') or p_ativo is null or length(trim(p_nome)) not between 1 and 120 then raise exception 'Perfil inválido'; end if;
 canonical_city=case when p_perfil='admin' then null else regexp_replace(translate(upper(trim(p_cidade)),'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ','AAAAAEEEEIIIIOOOOOUUUUC'),'\s+',' ','g') end;
 if p_perfil='entregador' and (canonical_city is null or length(canonical_city) not between 2 and 80) then raise exception 'Informe a cidade do entregador'; end if;
 select id,lower(email) into target_id,canonical_email from auth.users where lower(email)=lower(trim(p_email)) and deleted_at is null;
 if target_id is null then raise exception 'Conta não encontrada no Supabase Auth. Crie uma conta ou vincule um usuário existente.'; end if;
 if exists(select 1 from public.perfis_manifestos where id=target_id and proprietario) and (p_perfil<>'admin' or not p_ativo) then raise exception 'O administrador proprietário não pode ser bloqueado'; end if;
 if target_id=auth.uid() and (p_perfil<>'admin' or not p_ativo) then raise exception 'Não é permitido remover seu próprio acesso administrativo'; end if;
 insert into public.perfis_manifestos(id,email,nome,perfil,ativo,cidade) values(target_id,canonical_email,trim(p_nome),p_perfil,p_ativo,canonical_city)
 on conflict(id) do update set email=excluded.email,nome=excluded.nome,perfil=excluded.perfil,ativo=excluded.ativo,cidade=excluded.cidade,atualizado_em=now();
end; $function$;


CREATE OR REPLACE FUNCTION public.manifestos_salvar_perfil(p_email text, p_nome text, p_perfil text, p_ativo boolean, p_cidade text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select manifestos_private.salvar_perfil(p_email,p_nome,p_perfil,p_ativo,p_cidade); $function$;


revoke all on function manifestos_private.is_admin() from public,anon;
grant execute on function manifestos_private.is_admin() to authenticated;
revoke all on function manifestos_private.salvar_perfil(text,text,text,boolean,text) from public,anon;
grant execute on function manifestos_private.salvar_perfil(text,text,text,boolean,text) to authenticated;
revoke all on function public.manifestos_salvar_perfil(text,text,text,boolean,text) from public,anon;
grant execute on function public.manifestos_salvar_perfil(text,text,text,boolean,text) to authenticated;
drop policy if exists manifestos_select on public.perfis_manifestos;
create policy manifestos_select on public.perfis_manifestos for select to authenticated using(id=(select auth.uid()) or (select manifestos_private.is_admin()));

create schema if not exists td_cargas_private;
revoke all on schema td_cargas_private from public,anon;
grant usage on schema td_cargas_private to authenticated;
create table if not exists public.td_manifestos(id text primary key,data jsonb not null,revision integer not null default 0);
create table if not exists public.td_cidades(key text primary key,name text not null,created_at timestamptz not null default now());
create table if not exists public.td_config_pagamento(id text primary key,data jsonb not null);
alter table public.td_manifestos enable row level security;
alter table public.td_cidades enable row level security;
alter table public.td_config_pagamento enable row level security;
revoke all on public.td_manifestos,public.td_cidades,public.td_config_pagamento from public,anon,authenticated;
grant select,insert,update on public.td_manifestos,public.td_cidades,public.td_config_pagamento to authenticated;
drop policy if exists td_manifestos_admin on public.td_manifestos;
create policy td_manifestos_admin on public.td_manifestos for all to authenticated using((select manifestos_private.is_admin())) with check((select manifestos_private.is_admin()));
drop policy if exists td_cidades_admin on public.td_cidades;
create policy td_cidades_admin on public.td_cidades for all to authenticated using((select manifestos_private.is_admin())) with check((select manifestos_private.is_admin()));
drop policy if exists td_pix_admin on public.td_config_pagamento;
create policy td_pix_admin on public.td_config_pagamento for all to authenticated using((select manifestos_private.is_admin())) with check((select manifestos_private.is_admin()));
insert into public.td_cidades(key,name) values('ALMEIRIM','ALMEIRIM'),('GURUPA','GURUPÁ'),('PORTO DE MOZ','PORTO DE MOZ') on conflict do nothing;
create or replace function td_cargas_private.normalizar_cidade(valor text) returns text language sql immutable security invoker set search_path='' as $$ select regexp_replace(translate(upper(trim(coalesce(valor,''))),'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ','AAAAAEEEEIIIIOOOOOUUUUC'),'\s+',' ','g'); $$;
create or replace function td_cargas_private.listar_manifestos() returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos; result jsonb='[]'; m record; filtered jsonb;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null then raise exception 'Acesso não autorizado'; end if;
 for m in select * from public.td_manifestos order by id desc loop
  if p.perfil='admin' then result=result||jsonb_build_array(m.data||jsonb_build_object('revision',m.revision));
  elsif p.perfil='entregador' and nullif(trim(p.cidade),'') is not null then
   select coalesce(jsonb_agg(jsonb_build_object('id',r->>'id','client',r->>'client','city',r->>'city','kind',r->>'kind','volumes',r->'volumes','freight',r->'freight','payments',coalesce((select jsonb_agg(jsonb_build_object('amount',pay->'amount')) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),'[]'),'conferences',coalesce((select jsonb_agg(jsonb_build_object('operator',c->'operator','createdAt',c->'createdAt')) from jsonb_array_elements(coalesce(r->'conferences','[]')) c),'[]'))),'[]') into filtered
   from jsonb_array_elements(m.data->'rows') r where td_cargas_private.normalizar_cidade(r->>'city')=td_cargas_private.normalizar_cidade(p.cidade);
   if jsonb_array_length(filtered)>0 then result=result||jsonb_build_array(jsonb_build_object('id',m.id,'date',m.data->'date','time',m.data->'time','route',m.data->'route','rows',filtered)); end if;
  end if;
 end loop;
 return result;
end $$;
create or replace function td_cargas_private.operar_manifesto(p_manifest_id text,p_row_id text,p_action text,p_type text,p_amount bigint,p_note text,p_date text,p_method text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos; m jsonb; r jsonb; idx integer; balance bigint; amount bigint; entry jsonb;
begin
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null then raise exception 'Acesso não autorizado'; end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 if m is null then raise exception 'Viagem não encontrada'; end if;
 select value,(ordinality-1)::integer into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=p_row_id limit 1;
 if r is null or (p.perfil<>'admin' and (p.perfil<>'entregador' or nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade))) then raise exception 'Carga não encontrada ou fora da sua cidade'; end if;
 if p_action='conference' then
  if exists(select 1 from jsonb_array_elements(coalesce(r->'conferences','[]')) c where c->>'operatorId'=auth.uid()::text) then return jsonb_build_object('ok',true); end if;
  entry=jsonb_build_object('id',gen_random_uuid(),'operatorId',auth.uid(),'operator',p.nome,'city',r->'city','createdAt',now());
  r=jsonb_set(r,'{conferences}',coalesce(r->'conferences','[]')||jsonb_build_array(entry));
 elsif p_action='pay' then
  balance=(r->>'freight')::bigint-coalesce((select sum((pay->>'amount')::bigint) from jsonb_array_elements(coalesce(r->'payments','[]')) pay),0);
  if p_type is null or p_type not in ('integral','parcial') then raise exception 'Tipo de pagamento inválido'; end if;
  amount=case when p_type='integral' then balance else p_amount end;
  if amount is null or amount<=0 or amount>balance then raise exception 'Valor maior que o saldo ou inválido'; end if;
  if p_type='parcial' and (amount>=balance or nullif(trim(p_note),'') is null) then raise exception 'Pagamento parcial exige justificativa e valor inferior ao saldo'; end if;
  if p_date is null or p_date !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida'; end if;
  perform p_date::date;
  if length(coalesce(p_note,''))>2000 then raise exception 'Justificativa muito longa'; end if;
  entry=jsonb_build_object('id',gen_random_uuid(),'amount',amount,'note',case when p_type='parcial' then trim(p_note) else 'Quitação do saldo' end,'type',p_type,'operator',p.nome,'operatorEmail',p.email,'operatorId',auth.uid(),'date',p_date,'method',p_method,'createdAt',now());
  r=jsonb_set(r,'{payments}',coalesce(r->'payments','[]')||jsonb_build_array(entry));
 else raise exception 'Operação inválida'; end if;
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
create or replace function td_cargas_private.pix_config() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.perfis_manifestos where id=auth.uid() and ativo and (perfil='admin' or (perfil='entregador' and nullif(trim(cidade),'') is not null))) then raise exception 'Acesso não autorizado'; end if;
 return (select data from public.td_config_pagamento where id='pix');
end $$;
create or replace function public.td_listar_manifestos() returns jsonb language sql security invoker set search_path='' as $$ select td_cargas_private.listar_manifestos(); $$;
create or replace function public.td_operar_manifesto(p_manifest_id text,p_row_id text,p_action text,p_type text,p_amount bigint,p_note text,p_date text,p_method text) returns jsonb language sql security invoker set search_path='' as $$ select td_cargas_private.operar_manifesto(p_manifest_id,p_row_id,p_action,p_type,p_amount,p_note,p_date,p_method); $$;
create or replace function public.td_pix_config() returns jsonb language sql security invoker set search_path='' as $$ select td_cargas_private.pix_config(); $$;
revoke all on all functions in schema td_cargas_private from public,anon;
grant execute on all functions in schema td_cargas_private to authenticated;
revoke all on function public.td_listar_manifestos() from public,anon;
revoke all on function public.td_operar_manifesto(text,text,text,text,bigint,text,text,text) from public,anon;
revoke all on function public.td_pix_config() from public,anon;
grant execute on function public.td_listar_manifestos() to authenticated;
grant execute on function public.td_operar_manifesto(text,text,text,text,bigint,text,text,text) to authenticated;
grant execute on function public.td_pix_config() to authenticated;
