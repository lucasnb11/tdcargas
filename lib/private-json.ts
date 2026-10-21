export function privateJson(value:unknown,init:ResponseInit={}){
 const headers=new Headers(init.headers);headers.set('Cache-Control','private, no-store');headers.set('Pragma','no-cache');headers.set('Expires','0');return Response.json(value,{...init,headers});
}
