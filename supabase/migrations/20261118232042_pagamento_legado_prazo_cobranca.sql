-- A API legada usa a mesma validação de pagamento da API atual.
create or replace function td_cargas_private.operar_manifesto(p_manifest_id text,p_row_id text,p_action text,p_type text,p_amount bigint,p_note text,p_date text,p_method text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.perfis_manifestos;m jsonb;r jsonb;idx integer;entry jsonb;
begin
 if p_action='pay' then return public.td_registrar_pagamento(p_manifest_id,p_row_id,null,p_type,p_amount,p_note,p_date,p_method); end if;
 select * into p from public.perfis_manifestos where id=auth.uid() and ativo;
 if auth.uid() is null or p.id is null or p.perfil not in ('admin','entregador') then raise exception 'Acesso não autorizado'; end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 if m is null then raise exception 'Viagem não encontrada'; end if;
 select value,(ordinality-1)::integer into r,idx from jsonb_array_elements(m->'rows') with ordinality where value->>'id'=p_row_id limit 1;
 if r is null or (p.perfil<>'admin' and (nullif(trim(p.cidade),'') is null or td_cargas_private.normalizar_cidade(r->>'city')<>td_cargas_private.normalizar_cidade(p.cidade))) then raise exception 'Carga não encontrada ou fora da sua cidade'; end if;
 if p_action is distinct from 'conference' then raise exception 'Operação inválida'; end if;
 if exists(select 1 from jsonb_array_elements(coalesce(r->'conferences','[]')) c where c->>'operatorId'=auth.uid()::text) then return jsonb_build_object('ok',true); end if;
 entry=jsonb_build_object('id',gen_random_uuid(),'operatorId',auth.uid(),'operator',p.nome,'city',r->'city','createdAt',statement_timestamp());
 r=jsonb_set(r,'{conferences}',coalesce(r->'conferences','[]')||jsonb_build_array(entry));
 update public.td_manifestos set data=jsonb_set(m,array['rows',idx::text],r),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
