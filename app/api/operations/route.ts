import {getAccess} from '../../../lib/access';
import {createSupabase} from '../../../lib/supabase-server';
import {privateJson} from '../../../lib/private-json';
import {validateOperation} from '../../../lib/operations';
export const dynamic='force-dynamic';
export async function GET(){try{
 const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});
 const client=await createSupabase();let entries:any[]=[];
 for(let start=0;;start+=1000){const {data,error}=await client.from('td_operacoes').select('*').order('created_at',{ascending:false}).order('id').range(start,start+999);if(error)throw error;entries.push(...data);if(data.length<1000)break;}
 return privateJson(entries);
}catch(e:any){return privateJson({error:e.message||'Erro ao carregar prestação de contas.'},{status:400});}}
export async function POST(req:Request){try{
 const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});
 const body=await req.json();if(['approve','reject'].includes(body.action)&&user.role!=='admin')return privateJson({error:'Somente administradores podem analisar indenizações.'},{status:403});
 if(body.action==='create')validateOperation(body.input);
 const client=await createSupabase();const {data,error}=await client.rpc('td_operacao',{p_action:body.action,p_input:body.input});if(error)throw error;return privateJson(data);
}catch(e:any){return privateJson({error:e.message||'Não foi possível salvar.'},{status:400});}}
