'use client';
type Slice={label:string;value:number;color:string};
type Props={title:string;totalLabel:string;data:Slice[];formatValue:(value:number)=>string;footnote?:string};
const percent=(value:number)=>value.toLocaleString('pt-BR',{maximumFractionDigits:1});
export default function PieChart({title,totalLabel,data,formatValue,footnote}:Props){
 const slices=data.filter(slice=>slice.value>0),total=slices.reduce((sum,slice)=>sum+slice.value,0);
 let angle=-Math.PI/2;
 const parts=slices.map(slice=>{
  const start=angle,size=slice.value/total*Math.PI*2;angle+=size;
  return {...slice,ratio:slice.value/total,path:`M 130 130 L ${130+106*Math.cos(start)} ${130+106*Math.sin(start)} A 106 106 0 ${size>Math.PI?1:0} 1 ${130+106*Math.cos(angle)} ${130+106*Math.sin(angle)} Z`,x:130+66*Math.cos(start+size/2),y:130+66*Math.sin(start+size/2)};
 });
 return <figure className="dashboardpie"><figcaption><h2>{title}</h2><p>{totalLabel}</p></figcaption><svg className="dashboardpiesvg" viewBox="0 0 260 260" role="img" aria-label={`${title}. ${totalLabel}. ${data.map(slice=>`${slice.label}: ${formatValue(slice.value)}`).join('. ')}`}>
  {total===0?<><circle cx="130" cy="130" r="106" fill="#e7edf3"/><text x="130" y="135" textAnchor="middle" fill="#62788c" fontSize="15">Sem dados</text></>:parts.map(slice=><g key={slice.label}>{slice.ratio===1?<circle cx="130" cy="130" r="106" fill={slice.color}><title>{slice.label}: {formatValue(slice.value)} · 100%</title></circle>:<path d={slice.path} fill={slice.color} stroke="white" strokeWidth="2"><title>{slice.label}: {formatValue(slice.value)} · {percent(slice.ratio*100)}%</title></path>}{slice.ratio>=0.06&&<text x={slice.ratio===1?130:slice.x} y={slice.ratio===1?135:slice.y} textAnchor="middle" dominantBaseline="middle" fill="white" fontSize="16" fontWeight="700" pointerEvents="none">{percent(slice.ratio*100)}%</text>}</g>)}
 </svg><ul className="dashboardpielegend">{data.map(slice=><li key={slice.label}><i style={{background:slice.color}}/><span><b>{slice.label}</b><small>{percent(total?slice.value/total*100:0)}%</small></span><strong>{formatValue(slice.value)}</strong></li>)}</ul>{footnote&&<p className="dashboardpiefootnote">{footnote}</p>}</figure>;
}
