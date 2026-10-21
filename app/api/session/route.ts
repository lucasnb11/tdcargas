import {createSupabase} from '../../../lib/supabase-server';
import {privateJson} from '../../../lib/private-json';
export const dynamic='force-dynamic';
export async function POST(req:Request){try{
 const origin=req.headers.get('origin');if(origin&&origin!==new URL(req.url).origin)return privateJson({error:'Origem não autorizada.'},{status:403});
 const body:any=await req.json();const client=await createSupabase();
 if(body.action==='logout'){await client.auth.signOut({scope:'local'});return privateJson({ok:true});}
 if(body.action!=='login'||typeof body.email!=='string'||typeof body.password!=='string'||!body.email.trim()||!body.password||body.email.length>254||body.password.length>1024)return privateJson({error:'Informe e-mail e senha.'},{status:400});
 const {error}=await client.auth.signInWithPassword({email:body.email.trim().toLowerCase(),password:body.password});
 if(error)return privateJson({error:error.status===429?'Muitas tentativas. Aguarde antes de tentar novamente.':'E-mail ou senha inválidos. Use sua conta já cadastrada no Supabase.'},{status:error.status===429?429:401});
 return privateJson({ok:true});
 }catch{return privateJson({error:'Não foi possível acessar sua conta. Tente novamente.'},{status:500});}}
