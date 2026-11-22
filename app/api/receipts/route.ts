import {randomUUID} from 'node:crypto';
import {getAccess} from '../../../lib/access';
import {createSupabase} from '../../../lib/supabase-server';
import {privateJson} from '../../../lib/private-json';
export const dynamic='force-dynamic';
export async function POST(req:Request){try{
 const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});
 const form=await req.formData(),file=form.get('file');if(!(file instanceof File)||file.size<1||file.size>3*1024*1024)throw Error('Selecione uma imagem de até 3 MB.');
 const bytes=Buffer.from(await file.arrayBuffer());
 const type=bytes[0]===0xff&&bytes[1]===0xd8?'image/jpeg':bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))?'image/png':bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP'?'image/webp':null;
 if(!type)throw Error('Use uma foto JPG, PNG ou WebP.');
 const client=await createSupabase(),path=`${user.userId}/${randomUUID()}.${type==='image/jpeg'?'jpg':type==='image/png'?'png':'webp'}`;
 const {error}=await client.storage.from('td-comprovantes').upload(path,bytes,{contentType:type,upsert:false});if(error)throw error;return privateJson({path});
}catch(e:any){return privateJson({error:e.message||'Erro ao enviar comprovante.'},{status:400});}}
export async function GET(req:Request){try{
 const user=await getAccess();if(!user||!['admin','entregador'].includes(user.role))return privateJson({error:'Acesso não autorizado.'},{status:403});
 const url=new URL(req.url),id=url.searchParams.get('id'),path=url.searchParams.get('path');if(!id||!path)throw Error('Anexo não informado.');
 const client=await createSupabase();const {data:entry,error}=await client.from('td_operacoes').select('data').eq('id',id).maybeSingle();if(error||!entry||![...(entry.data.attachments||[]),...(entry.data.paymentAttachments||[])].includes(path))return privateJson({error:'Anexo fora do seu acesso.'},{status:403});
 const {data,error:signError}=await client.storage.from('td-comprovantes').createSignedUrl(path,300);if(signError)throw signError;return privateJson({url:data.signedUrl});
}catch(e:any){return privateJson({error:e.message||'Erro ao consultar comprovante.'},{status:400});}}
