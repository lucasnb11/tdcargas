'use client';
import {useState} from 'react';
import PieChart from './pie-chart';
import {canAccessCity} from '../../lib/cities';
import {departureDate,displayVessel} from '../../lib/vessels';
import {Check,Clock,FileText,MapPin,Wallet,ArrowDownToLine} from 'lucide-react';
import {dashboardData,DashboardUser} from '../../lib/dashboard';
const brl=(value:number)=>(value/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const number=(value:number)=>value.toLocaleString('pt-BR');
type Props={manifests:any[];user:DashboardUser;cityCatalog:any[];loading:boolean;onRefresh:()=>void};
export default function Dashboard({manifests,user,cityCatalog,loading,onRefresh}:Props){
 const [city,setCity]=useState(''),[trip,setTrip]=useState('');const isAdmin=user.role==='admin';
 const {summary,cities}=dashboardData(manifests,user,city,isAdmin?'':trip);
 const options=new Map<string,string>();
 if(isAdmin)for(const item of cityCatalog)options.set(item.key,item.name);
 for(const item of cities)if(!options.has(item.key))options.set(item.key,item.name);
 const nameOf=(key:string)=>options.get(key)||key;
 const selectedName=isAdmin?(city?nameOf(city):'Todas as cidades'):(user.city||'Cidade não definida');
 const visibleCities=city?cities.filter(item=>item.key===city):cities;
 const availableTrips=manifests.filter(manifest=>manifest.rows.some((row:any)=>canAccessCity(user,row.city)));
 if(!isAdmin)return <section className="dashboardpage deliverydashboard"><div className="eyebrow">DASHBOARD / {selectedName}</div><div className="heading"><div><h1>Dashboard de peças</h1><p>Quantidades de peças de {selectedName}, conforme os volumes dos manifestos.</p></div><button className="secondary" disabled={loading} onClick={onRefresh}>{loading?'Atualizando…':'Atualizar dados'}</button></div><div className="dashboardtripfilter"><label>Filtrar por viagem / manifesto<select aria-label="Filtrar dashboard por viagem" value={trip} onChange={e=>setTrip(e.target.value)}><option value="">Todas as viagens da minha cidade</option>{trip&&!availableTrips.some(manifest=>manifest.id===trip)&&<option value={trip}>Viagem {trip} — sem dados disponíveis</option>}{availableTrips.map(manifest=>{const departure=departureDate(manifest.date);return <option key={manifest.id} value={manifest.id}>Saída {departure.date}{departure.weekday?` · ${departure.weekday}`:''} · {displayVessel(manifest)} · Viagem {manifest.id}</option>})}</select></label></div><div className="deliverypies singlepie" aria-busy={loading}>
  <PieChart title="Quantidade de peças" totalLabel={`Total: ${number(summary.piecesCount)} peças`} data={[{label:'Peças com cobrança quitada',value:summary.paidPieces,color:'#246649'},{label:'Peças pendentes',value:summary.pendingPieces,color:'#a64d08'}]} formatValue={value=>`${number(value)} peças`} footnote="Peças correspondem aos volumes do manifesto. A quitação considera cada nota/frete quando detalhada; nos demais casos, considera o conhecimento. Pagamentos parciais não são convertidos proporcionalmente em peças."/>
 </div>{summary.unknownVolumesCount>0&&<p className="hint">{number(summary.unknownVolumesCount)} conhecimentos não possuem quantidade de peças informada e precisam de conferência.</p>}</section>;
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

## Recebimento manual e prazo de cobrança

Na tela do destinatário, Confirmar recebimento inicia 7 dias corridos (168 horas). A conferência de carga é independente e não inicia prazos retroativos para registros antigos. Pagamentos que deixam saldo no conhecimento renovam o prazo pelo horário do servidor, inclusive pagamentos de notas/fretes. A quitação encerra a pendência. Após o vencimento, todo pagamento daquele conhecimento fica bloqueado, incluindo notas, lote e a RPC legada. Somente um administrador pode usar Liberar por mais 7 dias. Recebimento, renovações e liberações ficam auditados no conhecimento. A liberação também é necessária para um administrador pagar item vencido. Pagar tudo exige que todos os conhecimentos com saldo estejam liberados; pagamentos dos demais itens continuam disponíveis individualmente.

Para outra instalação, aplicar as migrações `supabase/migrations/20261118231651_prazo_cobranca_conhecimento.sql` e `supabase/migrations/20261118232042_pagamento_legado_prazo_cobranca.sql`, nessa ordem, após os scripts 01 a 06. O bloqueio é calculado pelo prazo na gravação, sem depender de tarefa agendada ou do relógio do navegador.

## Relatório de cobranças

A aba Relatório de cobranças permite gerar uma consulta por viagem/manifesto, cidade (administradores), situação e destinatário/conhecimento. Entregadores acessam apenas a própria cidade. Gerar relatório recarrega os dados do servidor e registra o horário da consulta; mudar os filtros exige gerar novamente. O CSV exporta exatamente os resultados gerados e pode ser aberto no Excel.

Os grupos são exclusivos pelo saldo atual: Cobradas (Total) = quitadas; Cobradas (Parcial) = têm recebimento e saldo; Pendentes de cobrança = sem pagamento registrado. Um conhecimento quitado após vários parciais aparece apenas em Total. A consulta soma somente pagamentos dos conhecimentos, sem duplicar detalhes das notas/fretes. Mostra conhecimentos, peças/volumes, frete, recebido, saldo e prazo/bloqueio. Pendente identifica ausência de pagamento no sistema, não tentativa de cobrança. Nenhum dado operacional é alterado ao gerar o relatório.
