begin;
do $$
declare aid uuid;did uuid;city text;fixture text:='adjust-test-'||gen_random_uuid();r jsonb;due timestamptz:=statement_timestamp()+interval '5 days';res jsonb;
begin
 select id into aid from public.perfis_manifestos where ativo and perfil='admin' limit 1;
 select id,cidade into did,city from public.perfis_manifestos where ativo and perfil='entregador' and nullif(trim(cidade),'') is not null limit 1;
 assert aid is not null and did is not null;
 insert into public.td_manifestos(id,data) values(fixture,jsonb_build_object('id',fixture,'rows',jsonb_build_array(
 jsonb_build_object('id','a','city',city,'client','TEST','volumes',2,'freight',3500,'payments','[]'::jsonb,'receivedAt',statement_timestamp()-interval '2 days','collectionDueAt',due,'freights',jsonb_build_array(jsonb_build_object('id','f1','noteNumber','1','freight',1500,'volumes',1),jsonb_build_object('id','f2','noteNumber','2','freight',2000,'volumes',1))),
 jsonb_build_object('id','b','city','FOREIGN CITY','freight',11000,'payments','[]'::jsonb),
 jsonb_build_object('id','c','city',city,'freight',11000,'payments','[]'::jsonb,'collectionDueAt',statement_timestamp()-interval '1 day')
 )));
 perform set_config('request.jwt.claim.sub',did::text,true);
 begin perform public.td_ajustar_frete(fixture,'a',10000,'correction',' ',3500,0);raise exception 'TEST empty';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%justificativa%';end;
 begin perform public.td_ajustar_frete(fixture,'b',10000,'discount','test',11000,0);raise exception 'TEST foreign';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%fora da sua cidade%';end;
 begin perform public.td_ajustar_frete(fixture,'c',10000,'discount','test',11000,0);raise exception 'TEST blocked';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%bloqueado%';end;
 perform public.td_ajustar_frete(fixture,'a',10000,'correction','Frete lançado incorretamente',3500,0);
 select data->'rows'->0 into r from public.td_manifestos where id=fixture;
 assert (r->>'freight')::bigint=10000 and (r->>'originalFreight')::bigint=3500;
 assert (r->>'collectionDueAt')::timestamptz=due,'Ajuste renovou prazo';
 assert r->'payments'='[]'::jsonb,'Ajuste fabricou recebimento';
 assert r->'freightAdjustments'->0->>'operatorId'=did::text;
 assert (select sum((value->>'freight')::bigint)=10000 from jsonb_array_elements(r->'freights'));
 begin perform public.td_ajustar_frete(fixture,'a',9000,'discount','stale',3500,0);raise exception 'TEST stale';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%outro usuário%';end;
 begin perform public.td_pagar_conhecimento_versao(fixture,'a',null,'integral',null,null,'2026-11-22','Dinheiro',3500,0);raise exception 'TEST stale payment';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%atualizados%';end;
 perform public.td_registrar_pagamento(fixture,'a','f1','parcial',1000,'Acordo com administração','2026-11-22','Dinheiro');
 perform public.td_ajustar_frete(fixture,'a',9000,'discount','Acordo com cliente',10000,1000);
 select data->'rows'->0 into r from public.td_manifestos where id=fixture;
 assert (r->>'originalFreight')::bigint=3500 and jsonb_array_length(r->'freightAdjustments')=2;
 assert (select sum((value->>'amount')::bigint)=1000 from jsonb_array_elements(r->'payments'));
 perform td_cargas_private.distribuir_fretes(r);
 begin perform public.td_ajustar_frete(fixture,'a',999,'discount','invalid',9000,1000);raise exception 'TEST below paid';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%Valor inválido%';end;
 perform public.td_pagar_conhecimento_versao(fixture,'a',null,'integral',null,null,'2026-11-22','Dinheiro',9000,1000);
 select data->'rows'->0 into r from public.td_manifestos where id=fixture;
 assert (select sum((value->>'amount')::bigint)=9000 from jsonb_array_elements(r->'payments')),'Desconto foi contado como dinheiro';
 perform set_config('request.jwt.claim.sub',aid::text,true);
 perform public.td_ajustar_frete(fixture,'b',10000,'discount','Desconto de 110 para 100',11000,0);
 perform public.td_pagar_conhecimento_versao(fixture,'b',null,'integral',null,null,'2026-11-22','Dinheiro',10000,0);
 select data->'rows'->1 into r from public.td_manifestos where id=fixture;
 assert (r->>'freight')::bigint=10000 and (r->'payments'->0->>'amount')::bigint=10000;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.td_ajustar_frete(fixture,'b',9000,'discount','test',10000,10000);raise exception 'TEST anonymous';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%Acesso%';end;
 assert not has_function_privilege('anon','public.td_ajustar_frete(text,text,bigint,text,text,bigint,bigint)','execute');
end $$;
rollback;
