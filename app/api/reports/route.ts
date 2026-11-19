import {getAccess} from '../../../lib/access';
import {privateJson} from '../../../lib/private-json';
import {loadManifests} from '../../../lib/repository';
export const dynamic='force-dynamic';
export async function GET(){
 try{
  const user=await getAccess();
  if(user?.role!=='admin')return privateJson({error:'Relatório disponível somente para administradores.'},{status:403});
  return privateJson(await loadManifests());
 }catch(e:any){return privateJson({error:e.message||'Não foi possível gerar o relatório.'},{status:500});}
}
