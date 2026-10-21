import { createClient } from "npm:@supabase/supabase-js@2.117.3";
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{"Content-Type":"application/json","Cache-Control":"private, no-store"}});
Deno.serve(async(req)=>{
 if(req.method!=="POST")return json({error:"Método não permitido."},405);
 try{
 const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");if(!token)return json({error:"Acesso não autorizado."},401);
 const url=Deno.env.get("SUPABASE_URL"),secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),anon=Deno.env.get("SUPABASE_ANON_KEY");if(!url||!secret||!anon)return json({error:"Configuração indisponível."},500);
 const admin=createClient(url,secret,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data:{user},error}=await admin.auth.getUser(token);if(error||!user)return json({error:"Sessão inválida."},401);
 const {data:profile,error:lookup}=await admin.from("perfis_manifestos").select("perfil,ativo").eq("id",user.id).maybeSingle();if(lookup||!profile?.ativo||profile.perfil!=="admin")return json({error:"Somente administradores podem criar contas."},403);
 const body=await req.json();const email=String(body.email||"").trim().toLowerCase(),name=String(body.name||"").trim(),city=String(body.city||"").normalize("NFD").replace(/[\u0300-\u036f]/g,"").trim().replace(/\s+/g," ").toUpperCase();
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||name.length<1||name.length>120||city.length<2||city.length>80||typeof body.password!=="string"||body.password.length<12||body.password.length>128)return json({error:"Informe nome, e-mail, cidade e senha com pelo menos 12 caracteres."},400);
 const {error:createError}=await admin.auth.admin.createUser({email,password:body.password,email_confirm:true});
 if(createError)return json({error:"Não foi possível criar a conta. Verifique o e-mail e a senha. Se a conta já existir, use Vincular conta existente."},400);
 const caller=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}},auth:{autoRefreshToken:false,persistSession:false}});
 const {error:roleError}=await caller.rpc("manifestos_salvar_perfil",{p_email:email,p_nome:name,p_perfil:"entregador",p_ativo:true,p_cidade:city});
 if(roleError)return json({error:"A conta foi criada, mas o vínculo com a cidade não foi concluído. Use Vincular conta existente para finalizar."},409);
 return json({ok:true});
 }catch{return json({error:"Não foi possível concluir o cadastro."},500);}
});
