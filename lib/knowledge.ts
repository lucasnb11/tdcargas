import {normalizeCity} from './cities';

export function manifestImportSummary(existing:any,incoming:any){
 const known=new Set<string>((existing?.rows||[]).map((row:any)=>row.id));
 const received=new Set<string>((incoming?.rows||[]).map((row:any)=>row.id));
 return {added:[...received].filter(id=>!known.has(id)).length,existing:[...received].filter(id=>known.has(id)).length,absent:[...known].filter(id=>!received.has(id)).length};
}

export function validateKnowledge(manifestId: unknown, input: any, cities: string[]) {
 if(typeof manifestId!=='string'||!manifestId.trim())throw Error('Selecione o manifesto do conhecimento.');
 const row={id:typeof input?.id==='string'?input.id.trim():'',client:typeof input?.client==='string'?input.client.trim():'',city:typeof input?.city==='string'?normalizeCity(input.city):'',kind:input?.kind,volumes:input?.volumes,freight:input?.freight};
 if(!row.id||row.id.length>60||!row.client||row.client.length>200)throw Error('Informe o número do conhecimento e o cliente pagador.');
 if(!row.city||!cities.map(normalizeCity).includes(row.city))throw Error('Selecione uma cidade cadastrada.');
 if(!['FOB','CIF','VEÍCULO'].includes(row.kind))throw Error('Tipo de carga inválido.');
 if(!Number.isSafeInteger(row.volumes)||row.volumes<1||row.volumes>1000000)throw Error('Informe uma quantidade válida de volumes.');
 if(!Number.isSafeInteger(row.freight)||row.freight<1||row.freight>100000000000)throw Error('Informe um valor de frete válido.');
 return row;
}
