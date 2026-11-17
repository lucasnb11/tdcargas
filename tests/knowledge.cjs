const {test}=require('node:test');
const assert=require('node:assert/strict');
const {validateKnowledge}=require('../.test-build/knowledge.js');
const {clientSummary,tripSummary}=require('../.test-build/control.js');
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
