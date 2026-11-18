'use client';
import {useState} from 'react';
import PieChart from './pie-chart';
import {Check,Clock,FileText,MapPin,Wallet,ArrowDownToLine} from 'lucide-react';
import {dashboardData,DashboardUser} from '../../lib/dashboard';
const brl=(value:number)=>(value/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const number=(value:number)=>value.toLocaleString('pt-BR');
type Props={manifests:any[];user:DashboardUser;cityCatalog:any[];loading:boolean;onRefresh:()=>void};
export default function Dashboard({manifests,user,cityCatalog,loading,onRefresh}:Props){
 const [city,setCity]=useState('');const isAdmin=user.role==='admin';
 const {summary,cities}=dashboardData(manifests,user,city);
 const options=new Map<string,string>();
 if(isAdmin)for(const item of cityCatalog)options.set(item.key,item.name);
 for(const item of cities)if(!options.has(item.key))options.set(item.key,item.name);
 const nameOf=(key:string)=>options.get(key)||key;
 const selectedName=isAdmin?(city?nameOf(city):'Todas as cidades'):(user.city||'Cidade não definida');
 const visibleCities=city?cities.filter(item=>item.key===city):cities;
 if(!isAdmin)return <section className="dashboardpage deliverydashboard"><div className="eyebrow">DASHBOARD / {selectedName}</div><div className="heading"><div><h1>Dashboard</h1><p>Recebimentos e pendências de {selectedName}.</p></div><button className="secondary" disabled={loading} onClick={onRefresh}>{loading?'Atualizando…':'Atualizar dados'}</button></div><div className="deliverypies" aria-busy={loading}>
  <PieChart title="Quantidade de conhecimentos" totalLabel={`Total: ${number(summary.count)} conhecimentos`} data={[{label:'Cobranças quitadas',value:summary.paidCount,color:'#246649'},{label:'Pendentes',value:summary.pendingCount,color:'#a64d08'}]} formatValue={number} footnote={`Pendentes inclui ${number(summary.partialCount)} conhecimentos com pagamento parcial.`}/>
  <PieChart title="Valores de cobrança" totalLabel={`Total: ${brl(summary.freight)}`} data={[{label:'Cobrança realizada',value:summary.received,color:'#246649'},{label:'Saldo pendente',value:summary.balance,color:'#a64d08'}]} formatValue={brl} footnote="Cobrança realizada corresponde ao valor recebido, incluindo pagamentos parciais."/>
 </div></section>;
 const metrics=[
  {label:'Total de conhecimentos',value:number(summary.count),detail:`${number(summary.manifestCount)} manifestos com dados`,icon:FileText},
  {label:'Cobranças quitadas',value:number(summary.paidCount),detail:'Conhecimentos pagos integralmente',icon:Check},
  {label:'Pendentes de pagamento',value:number(summary.pendingCount),detail:`Inclui ${number(summary.partialCount)} com pagamento parcial`,icon:Clock},
  {label:'Frete total',value:brl(summary.freight),detail:'Valor total dos conhecimentos',icon:Wallet},
  {label:'Cobrança realizada',value:brl(summary.received),detail:'Valor recebido, incluindo pagamentos parciais',icon:ArrowDownToLine},
  {label:'Saldo a receber',value:brl(summary.balance),detail:'Valor que ainda falta receber',icon:Clock}
 ];
 return <section className="dashboardpage"><div className="eyebrow">FINANCEIRO / DASHBOARD</div><div className="heading"><div><h1>Dashboard</h1><p>Resumo de todos os manifestos disponíveis no seu acesso.</p></div><button className="secondary" disabled={loading} onClick={onRefresh}>{loading?'Atualizando…':'Atualizar dados'}</button></div>
  <div className="dashboardfilters"><div className="dashboardcity"><MapPin size={20}/><div><small>{isAdmin?'Cidade selecionada':'Seu acesso'}</small><strong>{selectedName}</strong></div></div>{isAdmin&&<label>Filtrar por cidade<select aria-label="Filtrar dashboard por cidade" value={city} onChange={e=>setCity(e.target.value)}><option value="">Todas as cidades</option>{[...options].sort((a,b)=>a[1].localeCompare(b[1],'pt-BR')).map(([key,label])=><option value={key} key={key}>{label}</option>)}</select></label>}</div>
  <div className="dashboardmetrics" aria-busy={loading}>{metrics.map((metric,index)=><article className={`dashboardmetric metric${index}`} key={metric.label}><div><span>{metric.label}</span><metric.icon size={18}/></div><strong>{metric.value}</strong><small>{metric.detail}</small></article>)}</div>
  {!summary.count&&!loading&&<div className="dashboardempty" role="status">Nenhum conhecimento encontrado para {selectedName.toLocaleLowerCase('pt-BR')}. Os indicadores serão atualizados quando houver manifestos disponíveis.</div>}
  <section className="dashboardcollection"><div><h2>Andamento dos recebimentos</h2><p>{selectedName} · {summary.receivedPercent.toLocaleString('pt-BR',{maximumFractionDigits:1})}% do frete recebido</p></div><div className="collectionbar" role="img" aria-label={`${summary.receivedPercent.toLocaleString('pt-BR',{maximumFractionDigits:1})}% recebido; ${brl(summary.balance)} pendentes`}><span style={{width:`${summary.receivedPercent}%`}}/></div><div className="collectionlegend"><span><i/>{brl(summary.received)} recebidos</span><span><i/>{brl(summary.balance)} pendentes</span></div><div className="collectioncounts"><div><b>{number(summary.paidCount)}</b><span>Quitados</span></div><div><b>{number(summary.partialCount)}</b><span>Pagamentos parciais</span></div><div><b>{number(summary.unpaidCount)}</b><span>Sem pagamento registrado</span></div></div></section>
  {isAdmin&&<section className="tablecard dashboardcities"><div className="tableheading"><div><h2>Resumo por cidade</h2><p>Pendentes inclui os conhecimentos com pagamento parcial. Clique na cidade para filtrar o dashboard.</p></div></div><div className="tablewrap"><table><thead><tr><th>CIDADE</th><th>CONHECIMENTOS</th><th>QUITADOS</th><th>PARCIAIS</th><th>PENDENTES</th><th>FRETE TOTAL</th><th>RECEBIDO</th><th>SALDO</th></tr></thead><tbody>{visibleCities.map(item=><tr key={item.key}><td data-label="Cidade"><button className="triplink" onClick={()=>setCity(item.key)}>{nameOf(item.key)}</button></td><td data-label="Conhecimentos">{number(item.count)}</td><td data-label="Quitados">{number(item.paidCount)}</td><td data-label="Parciais">{number(item.partialCount)}</td><td data-label="Pendentes">{number(item.pendingCount)}</td><td data-label="Frete total">{brl(item.freight)}</td><td data-label="Recebido" className="received">{brl(item.received)}</td><td data-label="Saldo"><b>{brl(item.balance)}</b></td></tr>)}</tbody></table></div>{!visibleCities.length&&<div className="empty"><p>Não há dados para a cidade selecionada.</p></div>}</section>}
 </section>;
}
