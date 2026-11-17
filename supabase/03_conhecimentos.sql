-- Cadastro de conhecimentos em manifestos existentes, sem alterar os registros atuais.
create or replace function public.td_adicionar_conhecimento(p_manifest_id text,p_row jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb; r jsonb; city text; freight numeric; volumes numeric;
begin
 if auth.uid() is null or not manifestos_private.is_admin() then raise exception 'Apenas administradores podem cadastrar conhecimentos'; end if;
 if nullif(trim(p_manifest_id),'') is null then raise exception 'Selecione o manifesto do conhecimento'; end if;
 select data into m from public.td_manifestos where id=p_manifest_id for update;
 if m is null then raise exception 'Manifesto não encontrado'; end if;
 if jsonb_typeof(p_row) is distinct from 'object' then raise exception 'Conhecimento inválido'; end if;
 if nullif(trim(p_row->>'id'),'') is null or length(trim(p_row->>'id'))>60 or nullif(trim(p_row->>'client'),'') is null or length(trim(p_row->>'client'))>200 then raise exception 'Informe o número do conhecimento e o cliente pagador'; end if;
 if exists(select 1 from jsonb_array_elements(m->'rows') e where upper(trim(e->>'id'))=upper(trim(p_row->>'id'))) then raise exception 'Este conhecimento já está cadastrado neste manifesto'; end if;
 if jsonb_array_length(m->'rows')>=5000 then raise exception 'O manifesto atingiu o limite de 5000 conhecimentos'; end if;
 city=td_cargas_private.normalizar_cidade(p_row->>'city');
 if city='' or not (exists(select 1 from public.td_cidades c where c.key=city) or city in ('ALMEIRIM','GURUPA','PORTO DE MOZ') or exists(select 1 from public.td_manifestos t cross join lateral jsonb_array_elements(t.data->'rows') e where td_cargas_private.normalizar_cidade(e->>'city')=city)) then raise exception 'Selecione uma cidade cadastrada'; end if;
 if coalesce(p_row->>'kind','') not in ('FOB','CIF','VEÍCULO') then raise exception 'Tipo de carga inválido'; end if;
 if jsonb_typeof(p_row->'freight') is distinct from 'number' or jsonb_typeof(p_row->'volumes') is distinct from 'number' then raise exception 'Frete e volumes inválidos'; end if;
 freight=(p_row->>'freight')::numeric; volumes=(p_row->>'volumes')::numeric;
 if freight<>trunc(freight) or freight<1 or freight>100000000000 or volumes<>trunc(volumes) or volumes<1 or volumes>1000000 then raise exception 'Frete e volumes inválidos'; end if;
 r=jsonb_build_object('id',trim(p_row->>'id'),'client',trim(p_row->>'client'),'city',city,'kind',p_row->>'kind','volumes',volumes::bigint,'freight',freight::bigint,'payments','[]'::jsonb,'conferences','[]'::jsonb,'source','manual','createdAt',now(),'createdBy',auth.uid());
 update public.td_manifestos set data=jsonb_set(m,'{rows}',(m->'rows')||jsonb_build_array(r)),revision=revision+1 where id=p_manifest_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.td_adicionar_conhecimento(text,jsonb) from public,anon;
grant execute on function public.td_adicionar_conhecimento(text,jsonb) to authenticated;
