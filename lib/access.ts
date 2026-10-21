import {createSupabase} from './supabase-server';
export async function getAccess(){
 const client=await createSupabase();
 const {data:{user},error}=await client.auth.getUser();
 if(error||!user?.email)return null;
 const {data:profile,error:profileError}=await client.from('perfis_manifestos').select('id,email,nome,perfil,ativo,proprietario,cidade').eq('id',user.id).maybeSingle();
 if(profileError)throw Error('Não foi possível verificar seu perfil de acesso.');
 const role=profile?.ativo&&['admin','entregador'].includes(profile.perfil)?profile.perfil:'blocked';
 return {userId:user.id,email:user.email.toLowerCase(),displayName:profile?.nome||user.email,role,owner:!!profile?.proprietario,city:profile?.cidade||null};
}
