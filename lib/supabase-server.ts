import {createServerClient} from '@supabase/ssr';
import {cookies} from 'next/headers';
export async function createSupabase(){
 const bindings=process.env;
 const url=bindings.SUPABASE_URL,key=bindings.SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key)throw Error('O acesso Supabase ainda não está configurado.');
 const store=await cookies();
 return createServerClient(url,key,{
  cookieOptions:{name:'carga-supabase-auth',httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'lax',path:'/'},
  global:{fetch:(input,init)=>fetch(input,{...init,cache:'no-store'})},
  cookies:{getAll(){return store.getAll();},setAll(values){values.forEach(({name,value,options})=>store.set(name,value,{...options,httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'lax',path:'/'}));}}
 });
}
