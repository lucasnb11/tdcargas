-- Reprocessamento incremental: somente acrescenta conhecimentos ausentes.
create or replace function public.td_importar_manifesto_incremental(p_manifest jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare mid text; m jsonb; incoming jsonb; new_rows jsonb; added int; existing int; absent int; rev int; created boolean;
begin
 if auth.uid() is null or not manifestos_private.is_admin() then raise exception 'Apenas administradores podem importar manifestos';end if;
 mid=p_manifest->>'id';incoming=p_manifest->'rows';
 if coalesce(mid,'') !~ '^[0-9]{6}/[0-9]{4}$' or jsonb_typeof(incoming) is distinct from 'array' or jsonb_array_length(incoming) not between 1 and 5000 then raise exception 'Manifesto inválido';end if;
 if jsonb_array_length(incoming)<>(select count(distinct value->>'id') from jsonb_array_elements(incoming)) then raise exception 'Conhecimentos duplicados no arquivo';end if;
 if exists(select 1 from jsonb_array_elements(incoming) r where coalesce(r->>'id','') !~ '^[0-9]{6}/[0-9]{4}$' or nullif(trim(r->>'client'),'') is null or nullif(trim(r->>'city'),'') is null or jsonb_typeof(r->'freight') is distinct from 'number' or (r->>'freight')::numeric not between 0 and 100000000000 or (r->>'freight')::numeric<>trunc((r->>'freight')::numeric) or jsonb_typeof(r->'volumes') is distinct from 'number' or (r->>'volumes')::numeric not between 0 and 1000000 or (r->>'volumes')::numeric<>trunc((r->>'volumes')::numeric)) then raise exception 'Dados de conhecimento inválidos';end if;
 if coalesce(p_manifest->>'vessel','') not in ('F/B SÃO DOMINGOS V','F/B DONA DOMINGAS') then raise exception 'Selecione a embarcação';end if;
 -- Insere a identidade apenas uma vez, inclusive com importações simultâneas.
 insert into public.td_manifestos(id,data) values(mid,jsonb_build_object('id',mid,'date',p_manifest->>'date','time',p_manifest->>'time','route',p_manifest->>'route','vessel',p_manifest->>'vessel','rows','[]'::jsonb)) on conflict(id) do nothing;
 created=found;
 select data,revision into m,rev from public.td_manifestos where id=mid for update;
 select coalesce(jsonb_agg(jsonb_build_object('id',r->>'id','client',r->>'client','city',r->>'city','kind',r->>'kind','goods',r->'goods','volumes',r->'volumes','freight',r->'freight','payments','[]'::jsonb,'conferences','[]'::jsonb) order by ord),'[]'::jsonb) into new_rows from jsonb_array_elements(incoming) with ordinality a(r,ord) where not exists(select 1 from jsonb_array_elements(m->'rows') old where old->>'id'=r->>'id');
 added=jsonb_array_length(new_rows);existing=jsonb_array_length(incoming)-added;
 select count(*) into absent from jsonb_array_elements(m->'rows') old where not exists(select 1 from jsonb_array_elements(incoming) r where r->>'id'=old->>'id');
 if added>0 then
  m=jsonb_set(m,'{rows}',(m->'rows')||new_rows);
  if created then update public.td_manifestos set data=m where id=mid;else update public.td_manifestos set data=m,revision=revision+1 where id=mid returning revision into rev;end if;
 end if;
 return jsonb_build_object('ok',true,'created',created,'added',added,'existing',existing,'absent',absent,'manifest',m||jsonb_build_object('revision',rev));
end $$;
revoke all on function public.td_importar_manifesto_incremental(jsonb) from public,anon;
grant execute on function public.td_importar_manifesto_incremental(jsonb) to authenticated;

-- Só vincula detalhes que ainda não existem, sob o mesmo bloqueio da viagem.
create or replace function public.td_vincular_fretes_faltantes(p_documents jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare mid text; d jsonb; m jsonb; r jsonb; pending jsonb:='[]'; preserved int:=0; result jsonb;
begin
 if auth.uid() is null or not manifestos_private.is_admin() then raise exception 'Apenas administradores podem vincular notas/fretes';end if;
 if jsonb_typeof(p_documents) is distinct from 'array' or jsonb_array_length(p_documents) not between 1 and 1000 then raise exception 'Lista de conhecimentos inválida';end if;
 for mid in select distinct value->>'manifestId' from jsonb_array_elements(p_documents) order by 1 loop
  select data into m from public.td_manifestos where id=mid for update;
  if m is null then raise exception 'Manifesto não encontrado';end if;
  for d in select value from jsonb_array_elements(p_documents) where value->>'manifestId'=mid loop
   select value into r from jsonb_array_elements(m->'rows') where value->>'id'=d->>'rowId';
   if r is null then raise exception 'Conhecimento não encontrado no manifesto';end if;
   if jsonb_array_length(coalesce(r->'freights','[]'))>0 or coalesce((r->>'itemsManaged')::boolean,false) or jsonb_array_length(coalesce(r->'freightAdjustments','[]'))>0 then preserved=preserved+1;continue;end if;
   pending=pending||jsonb_build_array(d);
  end loop;
 end loop;
 if jsonb_array_length(pending)>0 then result=public.td_salvar_fretes(pending);else result=jsonb_build_object('ok',true,'updated',0);end if;
 return result||jsonb_build_object('preserved',preserved);
end $$;
revoke all on function public.td_vincular_fretes_faltantes(jsonb) from public,anon;
grant execute on function public.td_vincular_fretes_faltantes(jsonb) to authenticated;
