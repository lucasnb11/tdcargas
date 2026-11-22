const {test}=require('node:test');
const assert=require('node:assert/strict');
const {validateKnowledge}=require('../.test-build/knowledge.js');
const {clientSummary,tripSummary,pendingRowsForManifest}=require('../.test-build/control.js');
const valid={id:' CT-001 ',client:' Cliente A ',city:'Gurupá',kind:'FOB',volumes:2,freight:15000};
test('conhecimento exige manifesto e dados válidos',()=>{
 assert.throws(()=>validateKnowledge('',valid,['GURUPA']),/manifesto/);
 assert.equal(validateKnowledge('001',valid,['GURUPA']).city,'GURUPA');
 for(const change of [{freight:-1},{freight:1.5},{volumes:0},{volumes:1.5},{client:''},{city:'NAO CADASTRADA'},{kind:'OUTRO'}])assert.throws(()=>validateKnowledge('001',{...valid,...change},['GURUPA']));
});
test('saldo por cliente e manifesto preserva conhecimentos pagos e parciais',()=>{
 const first={id:'M1',rows:[{...valid,id:'C1',client:'Cliente A',payments:[{amount:5000}]},{...valid,id:'C2',client:'CLIENTE A',freight:20000,payments:[]}]};
 const second={id:'M2',rows:[{...valid,id:'C3',client:'Cliente A',freight:10000,payments:[{amount:10000}]}]};
 const [client]=clientSummary([first,second]);
 assert.equal(client.manifestIds.size,2);assert.equal(client.rows.length,3);
 assert.equal(client.total,45000);assert.equal(client.received,15000);assert.equal(client.balance,30000);
 assert.deepEqual(tripSummary(first),{count:2,total:35000,received:5000,balance:30000,pendingCount:2});
});

test('pendências ficam limitadas ao manifesto selecionado, inclusive na ausência de saldo',()=>{
 const row=(id,freight,payments=[])=>({id,client:'Cliente A',freight,payments});
 const manifests=[{id:'M1',rows:[row('C1',10000),row('C2',20000,[{amount:5000}]),row('C3',1000,[{amount:1000}])]},{id:'M2',rows:[row('C4',7000)]},{id:'M3',rows:[row('C5',8000,[{amount:8000}])]}];
 assert.deepEqual(pendingRowsForManifest(manifests,'M1').map(r=>r.id),['C1','C2']);
 assert.deepEqual(pendingRowsForManifest(manifests,'M2').map(r=>r.id),['C4']);
 assert.deepEqual(pendingRowsForManifest(manifests,'M3'),[]);
 assert.deepEqual(pendingRowsForManifest(manifests,''),[]);
 assert.deepEqual(pendingRowsForManifest(manifests,'inexistente'),[]);
});

const {PARTIAL_REASONS,partialPaymentNote}=require('../.test-build/payment.js');
test('pagamento parcial exige um dos quatro motivos e detalhes conforme a escolha',()=>{
 assert.equal(PARTIAL_REASONS.length,4);
 assert.equal(partialPaymentNote('Sem dinheiro',null,'ignorar'),'Sem dinheiro');
 assert.equal(partialPaymentNote('Acordo com administração',null,''),'Acordo com administração');
 assert.equal(partialPaymentNote('Pagamento parcelado',3,''),'Pagamento parcelado em 3 vezes');
 for(const n of [null,undefined,'3',0,1,2.5,NaN,Infinity])assert.throws(()=>partialPaymentNote('Pagamento parcelado',n,''),/parcelas/);
 assert.equal(partialPaymentNote('Outros',null,'  Motivo combinado  '),'Outros: Motivo combinado');
 assert.throws(()=>partialPaymentNote('Outros',null,'   '),/Descreva/);
 assert.throws(()=>partialPaymentNote('Outros',null,'x'.repeat(1901)),/1900/);
 for(const reason of ['',null,'Motivo livre'])assert.throws(()=>partialPaymentNote(reason,3,'texto'),/Selecione/);
});

const {recipientGroups}=require('../.test-build/control.js');
test('agrupa destinatário dentro do manifesto, preservando conhecimentos e pagamentos individuais',()=>{
 const rows=[
  {id:'C1',manifestId:'M1',client:' Cliente A ',city:'GURUPA',freight:10000,payments:[{amount:2500}],conferences:[]},
  {id:'C2',manifestId:'M1',client:'CLIENTE A',city:'ALMEIRIM',freight:5000,payments:[{amount:5000}],conferences:[{operator:'Teste'}]},
  {id:'C1',manifestId:'M2',client:'Cliente A',city:'GURUPA',freight:3000,payments:[],conferences:[]},
  {id:'C3',manifestId:'M1',client:'Cliente B',city:'GURUPA',freight:8000,payments:[],conferences:[]}
 ];
 const groups=recipientGroups(rows);
 assert.equal(groups.length,3);
 const group=groups.find(g=>g.manifestId==='M1'&&g.recipientKey==='CLIENTE A');
 assert.deepEqual(group.rows.map(r=>r.id),['C1','C2']);
 assert.equal(group.freight,15000);assert.equal(group.received,7500);assert.equal(group.balance,7500);assert.equal(group.conferenceCount,1);
 assert.deepEqual([...group.cities],['GURUPA','ALMEIRIM']);
 assert.equal(group.rows[0],rows[0]);assert.equal(group.rows[0].payments.length,1);
 assert.deepEqual(recipientGroups([]),[]);
});

const {VESSELS,validateVessel}=require('../.test-build/vessels.js');
test('importação exige uma das duas embarcações e mantém o vínculo na consulta',()=>{
 for(const vessel of VESSELS){
  assert.equal(validateVessel(vessel),vessel);
  const [group]=recipientGroups(require('../.test-build/control.js').tripRows({id:'M1',vessel,rows:[{id:'C1',client:'Cliente',freight:100,payments:[],city:'GURUPA'}]}));
  assert.equal(group.vessel,vessel);
 }
 for(const value of ['',null,undefined,'OUTRA EMBARCAÇÃO'])assert.throws(()=>validateVessel(value),/Selecione a embarcação/);
});

const {validateFreights,freightBalances,freightPaymentRow}=require('../.test-build/freights.js');
const sampleFreights=[{id:'r1:n1',noteNumber:'n1',tracking:'r1',sender:'Exemplo A',volumes:1,freight:2000},{id:'r2:n2',noteNumber:'n2',tracking:'r2',sender:'Exemplo B',volumes:2,freight:3000},{id:'r3:n3',noteNumber:'n3',tracking:'r3',sender:'Exemplo C',volumes:3,freight:5000}];
test('pagamentos por conhecimento e por nota compartilham o mesmo saldo sem duplicação',()=>{
 const row={id:'C1',freight:10000,freights:sampleFreights,payments:[{amount:500,freightId:'r2:n2'},{amount:2500},{amount:2000,freightId:'r2:n2'}]};
 const items=freightBalances(row);
 assert.deepEqual(items.map(i=>i.received),[2000,3000,0]);
 assert.deepEqual(items.map(i=>i.balance),[0,0,5000]);
 assert.equal(items.reduce((s,i)=>s+i.received,0),5000);
 const final=freightBalances({...row,payments:[...row.payments,{amount:5000}]});
 assert.equal(final.reduce((s,i)=>s+i.balance,0),0);
 const target=freightPaymentRow(row,items[2]);assert.equal(target.id,'C1');assert.equal(target.freightId,'r3:n3');assert.equal(target.freight,5000);
 assert.equal(sampleFreights[0].received,undefined);
});
test('pagamentos antigos são distribuídos por ordem e notas inválidas são recusadas',()=>{
 assert.deepEqual(freightBalances({freight:10000,freights:sampleFreights,payments:[{amount:3500}]}).map(i=>i.received),[2000,1500,0]);
 assert.throws(()=>validateFreights(sampleFreights,9999),/soma/);
 assert.throws(()=>validateFreights([sampleFreights[0],sampleFreights[0]],4000),/duplicados/);
 assert.throws(()=>freightBalances({freight:10000,freights:sampleFreights,payments:[{amount:3000,freightId:'r1:n1'}]}),/excedem/);
 assert.throws(()=>freightBalances({freight:10000,freights:sampleFreights,payments:[{amount:100,freightId:'inexistente'}]}),/não encontrado/);
});
const {parseFreightDocuments}=require('../.test-build/freight-parser.js');
const freightDoc=`Conhecimento Usuario Ultima Alteracao
000001/2026 OPERADOR 17/11/2026 09:00
Viagem
000099/2026 13/11/2026 18:00 F/B EXEMPLO
QTD de Fretes: 3 Vencimento: 19/11/2026 Frete: 100,00
10001 REMETENTE A 123 500,00 1 0 ESTIVAS 20,00
10002 REMETENTE B 124 600,00 2 0 ESTIVAS 30,00
10003 REMETENTE C 125 700,00 3 0 ESTIVAS 50,00`;
const manifestsForFreights=[{id:'000099/2026',rows:[{id:'000001/2026',client:'Destinatário de exemplo',freight:10000}]}];
test('leitura de notas exige viagem, conhecimento, quantidade e soma corretos',()=>{
 const parsed=parseFreightDocuments(freightDoc,manifestsForFreights);assert.equal(parsed.errors.length,0);assert.equal(parsed.records.length,1);assert.equal(parsed.records[0].items.length,3);
 assert.equal(parseFreightDocuments(freightDoc.replace('50,00','51,00'),manifestsForFreights).records.length,0);
 assert.equal(parseFreightDocuments(freightDoc.replace('Fretes: 3','Fretes: 4'),manifestsForFreights).records.length,0);
 assert.equal(parseFreightDocuments(freightDoc,[]).records.length,0);
 assert.equal(parseFreightDocuments(freightDoc+'\n'+freightDoc,manifestsForFreights).records.length,1);
 assert.throws(()=>parseFreightDocuments('arquivo irreconhecível',[]),/reconhecer/);
});

test('segunda etapa limita o vínculo ao manifesto que acabou de ser importado',()=>{
 assert.equal(parseFreightDocuments(freightDoc,manifestsForFreights,'000099/2026').records.length,1);
 const other=parseFreightDocuments(freightDoc,manifestsForFreights,'000100/2026');
 assert.equal(other.records.length,0);assert.match(other.errors[0],/diferente do manifesto/);
 // A importação avulsa continua aceitando todos os manifestos cadastrados.
 assert.equal(parseFreightDocuments(freightDoc,manifestsForFreights).records.length,1);
});

const {displayVessel,departureDate,displayRoute}=require('../.test-build/vessels.js');
test('saída identifica sexta-feira sem deslocar a data por fuso e recupera embarcação da rota antiga',()=>{
 assert.deepEqual(departureDate('13/11/2026'),{date:'13/11/2026',weekday:'Sexta-feira',iso:'2026-11-13'});
 assert.equal(departureDate('2026-11-13').weekday,'Sexta-feira');
 assert.equal(departureDate('29/02/2024').weekday,'Quinta-feira');
 assert.equal(departureDate('31/02/2026').weekday,'');
 assert.equal(departureDate(undefined).date,'Data não informada');
 assert.equal(displayVessel({route:'BELÉM / ALMEIRIM - F/B SÃO DOMINGOS V'}),'F/B SÃO DOMINGOS V');
 assert.equal(displayVessel({route:'BELÉM / GURUPÁ - F/B DONA DOMINGAS'}),'F/B DONA DOMINGAS');
 assert.equal(displayVessel({vessel:'F/B DONA DOMINGAS',route:'BELÉM - F/B SÃO DOMINGOS V'}),'F/B DONA DOMINGAS');
 assert.equal(displayVessel({route:'BELÉM / ALMEIRIM'}),'Embarcação não informada');
 assert.equal(displayVessel({route:'F/B SAO DOMINGOS VIII'}),'Embarcação não informada');
 assert.equal(displayRoute({route:'BELÉM / ALMEIRIM - F/B SÃO DOMINGOS V'}),'BELÉM / ALMEIRIM');
});

const {dashboardData}=require('../.test-build/dashboard.js');
test('dashboard consolida valores e quantidades sem duplicar pagamentos de notas ou lotes',()=>{
 const manifests=[{id:'M1',rows:[{id:'C1',client:'A',city:'Gurupá',freight:10000,payments:[{amount:3000,freightId:'n1'}],freights:[{freight:10000}]},{id:'C2',client:'B',city:'GURUPA',freight:5000,payments:[{amount:5000,batchId:'lote'}]},{id:'C3',client:'C',city:'ALMEIRIM',freight:20000,payments:[]}]},{id:'M2',rows:[{id:'C4',client:'D',city:'ALMEIRIM',freight:1000,payments:[{amount:1000}]}]}];
 const all=dashboardData(manifests,{role:'admin'});
 assert.equal(all.summary.count,4);assert.equal(all.summary.manifestCount,2);assert.equal(all.summary.paidCount,2);assert.equal(all.summary.pendingCount,2);assert.equal(all.summary.partialCount,1);
 assert.equal(all.summary.freight,36000);assert.equal(all.summary.received,9000);assert.equal(all.summary.balance,27000);assert.equal(all.summary.receivedPercent,25);assert.equal(all.cities.length,2);
 const city=dashboardData(manifests,{role:'admin'},'GURUPA');assert.equal(city.summary.count,2);assert.equal(city.summary.received,8000);assert.equal(city.summary.balance,7000);
 const operator=dashboardData(manifests,{role:'entregador',city:'Gurupá'},'ALMEIRIM');assert.equal(operator.summary.count,2);assert.equal(operator.summary.balance,7000);assert.equal(operator.cities.length,1);assert.equal(operator.cities[0].key,'GURUPA');
 assert.equal(dashboardData(manifests,{role:'entregador',city:''}).summary.count,0);
 assert.equal(dashboardData(manifests,{role:'blocked',city:'GURUPA'}).summary.count,0);
 assert.equal(dashboardData(manifests,{role:'admin'},'SEM DADOS').summary.count,0);
 assert.equal(dashboardData([],{role:'admin'}).summary.receivedPercent,0);
});

test('pizza do entregador soma volumes e filtra viagem sem acessar outra cidade',()=>{
 const manifests=[{id:'M1',rows:[{id:'C1',city:'GURUPA',volumes:10,freight:10000,payments:[{amount:10000}]},{id:'C2',city:'Gurupá',volumes:20,freight:20000,payments:[{amount:5000}]},{id:'C3',city:'ALMEIRIM',volumes:900,freight:20000,payments:[]}]},{id:'M2',rows:[{id:'C4',city:'GURUPA',volumes:7,freight:7000,payments:[]}]},{id:'M3',rows:[{id:'C5',city:'ALMEIRIM',volumes:100,freight:5000,payments:[]}]}];
 const user={role:'entregador',city:'GURUPA'};
 const all=dashboardData(manifests,user).summary;assert.equal(all.piecesCount,37);assert.equal(all.paidPieces,10);assert.equal(all.pendingPieces,27);
 const trip=dashboardData(manifests,user,'','M1').summary;assert.equal(trip.piecesCount,30);assert.equal(trip.paidPieces,10);assert.equal(trip.pendingPieces,20);
 assert.equal(dashboardData(manifests,user,'','M2').summary.piecesCount,7);
 assert.equal(dashboardData(manifests,user,'','M3').summary.piecesCount,0);
 assert.equal(dashboardData(manifests,user,'','inexistente').summary.piecesCount,0);
 assert.equal(dashboardData(manifests,{role:'admin'}).summary.count,5);
});
test('peças de notas integralmente pagas são reconhecidas sem proporcionalizar pagamentos parciais',()=>{
 const row={id:'C1',city:'GURUPA',volumes:6,freight:10000,freights:sampleFreights,payments:[{amount:2000,freightId:'r1:n1'},{amount:1000,freightId:'r2:n2'}]};
 const result=dashboardData([{id:'M1',rows:[row]}],{role:'entregador',city:'GURUPA'}).summary;
 assert.equal(result.piecesCount,6);assert.equal(result.paidPieces,1);assert.equal(result.pendingPieces,5);
 const unknown=dashboardData([{id:'M1',rows:[{...row,volumes:undefined,freights:[]}]}],{role:'entregador',city:'GURUPA'}).summary;
 assert.equal(unknown.unknownVolumesCount,1);assert.equal(unknown.piecesCount,0);
});

test('dashboard administrador combina cidade e viagem inclusive no resumo por cidade',()=>{
 const manifests=[{id:'A',rows:[{id:'1',city:'GURUPA',freight:1000,volumes:2,payments:[]},{id:'2',city:'ALMEIRIM',freight:2000,volumes:3,payments:[]}]},{id:'B',rows:[{id:'3',city:'GURUPA',freight:4000,volumes:4,payments:[]}]}];
 const trip=dashboardData(manifests,{role:'admin'},'','A');assert.equal(trip.summary.count,2);assert.equal(trip.summary.freight,3000);assert.equal(trip.cities.reduce((sum,city)=>sum+city.freight,0),3000);
 const combined=dashboardData(manifests,{role:'admin'},'GURUPA','A');assert.equal(combined.summary.count,1);assert.equal(combined.summary.freight,1000);assert.equal(combined.cities.find(city=>city.key==='GURUPA').freight,1000);
 assert.equal(dashboardData(manifests,{role:'admin'},'ALMEIRIM','B').summary.count,0);
 assert.equal(dashboardData(manifests,{role:'admin'},'GURUPA').summary.freight,5000);
});

const {collectionState,assertCollectionOpen}=require('../.test-build/collection.js');
test('prazo de cobrança bloqueia apenas saldo vencido e inclui o instante exato do vencimento',()=>{
 const now=Date.parse('2026-11-18T18:00:00Z');
 const row={freight:1000,payments:[{amount:100}],receivedAt:'2026-11-11T18:00:00Z',collectionDueAt:'2026-11-18T18:00:00Z'};
 assert.equal(collectionState(row,now-1).blocked,false);assert.equal(collectionState(row,now).blocked,true);assert.throws(()=>assertCollectionOpen(row,now),/bloqueado/);
 assert.equal(collectionState({...row,payments:[{amount:1000}]},now).blocked,false);
 assert.equal(collectionState({...row,collectionDueAt:'2026-11-25T18:00:00Z'},now).blocked,false);
 assert.equal(collectionState({freight:1000,payments:[],conferences:[{createdAt:'2025-01-01'}]},now).blocked,false);
});

const {collectionReport,collectionReportCsv,REPORT_CATEGORIES}=require('../.test-build/collection-report.js');
test('relatório separa situações exclusivas por saldo atual sem duplicar notas e pagamentos parciais antigos',()=>{
 const manifests=[{id:'A',date:'18/11/2026',rows:[{id:'paid',client:'CLIENTE',city:'Gurupá',volumes:2,freight:1000,payments:[{amount:200,type:'parcial'},{amount:800,type:'integral'}],freights:[{freight:1000,payments:[{amount:1000}]}]},{id:'partial',client:'CLIENTE',city:'GURUPA',volumes:3,freight:2000,payments:[{amount:500}],receivedAt:'2026-11-01T00:00:00Z',collectionDueAt:'2026-11-08T00:00:00Z'},{id:'pending',client:'CLIENTE',city:'ALMEIRIM',volumes:4,freight:3000,payments:[]}]},{id:'B',rows:[{id:'paid',client:'OUTRO',city:'GURUPA',volumes:5,freight:4000,payments:[]}]}];
 const filters={manifestId:'',city:'',category:'',query:''};
 const data=collectionReport(manifests,{role:'admin'},filters,Date.parse('2026-11-18T00:00:00Z'));
 assert.deepEqual(data.groups.map(g=>g.count),[1,1,2]);assert.equal(data.rows.length,4);assert.equal(data.groups[0].received,1000);assert.equal(data.groups[1].balance,1500);assert.equal(data.groups[1].rows[0].blocked,true);assert.equal(data.groups[2].pieces,9);
 const combined=collectionReport(manifests,{role:'admin'},{...filters,manifestId:'A',city:'GURUPA',category:REPORT_CATEGORIES[1]});assert.equal(combined.rows.length,1);assert.equal(combined.rows[0].id,'partial');
 const scoped=collectionReport(manifests,{role:'entregador',city:'GURUPA'},filters);assert.equal(scoped.rows.length,3);assert.ok(scoped.rows.every(row=>row.city!=='ALMEIRIM'));
 assert.equal(collectionReport(manifests,{role:'entregador',city:'GURUPA'},{...filters,city:'ALMEIRIM'}).rows.length,0);
 assert.equal(collectionReport(manifests,{role:'entregador',city:''},filters).rows.length,0);
 assert.equal(collectionReport(manifests,{role:'blocked'},filters).rows.length,0);
 assert.equal(collectionReport(manifests,{role:'admin'},{...filters,query:'OUTRO'}).rows.length,1);
 assert.equal(collectionReport(manifests,{role:'admin'},{...filters,manifestId:'inexistente'}).rows.length,0);
});
test('CSV do relatório respeita os registros filtrados e neutraliza fórmulas de planilhas',()=>{
 const manifests=[{id:'A',rows:[{id:'01',client:'=HYPERLINK("exemplo")',city:'GURUPA',volumes:1,freight:1000,payments:[{amount:1000}]},{id:'02',client:'NÃO EXPORTAR',city:'GURUPA',volumes:2,freight:2000,payments:[]}]}];
 const data=collectionReport(manifests,{role:'admin'},{manifestId:'A',city:'',category:REPORT_CATEGORIES[0],query:''});const csv=collectionReportCsv(data.rows);
 assert.ok(csv.startsWith('\ufeff'));assert.ok(csv.includes("'=HYPERLINK"));assert.ok(!csv.includes('NÃO EXPORTAR'));assert.equal(csv.split('\r\n').length,2);assert.ok(csv.includes('"10.00";"10.00";"0.00"'));
});

test('API de relatórios exige administrador antes de carregar qualquer dado',async()=>{
 const fs=require('node:fs'),vm=require('node:vm'),ts=require('typescript');
 const source=ts.transpileModule(fs.readFileSync('app/api/reports/route.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
 for(const role of [null,'entregador','blocked','admin']){
  let reads=0;const exported={};
  vm.runInNewContext(source,{exports:exported,require:(name)=>{
   if(name.endsWith('/access'))return {getAccess:async()=>role?{role}:null};
   if(name.endsWith('/private-json'))return {privateJson:(body,options)=>({body,status:options?.status||200})};
   if(name.endsWith('/repository'))return {loadManifests:async()=>{reads++;return [{id:'A'}]}};
   throw Error(name);
  }});
  const result=await exported.GET();assert.equal(result.status,role==='admin'?200:403);assert.equal(reads,role==='admin'?1:0);
 }
});

test('exportação centralizada preserva rota e histórico de pagamentos sem somar o histórico novamente',()=>{
 const manifests=[{id:'A',route:'BELÉM / ALMEIRIM',rows:[{id:'01',client:'CLIENTE',city:'ALMEIRIM',volumes:3,freight:1000,payments:[{amount:200,date:'2026-11-18',operator:'OPERADOR',method:'Dinheiro',note:'Sem dinheiro'},{amount:800,date:'2026-11-19',operator:'ADMIN',method:'Pix',note:'Quitação do saldo',freightId:'n1',noteNumber:'NF10'}]}]}];
 const data=collectionReport(manifests,{role:'admin'},{manifestId:'A',city:'',category:'',query:''});const csv=collectionReportCsv(data.rows);
 assert.equal(data.rows.length,1);assert.equal(data.rows[0].received,1000);assert.ok(csv.includes('BELÉM / ALMEIRIM'));assert.ok(csv.includes('2026-11-18 | Conhecimento | 2.00 | OPERADOR | Dinheiro | Sem dinheiro'));assert.ok(csv.includes('2026-11-19 | Nota NF10 | 8.00 | ADMIN | Pix | Quitação do saldo'));
});

test('desconto mantém recebimento real, quita saldo e exporta trilha sem duplicar valores',()=>{
 const {collectionReport,collectionReportCsv}=require('../.test-build/collection-report.js');
 const {dashboardData}=require('../.test-build/dashboard.js');
 const row={id:'K',client:'Cliente',city:'ALMEIRIM',volumes:3,freight:10000,originalFreight:11000,payments:[{amount:10000}],freightAdjustments:[{id:'A',kind:'discount',before:11000,after:10000,reason:'Acordo',operator:'Entregador',createdAt:'2026-11-22T00:00:00Z'}]};
 const manifests=[{id:'M',rows:[row]}],user={role:'admin'};
 const report=collectionReport(manifests,user,{manifestId:'',city:'',category:'',query:''});
 assert.equal(report.rows[0].category,'Cobradas (Total)');assert.equal(report.rows[0].received,10000);assert.equal(report.rows[0].balance,0);
 const summary=dashboardData(manifests,user).summary;assert.equal(summary.received,10000);assert.equal(summary.paidPieces,3);
 const csv=collectionReportCsv(report.rows);assert.match(csv,/Frete original/);assert.match(csv,/110.00/);assert.match(csv,/Acordo/);
});

test('mercadorias preservam identificação e saldo do pai ao abrir pagamento por item',()=>{
 const {freightBalances,freightPaymentRow}=require('../.test-build/freights.js');
 const row={freight:29000,payments:[{amount:9000,freightId:'bev'}],freights:[{id:'bev',noteNumber:'N',tracking:'',sender:'',description:'Bebidas',category:'Bebidas',volumes:2,freight:9000,originalFreight:10000},{id:'food',noteNumber:'N',tracking:'',sender:'',description:'Estiva',category:'Estiva',volumes:3,freight:20000}]};
 const items=freightBalances(row);assert.equal(items[0].balance,0);assert.equal(items[1].balance,20000);assert.equal(items[0].description,'Bebidas');assert.equal(items[0].originalFreight,10000);
 const payment=freightPaymentRow(row,items[1]);assert.equal(payment.parentFreight,29000);assert.equal(payment.parentPaid,9000);assert.equal(payment.freight,20000);assert.equal(payment.itemDescription,'Estiva');
});
test('prestação separa dinheiro, outros meios, despesas, recursos próprios e indenizações',()=>{
 const {cashStatement,operationsCsv,validateOperation}=require('../.test-build/operations.js');
 const manifests=[{id:'M',rows:[{city:'A',payments:[{amount:9000,method:'Dinheiro'},{amount:20000,method:'Pix'}]},{city:'B',payments:[{amount:80000,method:'Dinheiro'}]}]}];
 const base={manifest_id:'M',city:'A',status:'paid',kind:'expense',data:{amount:1500,source:'Dinheiro das cobranças',description:'Carne'}};
 const entries=[base,{...base,kind:'damage',data:{amount:5000,approvedAmount:4000,source:'Dinheiro das cobranças'}},{...base,data:{amount:500,source:'Recurso próprio'}},{...base,kind:'damage',status:'approved',data:{amount:1000,approvedAmount:800}},{...base,kind:'damage',status:'rejected',data:{amount:90000}},{...base,city:'B',data:{amount:10000,source:'Dinheiro das cobranças'}}];
 const s=cashStatement(manifests,entries,'M','A');assert.equal(s.cashReceived,9000);assert.equal(s.bankReceived,20000);assert.equal(s.cashOut,5500);assert.equal(s.cashBalance,3500);assert.equal(s.expenses,2000);assert.equal(s.indemnities,4000);assert.equal(s.ownFunds,500);assert.equal(s.pendingIndemnities,800);
 assert.match(operationsCsv([{...base,data:{...base.data,description:'=FORMULA'}}]),/'=FORMULA/);
 const input={kind:'expense',manifestId:'M',city:'A',data:{amount:1500,description:'Compra',date:'2026-11-22',category:'Alimentação',source:'Dinheiro das cobranças',attachments:[]}};
 assert.doesNotThrow(()=>validateOperation(input));assert.throws(()=>validateOperation({...input,data:{...input.data,amount:1.5}}));assert.throws(()=>validateOperation({...input,data:{...input.data,source:'Qualquer'}}));
});

test('API de operações recusa aprovações de entregadores antes da chamada ao banco',async()=>{
 const fs=require('node:fs'),vm=require('node:vm'),ts=require('typescript');
 const source=ts.transpileModule(fs.readFileSync('app/api/operations/route.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
 for(const role of [null,'blocked','entregador','admin']){
  let writes=0;const exported={};
  vm.runInNewContext(source,{exports:exported,require:name=>{
   if(name.endsWith('/access'))return {getAccess:async()=>role?{role}:null};
   if(name.endsWith('/private-json'))return {privateJson:(body,options)=>({body,status:options?.status||200})};
   if(name.endsWith('/supabase-server'))return {createSupabase:async()=>({rpc:async()=>{writes++;return {data:{ok:true}}}})};
   if(name.endsWith('/operations'))return require('../.test-build/operations.js');
   throw Error(name);
  }});
  const result=await exported.POST({json:async()=>({action:'approve',input:{id:'test'}})});
  assert.equal(result.status,role==='admin'?200:403);assert.equal(writes,role==='admin'?1:0);
 }
});
