begin;
do $$
declare aid uuid;fixture text:='class-test-'||gen_random_uuid();old_item jsonb;new_item jsonb;r jsonb;
begin
 select id into aid from public.perfis_manifestos where ativo and perfil='admin' limit 1;
 assert aid is not null;
 perform set_config('request.jwt.claim.sub',aid::text,true);
 old_item=jsonb_build_object('id','100:200','tracking','100','noteNumber','200','sender','TEST','volumes',2,'freight',10000);
 new_item=old_item||jsonb_build_object('category','PCT BEBIDAS LATA','description','PCT BEBIDAS LATA');
 insert into public.td_manifestos(id,data) values(fixture,jsonb_build_object('id',fixture,'rows',jsonb_build_array(jsonb_build_object('id','K','client','TEST','city','ALMEIRIM','volumes',2,'freight',10000,'payments',jsonb_build_array(jsonb_build_object('id','pay','amount',1000,'freightId','100:200')),'freights',jsonb_build_array(old_item)),jsonb_build_object('id','K2','client','TEST','city','ALMEIRIM','volumes',2,'freight',10000,'payments','[]'::jsonb))));
 perform public.td_salvar_fretes(jsonb_build_array(jsonb_build_object('manifestId',fixture,'rowId','K','items',jsonb_build_array(new_item))));
 select data->'rows'->0 into r from public.td_manifestos where id=fixture;
 assert r->'freights'->0->>'category'='PCT BEBIDAS LATA';
 assert (r->'payments'->0->>'amount')::int=1000 and (r->'freights'->0->>'freight')::int=10000;
 perform public.td_gerenciar_mercadorias(fixture,'K2',jsonb_build_array(new_item),10000);
 select data->'rows'->1 into r from public.td_manifestos where id=fixture;
 assert r->'freights'->0->>'category'='PCT BEBIDAS LATA';
end $$;
rollback;
