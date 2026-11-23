'use client';
import {availableClasses} from '../../lib/freights';
import {ArrowUpRight,ChevronRight} from 'lucide-react';
const brl=(v:number)=>(v/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
type Props={groups:any[];showManifest:boolean;onManifest:(id:string)=>void;onOpen:(group:any)=>void};
export default function RecipientTable({groups,showManifest,onManifest,onOpen}:Props){
 return <div className="tablewrap"><table className="recipienttable"><thead><tr>{showManifest&&<th>MANIFESTO</th>}<th>DESTINATÁRIO</th><th>SALDO A RECEBER</th><th>STATUS</th></tr></thead><tbody>{groups.map(group=>{
  const groupStatus=group.balance<=0?'Pago':group.received>0?'Parcial':'Pendente';
  return <tr key={group.key}>
   {showManifest&&<td data-label="Manifesto"><button className="triplink" onClick={()=>onManifest(group.manifestId)}>{group.manifestId}<ArrowUpRight size={12}/></button><small>{group.tripDate}</small></td>}
   <td data-label="Destinatário" className="recipienttitle"><button className="client recipientname" onClick={()=>onOpen(group)}>{group.client}<ChevronRight size={16}/></button><small>{group.rows.length} {group.rows.length===1?'conhecimento':'conhecimentos'} · {[...group.cities].join(', ')}</small>{availableClasses(group.rows).length>0&&<small>Classes: {availableClasses(group.rows).join(' · ')}</small>}</td>
   <td data-label="Saldo a receber"><b>{brl(group.balance)}</b></td><td data-label="Status"><span className={'badge '+groupStatus.toLowerCase()}><i/>{groupStatus}</span></td>
  </tr>;
 })}</tbody></table></div>;
}
