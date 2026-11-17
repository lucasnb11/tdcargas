-- Inclui a embarcação na projeção dos entregadores; mantém as restrições de cidade.
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
   if jsonb_array_length(filtered)>0 then result=result||jsonb_build_array(jsonb_build_object('id',m.id,'date',m.data->'date','time',m.data->'time','route',m.data->'route','vessel',m.data->'vessel','rows',filtered)); end if;
  end if;
 end loop;
 return result;
end $$;
