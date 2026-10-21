import {createSupabase} from './supabase-server';
export async function loadManifests(){const client=await createSupabase();const {data,error}=await client.rpc('td_listar_manifestos');if(error)throw Error('Não foi possível carregar os manifestos. Verifique se o SQL de instalação foi executado.');return (data||[]) as any[];}
export async function getPix(){const client=await createSupabase();const {data,error}=await client.rpc('td_pix_config');if(error)throw error;return data;}
