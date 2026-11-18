import {assertCollectionOpen} from '../../../lib/collection';
import {freightBalances} from '../../../lib/freights';
import {canAccessCity} from '../../../lib/cities';
import {privateJson} from '../../../lib/private-json';
import {getAccess} from '../../../lib/access';
import {createSupabase} from '../../../lib/supabase-server';
import {getPix,loadManifests} from '../../../lib/repository';
import {validatePixConfig,pixPayload} from '../../../lib/pix';
export const dynamic='force-dynamic';
export async function GET(){try{const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});const config=await getPix();return privateJson({configured:!!config,...(user.role==='admin'&&config?{config}:{})},{headers:{'Cache-Control':'no-store'}});}catch{return privateJson({error:'Não foi possível carregar as configurações Pix.'},{status:500});}}
export async function POST(req:Request){try{const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});const body:any=await req.json(),client=await createSupabase();
 if(body.action==='configure'){if(user.role!=='admin')return privateJson({error:'Somente administradores podem configurar o recebimento.'},{status:403});const config=validatePixConfig(body.config);const {error}=await client.from('td_config_pagamento').upsert({id:'pix',data:config});if(error)throw error;return privateJson({ok:true,config});}
 if(body.action!=='generate')throw Error('Operação inválida.');
 const setting=await getPix();if(!setting)throw Error('Configure a chave Pix em Recebimento Pix.');const record=(await loadManifests()).find(m=>m.id===body.manifestId);const row=record?.rows.find((r:any)=>r.id===body.rowId);if(!row||!canAccessCity(user,row.city))return privateJson({error:'Carga não encontrada ou fora da sua cidade.'},{status:403});assertCollectionOpen(row);let balance=row.freight-row.payments.reduce((sum:number,p:any)=>sum+p.amount,0);if(body.freightId){const item=freightBalances(row).find(i=>i.id===body.freightId);if(!item)throw Error('Nota/frete não encontrado.');balance=Math.min(balance,item.balance);}if(!['integral','parcial'].includes(body.type))throw Error('Tipo de pagamento inválido.');const amount=body.type==='integral'?balance:body.amount;if(!Number.isSafeInteger(amount)||amount<=0||amount>balance||body.type==='parcial'&&amount>=balance)throw Error('Informe um valor parcial válido, inferior ao saldo pendente.');const config=validatePixConfig(setting);const reference=crypto.randomUUID().replaceAll('-','').slice(0,25);return privateJson({payload:pixPayload(config,amount,reference),amount,reference,recipient:config.name,city:config.city,manifestId:body.manifestId,rowId:body.rowId,freightId:body.freightId||null},{headers:{'Cache-Control':'no-store'}});
 }catch(e:any){return privateJson({error:e.message||'Não foi possível gerar o Pix.'},{status:400});}}
