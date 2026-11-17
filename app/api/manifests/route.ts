import {validateFreights} from '../../../lib/freights';
import {validateVessel} from '../../../lib/vessels';
import {partialPaymentNote} from '../../../lib/payment';
import {getAccess} from '../../../lib/access';
import {privateJson} from '../../../lib/private-json';
import {createSupabase} from '../../../lib/supabase-server';
import {validateKnowledge} from '../../../lib/knowledge';
import {getCityCatalog} from '../../../lib/city-catalog';
import {loadManifests} from '../../../lib/repository';
export const dynamic='force-dynamic';
export async function GET(){try{const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});return privateJson(await loadManifests());}catch(e:any){return privateJson({error:e.message||'Erro ao carregar manifestos.'},{status:500});}}
export async function POST(req:Request){try{const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});const b:any=await req.json(),client=await createSupabase();
if(b.action==='import'){if(user.role!=='admin')return privateJson({error:'Apenas administradores podem importar.'},{status:403});const m=b.manifest;if(!/^\d{6}\/\d{4}$/.test(m?.id)||!Array.isArray(m.rows)||!m.rows.length||m.rows.length>5000||m.rows.some((r:any)=>!r.id||!r.client||!Number.isSafeInteger(r.freight)||r.freight<0))throw Error('Manifesto inválido.');m.vessel=validateVessel(m.vessel);m.rows.forEach((r:any)=>{r.payments=[];r.conferences=[]});const {error}=await client.from('td_manifestos').insert({id:m.id,data:m});if(error)throw Error(error.code==='23505'?'Esta viagem já foi importada.':error.message);return privateJson({ok:true});}
if(b.action==='add_knowledge'){
 if(user.role!=='admin')return privateJson({error:'Apenas administradores podem cadastrar conhecimentos.'},{status:403});
 const cities=await getCityCatalog();
 const row=validateKnowledge(b.manifestId,b.row,cities.map((c:any)=>c.key));
 const {error}=await client.rpc('td_adicionar_conhecimento',{p_manifest_id:b.manifestId,p_row:row});
 if(error)throw Error(error.message);
 return privateJson({ok:true});
}
if(b.action==='save_freights'){
 if(user.role!=='admin')return privateJson({error:'Apenas administradores podem vincular notas/fretes.'},{status:403});
 if(!Array.isArray(b.documents)||!b.documents.length||b.documents.length>1000)throw Error('Importação de notas/fretes inválida.');
 const manifests=await loadManifests();
 const documents=b.documents.map((d:any)=>{const row=manifests.find(m=>m.id===d.manifestId)?.rows.find((r:any)=>r.id===d.rowId);if(!row)throw Error('Conhecimento não encontrado no manifesto.');return {manifestId:d.manifestId,rowId:d.rowId,items:validateFreights(d.items,row.freight)};});
 const {data,error}=await client.rpc('td_salvar_fretes',{p_documents:documents});if(error)throw Error(error.message);return privateJson(data);
}
if(b.action==='pay'){
 if(b.type==='parcial'&&!Number.isSafeInteger(b.amount))throw Error('Valor inválido.');
 if(b.freightId!==undefined&&(typeof b.freightId!=='string'||!b.freightId||b.freightId.length>120))throw Error('Nota/frete inválido.');
 const {error}=await client.rpc('td_registrar_pagamento',{p_manifest_id:b.manifestId,p_row_id:b.rowId,p_freight_id:b.freightId||null,p_type:b.type||null,p_amount:b.amount??null,p_note:b.type==='parcial'?partialPaymentNote(b.reason,b.installments,b.note):null,p_date:b.date||null,p_method:b.method||null});if(error)throw Error(error.message);return privateJson({ok:true});
}
if(b.action!=='conference')throw Error('Operação inválida.');const {error}=await client.rpc('td_operar_manifesto',{p_manifest_id:b.manifestId,p_row_id:b.rowId,p_action:'conference',p_type:null,p_amount:null,p_note:null,p_date:null,p_method:null});if(error)throw Error(error.message);return privateJson({ok:true});}catch(e:any){return privateJson({error:e.message||'Não foi possível salvar.'},{status:400});}}
