'use client';
import {collectionState,collectionDate} from '../../lib/collection';
type Props={row:any;isAdmin:boolean;busy:boolean;now:number;onReceive:(row:any)=>void;onUnlock:(row:any)=>void};
export default function CollectionControl({row,isAdmin,busy,now,onReceive,onUnlock}:Props){
 const state=collectionState(row,now);
 return <div className="collectioncontrol">
  {!state.received?<><span>Recebimento não confirmado</span><button className="secondary" disabled={busy} onClick={()=>onReceive(row)}>Confirmar recebimento</button></>:<><small>Recebido em {collectionDate(row.receivedAt)}</small>{state.settled?<b className="received">Cobrança quitada</b>:<><b className={state.blocked?'collectionblocked':''}>{state.blocked?'Bloqueado · prazo vencido':'Cobrar até'} {row.collectionDueAt&&collectionDate(row.collectionDueAt)}</b>{state.blocked&&(isAdmin?<button className="secondary" disabled={busy} onClick={()=>onUnlock(row)}>Liberar por mais 7 dias</button>:<small>Somente o administrador pode liberar o pagamento.</small>)}</>}</>}
 </div>;
}
