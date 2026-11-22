import {csvCell} from './collection-report';
export const EXPENSE_CATEGORIES=['Alimentação','Combustível','Manutenção','Outros'] as const;
export const FUND_SOURCES=['Dinheiro das cobranças','Conta da empresa','Recurso próprio'] as const;
export const OP_STATUS:Record<string,string>={pending:'Aguardando análise',approved:'Aprovada',rejected:'Rejeitada',paid:'Pago'};
export function validateOperation(input:any){
 if(!input||!['expense','damage'].includes(input.kind)||typeof input.manifestId!=='string'||!input.manifestId||typeof input.city!=='string'||!input.city)throw Error('Selecione a viagem e a cidade.');
 const d=input.data;
 if(!d||typeof d.description!=='string'||!d.description.trim()||d.description.length>2000||!Number.isSafeInteger(d.amount)||d.amount<1||d.amount>100000000000)throw Error('Informe a descrição e um valor válido.');
 if(typeof d.date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(d.date)||Number.isNaN(Date.parse(d.date+'T12:00:00Z')))throw Error('Data inválida.');
 if(input.kind==='expense'&&(!EXPENSE_CATEGORIES.includes(d.category)||!FUND_SOURCES.includes(d.source)))throw Error('Selecione a categoria e a origem do dinheiro.');
 if(input.kind==='damage'&&(!input.rowId||!Number.isSafeInteger(d.quantity)||d.quantity<1))throw Error('Identifique o conhecimento e a quantidade avariada.');
 if(!Array.isArray(d.attachments)||d.attachments.length>3||d.attachments.some((p:any)=>typeof p!=='string'||p.length>200))throw Error('Anexe no máximo três imagens.');
 return input;
}
export function cashStatement(manifests:any[],entries:any[],manifestId='',city=''){
 const included=(mid:string,c:string)=>(!manifestId||mid===manifestId)&&(!city||c===city);
 let cashReceived=0,bankReceived=0;
 for(const m of manifests)for(const r of m.rows||[])if(included(m.id,r.city))for(const p of r.payments||[]){if(p.method==='Dinheiro')cashReceived+=p.amount;else if(p.method)bankReceived+=p.amount;}
 const rows=entries.filter(e=>included(e.manifest_id,e.city));
 const paid=rows.filter(e=>e.status==='paid');
 const amount=(e:any)=>e.kind==='expense'?e.data.amount:e.data.approvedAmount;
 const cashOut=paid.filter(e=>e.data.source==='Dinheiro das cobranças').reduce((s,e)=>s+amount(e),0);
 return {rows,cashReceived,bankReceived,cashOut,cashBalance:cashReceived-cashOut,expenses:paid.filter(e=>e.kind==='expense').reduce((s,e)=>s+amount(e),0),indemnities:paid.filter(e=>e.kind==='damage').reduce((s,e)=>s+amount(e),0),ownFunds:paid.filter(e=>e.data.source==='Recurso próprio').reduce((s,e)=>s+amount(e),0),pendingIndemnities:rows.filter(e=>e.kind==='damage'&&e.status==='approved').reduce((s,e)=>s+e.data.approvedAmount,0)};
}
export function operationsCsv(entries:any[]){
 const rows=[['Viagem','Cidade','Tipo','Conhecimento','Mercadoria','Situação','Descrição','Data','Valor solicitado / despesa','Indenização aprovada','Origem do dinheiro','Data do pagamento','Responsável','Histórico'],...entries.map(e=>[e.manifest_id,e.city,e.kind==='expense'?'Despesa':'Avaria',e.row_id||'',e.data.itemDescription||e.freight_id||'',OP_STATUS[e.status],e.data.description,e.data.date,(e.data.amount/100).toFixed(2),e.data.approvedAmount===undefined?'':(e.data.approvedAmount/100).toFixed(2),e.data.source||'',e.data.paidDate||'',e.data.operator||'',(e.events||[]).map((a:any)=>[a.action,a.operator,a.createdAt,a.reason||''].join(' | ')).join(' / ')])];
 return '\ufeff'+rows.map(r=>r.map(csvCell).join(';')).join('\r\n');
}
