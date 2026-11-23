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

A aba Relatório de cobranças é exclusiva para administradores e permite gerar uma consulta por viagem/manifesto, cidade (administradores), situação e destinatário/conhecimento. Entregadores não visualizam a aba nem geram este relatório. Gerar relatório recarrega os dados do servidor e registra o horário da consulta; mudar os filtros exige gerar novamente. O CSV exporta exatamente os resultados gerados e pode ser aberto no Excel.

Os grupos são exclusivos pelo saldo atual: Cobradas (Total) = quitadas; Cobradas (Parcial) = têm recebimento e saldo; Pendentes de cobrança = sem pagamento registrado. Um conhecimento quitado após vários parciais aparece apenas em Total. A consulta soma somente pagamentos dos conhecimentos, sem duplicar detalhes das notas/fretes. Mostra conhecimentos, peças/volumes, frete, recebido, saldo e prazo/bloqueio. Pendente identifica ausência de pagamento no sistema, não tentativa de cobrança. Nenhum dado operacional é alterado ao gerar o relatório.

## Fluxo simplificado de operação

- Importar novas viagens e retomar a importação dos conhecimentos: Viagens e manifestos.
- Consultar todos os conhecimentos entre viagens: Conhecimentos. Clientes pagadores mantém o consolidado por cliente entre manifestos; Pendências mostra só saldos da viagem selecionada. Essas consultas têm escopos diferentes.
- Abrir destinatário: clique diretamente no nome, sem um segundo botão com a mesma função.
- Confirmar recebimento e pagar: tela dos conhecimentos do destinatário. Pagar tudo aparece quando há mais de um conhecimento com saldo; para um único saldo, use Pagar conhecimento.
- Consultar histórico: Ver histórico, sem outra entrada para pagar.
- Gerar e exportar: Relatório de cobranças, exclusivo do administrador. O CSV inclui também rota e histórico de pagamentos.

Foram removidas as entradas repetidas de importação, o banner que duplicava o menu de pendências e a interface de notas/fretes que ficou sem acesso. A importação de detalhes, os registros existentes e os controles no banco foram preservados.

A consulta global Conhecimentos é exclusiva do administrador. Entregadores acessam os conhecimentos pelo fluxo Viagens e manifestos → Abrir cargas para baixa → Destinatário.

Os menus Conhecimentos, Clientes pagadores e Pendências de pagamento foram removidos de todos os perfis. A operação fica em Viagens e manifestos → Destinatário → Conhecimento; a busca e os filtros de situação continuam no manifesto. A consulta financeira e exportação ficam no Dashboard e no Relatório de cobranças administrativo.

### Mercadorias, despesas e avarias

Importação de conhecimentos: a coluna `Class.` do PDF é preservada por nota/frete, com conferência e correção da classe na prévia. O catálogo de classes é formado pelos itens importados e aceita novos nomes. A busca por classe seleciona destinatários e conhecimentos correspondentes; o relatório de cobranças mantém os totais integrais dos conhecimentos e oferece um resumo e CSV por classe com os valores de cada item, sem duplicar recebimentos. Mercadorias com divisão manual ou ajustes anteriores são preservadas; notas já vinculadas a pagamentos ou avarias só aceitam reclassificação se identidade, ordem, volumes e frete permanecerem iguais.

A operação continua em Viagens e manifestos → destinatário → conhecimento. Mercadorias abre os itens importados; antes de pagamentos ou ajustes, o administrador pode dividir uma nota por categoria (Bebidas, Estiva, Outros), fechando os fretes e volumes com o conhecimento. Descrição e categoria são manuais quando o PDF não as informa. Pagamentos e ajustes individuais mantêm o saldo do conhecimento; ajustes exigem justificativa. O prazo e o bloqueio de cobrança continuam no conhecimento. Importar novamente não sobrescreve uma divisão manual nem fretes ajustados.

Despesas e avarias é o controle por viagem/cidade. Despesas registram saídas já realizadas, com categoria, origem do dinheiro e até três fotos. Avarias são registradas no conhecimento ou item: quantidade, descrição, fotos e valor solicitado. Apenas administradores aprovam/rejeitam com justificativa. Após aprovação, o usuário da cidade ou administrador registra a indenização paga, com comprovante obrigatório. Este registro não transfere dinheiro e não reduz o frete. Os eventos ficam auditados, e o pagamento não pode ser registrado duas vezes.

O resumo separa cobranças em espécie, outros meios, saídas do dinheiro das cobranças, despesas, indenizações, valores aprovados a pagar e recursos próprios. Não registra repasses à empresa nem reembolsos de recursos próprios. CSV administrativo exporta o filtro aplicado. Backup v2 inclui operações; v1 continua aceito. Fotos privadas ficam no Supabase Storage: o JSON guarda referências, não os binários. Leituras respeitam a cidade e URLs de imagens expiram em cinco minutos.
