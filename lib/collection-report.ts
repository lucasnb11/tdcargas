import {canAccessCity,normalizeCity} from './cities';
import {paid,tripRows} from './control';
import {classKey,freightBalances,knowledgeClasses,matchesClass} from './freights';
import {collectionState} from './collection';
export const REPORT_CATEGORIES=['Cobradas (Total)','Cobradas (Parcial)','Pendentes de cobrança'] as const;
export type ReportCategory=typeof REPORT_CATEGORIES[number];
export type ReportFilters={manifestId:string;city:string;category:string;query:string;freightClass?:string};
export function reportCategory(row:any):ReportCategory{
 const received=paid(row);
 return received>=row.freight?REPORT_CATEGORIES[0]:received>0?REPORT_CATEGORIES[1]:REPORT_CATEGORIES[2];
}
export function collectionReport(manifests:any[],user:{role:string;city?:string|null},filters:ReportFilters,now=Date.now()){
 const query=filters.query.trim().toLocaleLowerCase('pt-BR');
 const rows=manifests.flatMap(tripRows).filter(row=>canAccessCity(user,row.city)&&(!filters.manifestId||row.manifestId===filters.manifestId)&&(!filters.city||normalizeCity(row.city)===normalizeCity(filters.city))&&matchesClass(row,filters.freightClass)&&(!query||`${row.id} ${row.client} ${row.manifestId}`.toLocaleLowerCase('pt-BR').includes(query)))
 .map(row=>({...row,category:reportCategory(row),received:paid(row),balance:Math.max(0,row.freight-paid(row)),blocked:collectionState(row,now).blocked}));
 const groups=REPORT_CATEGORIES.map(category=>{
  const items=rows.filter(row=>row.category===category);
  return {category,rows:items,count:items.length,pieces:items.reduce((sum,row)=>sum+(Number.isSafeInteger(Number(row.volumes))?Math.max(0,Number(row.volumes)):0),0),freight:items.reduce((sum,row)=>sum+row.freight,0),received:items.reduce((sum,row)=>sum+row.received,0),balance:items.reduce((sum,row)=>sum+row.balance,0)};
 }).filter(group=>!filters.category||group.category===filters.category);
 const included=groups.flatMap(group=>group.rows);
 const classification=new Map<string,{name:string;count:number;pieces:number;freight:number;received:number;balance:number}>();
 for(const row of included){
  const seen=new Set<string>();
  let items:ReturnType<typeof freightBalances>=[];
  try{items=freightBalances(row);}catch{continue;}
  for(const item of items){
   const name=classKey(item.category)||'SEM CLASSE';
   if(filters.freightClass&&name!==classKey(filters.freightClass))continue;
   const entry=classification.get(name)||{name,count:0,pieces:0,freight:0,received:0,balance:0};
   if(!seen.has(name)){entry.count++;seen.add(name);}
   entry.pieces+=item.volumes;entry.freight+=item.freight;entry.received+=item.received;entry.balance+=item.balance;
   classification.set(name,entry);
  }
 }
 return {groups,rows:included,classes:[...classification.values()].sort((a,b)=>a.name.localeCompare(b.name,'pt-BR'))};
}
// Protege textos de clientes contra execução de fórmulas ao abrir no Excel.
export function csvCell(value:unknown){let text=String(value??'');if(/^[\s]*[=+@-]/.test(text)||/^[\t\r\n]/.test(text))text="'"+text;return '"'+text.replace(/"/g,'""')+'"';}
export function collectionReportCsv(rows:ReturnType<typeof collectionReport>['rows']){
 const lines=[['Situação','Manifesto / viagem','Data da saída','Embarcação','Conhecimento','Destinatário','Cidade','Peças / volumes','Frete (R$)','Recebido (R$)','Saldo (R$)','Pagamento bloqueado','Recebimento confirmado em','Prazo de cobrança','Rota','Histórico de pagamentos','Frete original (R$)','Histórico de ajustes','Classes de frete'],...rows.map(row=>[row.category,row.manifestId,row.tripDate,row.tripVessel,row.id,row.client,row.city,row.volumes,(row.freight/100).toFixed(2),(row.received/100).toFixed(2),(row.balance/100).toFixed(2),row.blocked?'Sim':'Não',row.receivedAt||'',row.collectionDueAt||'',row.tripRoute||'',row.payments.map((p:any)=>[p.date||'',p.freightId?p.itemDescription?`Mercadoria ${p.itemDescription}`:`Nota ${p.noteNumber||p.freightId}`:'Conhecimento',(p.amount/100).toFixed(2),p.operator||'',p.method||'',p.note||''].join(' | ')).join(' / '),((row.originalFreight??row.freight)/100).toFixed(2),(row.freightAdjustments||[]).map((a:any)=>[a.createdAt,a.kind,a.itemDescription||a.freightId||'Conhecimento',(a.before/100).toFixed(2),(a.after/100).toFixed(2),a.operator,a.reason].join(' | ')).join(' / '),knowledgeClasses(row).join(' / ')])];
 return '\ufeff'+lines.map(line=>line.map(csvCell).join(';')).join('\r\n');
}
