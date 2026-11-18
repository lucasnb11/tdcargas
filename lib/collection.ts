import {paid} from './control';
export const COLLECTION_DAYS=7;
export function collectionState(row:any,now=Date.now()){
 const deadline=row.collectionDueAt?Date.parse(row.collectionDueAt):NaN;
 const settled=paid(row)>=row.freight;
 const blocked=!settled&&Number.isFinite(deadline)&&now>=deadline;
 return {received:!!row.receivedAt,deadline,settled,blocked};
}
export function collectionDate(value:string){return new Date(value).toLocaleString('pt-BR',{timeZone:'America/Belem',dateStyle:'short',timeStyle:'short'});}
export function assertCollectionOpen(row:any,now=Date.now()){
 if(collectionState(row,now).blocked)throw Error('Conhecimento bloqueado: prazo de cobrança vencido. Solicite a liberação do administrador.');
}
