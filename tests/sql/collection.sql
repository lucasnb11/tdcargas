-- Integração: executa em transação e não preserva fixtures nem pagamentos.
begin;
do $$
declare admin_id uuid;driver_id uuid;driver_city text;fixture text:='deadline-test-'||gen_random_uuid();r jsonb;before_due timestamptz;result jsonb;rows jsonb;
begin
 select id into admin_id from public.perfis_manifestos where ativo and perfil='admin' limit 1;
 select id,cidade into driver_id,driver_city from public.perfis_manifestos where ativo and perfil='entregador' and nullif(trim(cidade),'') is not null limit 1;
 assert admin_id is not null and driver_id is not null,'Perfis de teste indisponíveis';
 rows=jsonb_build_array(
  jsonb_build_object('id','normal','client','TEST NORMAL','city',driver_city,'freight',1000,'volumes',2,'payments','[]'::jsonb,'conferences','[]'::jsonb),
  jsonb_build_object('id','open','client','TEST BATCH','city',driver_city,'freight',1000,'volumes',2,'payments','[]'::jsonb),
  jsonb_build_object('id','expired','client','TEST BATCH','city',driver_city,'freight',1000,'volumes',2,'payments','[]'::jsonb,'receivedAt',statement_timestamp()-interval '8 days','collectionDueAt',statement_timestamp()-interval '1 day'),
  jsonb_build_object('id','foreign','client','TEST FOREIGN','city','OTHER CITY TEST','freight',1000,'payments','[]'::jsonb),
  jsonb_build_object('id','notes','client','TEST NOTES','city',driver_city,'freight',1000,'volumes',2,'payments','[]'::jsonb,'receivedAt',statement_timestamp()-interval '8 days','collectionDueAt',statement_timestamp()-interval '1 day','freights',jsonb_build_array(jsonb_build_object('id','f1','noteNumber','1','volumes',1,'freight',400),jsonb_build_object('id','f2','noteNumber','2','volumes',1,'freight',600)))
 );
 insert into public.td_manifestos(id,data) values(fixture,jsonb_build_object('id',fixture,'rows',rows));
 perform set_config('request.jwt.claim.sub',driver_id::text,true);
 perform public.td_controlar_cobranca(fixture,'normal','receive');
 select data->'rows'->0 into r from public.td_manifestos where id=fixture;
 assert (r->>'collectionDueAt')::timestamptz-(r->>'receivedAt')::timestamptz=interval '168 hours','Recebimento não iniciou 7 dias';
 before_due=(r->>'collectionDueAt')::timestamptz;
 perform public.td_controlar_cobranca(fixture,'normal','receive');
 assert (select (data->'rows'->0->>'collectionDueAt')::timestamptz=before_due from public.td_manifestos where id=fixture),'Confirmação repetida renovou prazo';
 begin perform public.td_controlar_cobranca(fixture,'foreign','receive');raise exception 'TEST acesso cidade';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%fora da sua cidade%';end;
 begin perform public.td_controlar_cobranca(fixture,'expired','unlock');raise exception 'TEST entregador liberou';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%administradores%';end;
 perform public.td_controlar_cobranca(fixture,'expired','receive');
 assert (select (data->'rows'->2->>'collectionDueAt')::timestamptz<statement_timestamp() from public.td_manifestos where id=fixture),'Repetir recebimento desbloqueou';
 begin perform public.td_registrar_pagamento(fixture,'expired',null,'integral',null,null,'2026-01-01','Dinheiro');raise exception 'TEST pagamento vencido';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%bloqueado%';end;
 begin perform public.td_registrar_pagamento(fixture,'notes','f1','integral',null,null,'2026-01-01','Dinheiro');raise exception 'TEST nota vencida';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%bloqueado%';end;
 begin perform public.td_operar_manifesto(fixture,'expired','pay','integral',null,null,'2026-01-01','Dinheiro');raise exception 'TEST API legada';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%bloqueado%';end;
 begin perform public.td_pagar_destinatario(fixture,'TEST BATCH',2000,2,'2026-01-01','Dinheiro');raise exception 'TEST lote vencido';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%bloqueado%';end;
 assert (select jsonb_array_length(data->'rows'->1->'payments')=0 from public.td_manifestos where id=fixture),'Lote não foi revertido integralmente';
 -- Simula prazo perto de vencer sem tocar dados reais.
 update public.td_manifestos set data=jsonb_set(data,'{rows,0,collectionDueAt}',to_jsonb(statement_timestamp()+interval '1 hour')) where id=fixture;
 perform public.td_registrar_pagamento(fixture,'normal',null,'parcial',100,'Sem dinheiro','2026-01-01','Dinheiro');
 assert (select (data->'rows'->0->>'collectionDueAt')::timestamptz=statement_timestamp()+interval '168 hours' from public.td_manifestos where id=fixture),'Parcial não renovou pelo relógio servidor';
 assert (select data->'rows'->0->'collectionEvents'->-1->>'action'='partial_payment' from public.td_manifestos where id=fixture),'Renovação não auditada';
 -- Um item vencido não impede pagar outro conhecimento.
 perform public.td_registrar_pagamento(fixture,'open',null,'integral',null,null,'2026-01-01','Dinheiro');
 result=public.td_listar_manifestos();
 assert exists(select 1 from jsonb_array_elements(result) m,jsonb_array_elements(m->'rows') k where m->>'id'=fixture and k->>'id'='normal' and k->>'receivedAt' is not null and k->>'collectionDueAt' is not null),'Entregador não recebeu prazo';
 assert not exists(select 1 from jsonb_array_elements(result) m,jsonb_array_elements(m->'rows') k where m->>'id'=fixture and k->>'id'='foreign'),'Vazamento de cidade';
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 begin perform public.td_registrar_pagamento(fixture,'expired',null,'integral',null,null,'2026-01-01','Dinheiro');raise exception 'TEST admin sem liberar';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%bloqueado%';end;
 perform public.td_controlar_cobranca(fixture,'expired','unlock');
 assert (select data->'rows'->2->'collectionEvents'->-1->>'action'='unlock' from public.td_manifestos where id=fixture),'Liberação não auditada';
 perform public.td_controlar_cobranca(fixture,'notes','unlock');
 update public.td_manifestos set data=jsonb_set(data,'{rows,4,collectionDueAt}',to_jsonb(statement_timestamp()+interval '1 hour')) where id=fixture;
 perform set_config('request.jwt.claim.sub',driver_id::text,true);
 perform public.td_registrar_pagamento(fixture,'notes','f1','integral',null,null,'2026-01-01','Dinheiro');
 assert (select (data->'rows'->4->>'collectionDueAt')::timestamptz=statement_timestamp()+interval '168 hours' from public.td_manifestos where id=fixture),'Nota quitada com saldo no conhecimento não renovou';
 perform public.td_registrar_pagamento(fixture,'expired',null,'integral',null,null,'2026-01-01','Dinheiro');
 assert (select (data->'rows'->2->'payments'->0->>'amount')::bigint=1000 from public.td_manifestos where id=fixture),'Item liberado não recebeu pagamento';
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.td_controlar_cobranca(fixture,'normal','receive');raise exception 'TEST acesso anonimo';exception when others then if sqlerrm like 'TEST%' then raise;end if;assert sqlerrm like '%não autorizado%';end;
end $$;
rollback;
