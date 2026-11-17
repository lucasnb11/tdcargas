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
