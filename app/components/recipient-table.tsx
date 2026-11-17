'use client';
import {Fragment,useState} from 'react';
import {ArrowUpRight,Check,ChevronRight,FileText} from 'lucide-react';
import {paid,status} from '../../lib/control';
const brl=(v:number)=>(v/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});

type Props={groups:any[];showManifest:boolean;isAdmin:boolean;busy:boolean;onManifest:(id:string)=>void;onPay:(row:any)=>void;onConference:(row:any)=>void;onHistory:(row:any)=>void};
export default function RecipientTable({groups,showManifest,isAdmin,busy,onManifest,onPay,onConference,onHistory}:Props){
 const [expanded,setExpanded]=useState<string|null>(null);
 return <div className="tablewrap"><table className="recipienttable"><thead><tr>{showManifest&&<th>MANIFESTO</th>}<th>DESTINATÁRIO</th><th>DESTINO</th><th>FRETE TOTAL</th><th>RECEBIDO</th><th>SALDO</th><th>STATUS</th><th>CONFERÊNCIA</th><th/></tr></thead><tbody>{groups.map((group,index)=>{
  const open=expanded===group.key,groupStatus=group.balance<=0?'Pago':group.received>0?'Parcial':'Pendente',detailId=`recipient-details-${index}`;
  return <Fragment key={group.key}><tr className={open?'recipientopen':''}>
   {showManifest&&<td><button className="triplink" onClick={()=>onManifest(group.manifestId)}>{group.manifestId}<ArrowUpRight size={12}/></button><small>{group.tripDate}</small></td>}
   <td><button className="client recipientname" aria-expanded={open} aria-controls={detailId} onClick={()=>setExpanded(open?null:group.key)}><ChevronRight size={16} className={open?'rotated':''}/>{group.client}</button><small>{group.rows.length} {group.rows.length===1?'conhecimento':'conhecimentos'} neste manifesto</small></td>
   <td className="city">{[...group.cities].join(', ')}</td><td>{brl(group.freight)}</td><td className="received">{brl(group.received)}</td><td><b>{brl(group.balance)}</b></td><td><span className={'badge '+groupStatus.toLowerCase()}><i/>{groupStatus}</span></td><td><span className={'badge '+(group.conferenceCount===group.rows.length?'pago':'pendente')}>{group.conferenceCount}/{group.rows.length} conferidos</span></td><td><button className="paybutton" aria-expanded={open} aria-controls={detailId} onClick={()=>setExpanded(open?null:group.key)}>{open?'Fechar':'Ver conhecimentos'}<ChevronRight size={14}/></button></td>
  </tr>{open&&<tr className="recipientdetail"><td colSpan={showManifest?9:8}><section id={detailId} aria-label={`Conhecimentos de ${group.client}`}>
   <div className="recipientdetailheading"><FileText size={18}/><div><h3>{group.client}</h3><p>Manifesto {group.manifestId} · Todos os conhecimentos deste destinatário. Registre cada pagamento separadamente.</p></div></div>
   <div className="tablewrap"><table><thead><tr><th>CONHECIMENTO</th><th>DESTINO</th><th>FRETE</th><th>RECEBIDO</th><th>SALDO</th><th>STATUS</th><th>CONFERÊNCIA</th><th>AÇÕES</th></tr></thead><tbody>{group.rows.map((row:any)=><tr key={row.id}><td><b>{row.id}</b><small>{row.volumes} volumes · {row.kind}</small></td><td className="city">{row.city}</td><td>{brl(row.freight)}</td><td className="received">{brl(paid(row))}</td><td><b>{brl(Math.max(0,row.freight-paid(row)))}</b></td><td><span className={'badge '+status(row).toLowerCase()}><i/>{status(row)}</span></td><td>{row.conferences?.length?<span className="badge pago"><Check size={12}/>Conferido</span>:<button className="conferencebutton" disabled={busy} onClick={()=>onConference(row)}><Check size={13}/>Conferir carga</button>}</td><td><div className="knowledgeactions">{status(row)!=='Pago'?<button className="paybutton" disabled={busy} onClick={()=>onPay(row)}>{isAdmin?'Registrar pagamento':'Dar baixa'}<ArrowUpRight size={14}/></button>:<span className="received">✓ Baixado</span>}{isAdmin&&<button className="historybutton" onClick={()=>onHistory(row)}>Ver histórico</button>}</div></td></tr>)}</tbody></table></div>
  </section></td></tr>}</Fragment>;
 })}</tbody></table></div>;
}
