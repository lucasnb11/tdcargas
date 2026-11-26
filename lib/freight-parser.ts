import {validateFreights,FreightItem} from './freights';
const money=(value:string)=>Math.round(Number(value.replace(/\./g,'').replace(',','.'))*100);
// As colunas de um PDF podem ter linhas de base ligeiramente diferentes,
// especialmente quando o número do conhecimento usa uma fonte maior.
export function freightPageText(items:any[]):string{
 const lines:{y:number;items:any[]}[]=[];
 for(const item of items.filter(i=>typeof i.str==='string'&&i.str.trim()).sort((a,b)=>b.transform[5]-a.transform[5])){
  const y=item.transform[5];
  const line=lines.find(l=>Math.abs(l.y-y)<=4);
  if(line)line.items.push(item);else lines.push({y,items:[item]});
 }
 return lines.map(l=>l.items.sort((a,b)=>a.transform[4]-b.transform[4]).map(i=>i.str.trim()).join(' ')).join('\n');
}
export function parseFreightDocuments(text:string,manifests:any[],targetManifestId?:string){
 // Espaços introduzidos pelo OCR entre o valor e a vírgula decimal.
 text=text.replace(/(?<=\d)[ \t]+,(?=\d{2}\b)/g,',').replace(/(?<=\d),[ \t]+(?=\d{2}\b)/g,',');
 const records:any[]=[],errors:string[]=[];let preserved=0;
 const starts=[...text.matchAll(/(?:^|\n)Conhecimento[^\n]*\n\s*(\d{6}\/\d{4})/gi)];
 if(!starts.length)throw Error('Não foi possível reconhecer os conhecimentos no PDF.');
 const grouped=new Map<string,any>();
 starts.forEach((match,index)=>{
  const block=text.slice(match.index,starts[index+1]?.index??text.length),rowId=match[1];
  const manifestId=block.match(/Viagem\s*\n\s*(\d{6}\/\d{4})/i)?.[1];
  if(!manifestId){errors.push(`Conhecimento ${rowId}: viagem não identificada.`);return;}
  if(targetManifestId&&manifestId!==targetManifestId){errors.push(`Conhecimento ${rowId}: pertence à viagem ${manifestId}, diferente do manifesto ${targetManifestId} desta importação.`);return;}
  const expectedCount=block.match(/QTD\s+de\s+Fretes\s*:\s*(\d+)/i)?.[1];
  const totalText=block.match(/QTD\s+de\s+Fretes[^\n]*\bFrete\s*:\s*([\d.]+,\d{2})/i)?.[1];
  const key=JSON.stringify([manifestId,rowId]);
  const document=grouped.get(key)||{manifestId,rowId,items:[],expectedCount:undefined,total:undefined};
  if(expectedCount)document.expectedCount=Number(expectedCount);
  if(totalText)document.total=money(totalText);
  for(const raw of block.split('\n')){
   const line=raw.trim();
   // O OCR às vezes omite a vírgula do valor da nota, que não é usado na cobrança.
   const item=line.match(/^(\d{4,})\.?\s+(.+?)\s+([\w./-]+)\s+([\d.]+,\d{2})\s+(\d+)\s+([\d.,]+)\s+(\p{L}.*?)\s+([\d.]+,\d{2})\s*$/u)
    ||line.match(/^(\d{4,})\.?\s+(.+?)\s+([\w./-]+)\s+([\d.]+)\s+(\d+)\s+([\d.,]+)\s+(\p{L}.*?)\s+([\d.]+,\d{2})\s*$/u);
   if(!item)continue;
   const category=item[7].trim().replace(/\s+/g,' ');
   if(!/\p{L}/u.test(category)||category.length>40){document.conflict=true;continue;}
   const value:FreightItem={id:`${item[1]}:${item[3]}`,tracking:item[1],sender:item[2],noteNumber:item[3],volumes:Number(item[5]),freight:money(item[8]),category,description:category};
   const existing=document.items.find((i:FreightItem)=>i.id===value.id);
   if(existing&&JSON.stringify(existing)!==JSON.stringify(value))document.conflict=true;
   if(!existing)document.items.push(value);
  }
  grouped.set(key,document);
 });
 for(const document of grouped.values()){
  try{
   const manifest=manifests.find(m=>m.id===document.manifestId),row=manifest?.rows.find((r:any)=>r.id===document.rowId);
   if(!row)throw Error('importe primeiro o manifesto que contém esse conhecimento');
   if(row.freights?.length||row.itemsManaged||row.freightAdjustments?.length){preserved++;continue;}
   if(document.conflict)throw Error('há dados divergentes para a mesma nota no PDF');
   if(!document.expectedCount||document.items.length!==document.expectedCount)throw Error('a quantidade de fretes extraída não confere com o documento');
   if(document.total!==row.freight)throw Error('o frete do PDF diverge do manifesto');
   const items=validateFreights(document.items,row.freight);
   if(Number.isSafeInteger(row.volumes)&&items.reduce((sum,item)=>sum+item.volumes,0)!==row.volumes)throw Error('a soma dos volumes não confere com o manifesto');
   records.push({manifestId:document.manifestId,rowId:document.rowId,client:row.client,items});
  }catch(e:any){errors.push(`Conhecimento ${document.rowId} / viagem ${document.manifestId}: ${e.message}.`);}
 }
 return {records,errors,preserved};
}
