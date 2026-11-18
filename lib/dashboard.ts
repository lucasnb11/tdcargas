import {canAccessCity,normalizeCity} from './cities';
import {paid,tripRows} from './control';
export type DashboardUser={role:string;city?:string|null};
export function dashboardCityKey(city:unknown){return normalizeCity(city)||'__SEM_CIDADE__';}
export function summarizeDashboard(rows:any[]){
 let freight=0,received=0,balance=0,paidCount=0,pendingCount=0,partialCount=0;
 for(const row of rows){
  const amount=paid(row),remaining=Math.max(0,row.freight-amount);
  freight+=row.freight;received+=amount;balance+=remaining;
  if(remaining===0)paidCount++;else{pendingCount++;if(amount>0)partialCount++;}
 }
 return {count:rows.length,manifestCount:new Set(rows.map(row=>row.manifestId)).size,freight,received,balance,paidCount,pendingCount,partialCount,unpaidCount:pendingCount-partialCount,receivedPercent:freight>0?Math.min(100,Math.max(0,received/freight*100)):0};
}
export function dashboardData(manifests:any[],user:DashboardUser,cityFilter=''){
 // O servidor já restringe os dados pela cidade. Este filtro reforça o escopo na exibição.
 const scopeRows=manifests.flatMap(tripRows).filter(row=>canAccessCity(user,row.city));
 const selected=user.role==='admin'?cityFilter:normalizeCity(user.city);
 const rows=selected?scopeRows.filter(row=>dashboardCityKey(row.city)===dashboardCityKey(selected)):scopeRows;
 const groups=new Map<string,{key:string;name:string;rows:any[]}>();
 for(const row of scopeRows){const key=dashboardCityKey(row.city);const group:{key:string;name:string;rows:any[]}=groups.get(key)||{key,name:String(row.city||'Cidade não informada'),rows:[]};group.rows.push(row);groups.set(key,group);}
 const cities=[...groups.values()].map(group=>({key:group.key,name:group.name,...summarizeDashboard(group.rows)})).sort((a,b)=>a.name.localeCompare(b.name,'pt-BR'));
 return {rows,summary:summarizeDashboard(rows),cities};
}
