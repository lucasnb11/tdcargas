export type FreightItem={id:string;noteNumber:string;tracking:string;sender:string;volumes:number;freight:number;description?:string;category?:string;originalFreight?:number};
export const classKey=(value:unknown)=>String(value??'').trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
export function knowledgeClasses(row:any):string[]{return [...new Set<string>((row.freights||[]).map((item:any)=>classKey(item.category)).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'pt-BR'));}
export function availableClasses(rows:any[]):string[]{return [...new Set(rows.flatMap(knowledgeClasses))].sort((a,b)=>a.localeCompare(b,'pt-BR'));}
export function matchesClass(row:any,selected?:string){return !selected||knowledgeClasses(row).includes(classKey(selected));}
export function validateFreights(items:any,expected:number):FreightItem[]{
 if(!Array.isArray(items)||!items.length||items.length>2000)throw Error('Informe entre 1 e 2000 notas/fretes.');
 const result=items.map((item:any)=>{
  if(!item||typeof item.id!=='string'||!item.id.trim()||item.id.length>120||typeof item.noteNumber!=='string'||!item.noteNumber.trim()||item.noteNumber.length>60||typeof item.sender!=='string'||item.sender.length>200||typeof item.tracking!=='string'||item.tracking.length>80||!Number.isSafeInteger(item.volumes)||item.volumes<0||item.volumes>1000000||!Number.isSafeInteger(item.freight)||item.freight<0||item.freight>100000000000)throw Error('Nota/frete inválido: confira número, volumes e valor.');
  return {...(typeof item.description==='string'?{description:item.description.slice(0,200)}:{}),...(typeof item.category==='string'?{category:item.category.slice(0,40)}:{}),...(Number.isSafeInteger(item.originalFreight)?{originalFreight:item.originalFreight}:{}),id:item.id.trim(),noteNumber:item.noteNumber.trim(),tracking:item.tracking.trim(),sender:item.sender.trim(),volumes:item.volumes,freight:item.freight};
 });
 if(new Set(result.map(i=>i.id)).size!==result.length)throw Error('Existem notas/fretes duplicados.');
 if(result.reduce((sum,i)=>sum+i.freight,0)!==expected)throw Error('A soma dos fretes deve ser igual ao frete total do conhecimento.');
 return result;
}
// Pagamentos gerais, inclusive antigos, são distribuídos na ordem das notas.
// Pagamentos individuais permanecem vinculados à nota escolhida.
export function freightBalances(row:any){
 if(!row.freights?.length)return [];
 const items=validateFreights(row.freights,row.freight).map(item=>({...item,received:0,balance:item.freight}));
 for(const payment of row.payments||[]){
  if(!Number.isSafeInteger(payment.amount)||payment.amount<=0)throw Error('Valor de pagamento inválido.');
  let remaining=payment.amount;
  const targets=payment.freightId?items.filter(item=>item.id===payment.freightId):items;
  if(payment.freightId&&targets.length!==1)throw Error('Pagamento vinculado a uma nota/frete não encontrado.');
  for(const item of targets){const value=Math.min(remaining,item.balance);item.received+=value;item.balance-=value;remaining-=value;if(!remaining)break;}
  if(remaining)throw Error('Os pagamentos excedem o saldo das notas/fretes.');
 }
 return items;
}
export function freightPaymentRow(row:any,item:ReturnType<typeof freightBalances>[number]){
 return {...row,parentFreight:row.freight,parentPaid:row.payments.reduce((s:number,p:any)=>s+p.amount,0),itemDescription:item.description||item.noteNumber,freight:item.freight,payments:item.received?[{amount:item.received}]:[],freightId:item.id,noteNumber:item.noteNumber,tracking:item.tracking};
}
