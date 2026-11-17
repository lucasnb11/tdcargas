'use client';
import {useEffect,useRef,useState} from 'react';
import {parseFreightDocuments} from '../../lib/freight-parser';
export default function FreightImport({manifests,onSave,targetManifestId,guided=false,onSkip}:{manifests:any[];onSave:(records:any[])=>Promise<void>;targetManifestId?:string;guided?:boolean;onSkip?:()=>void}){
 const [progress,setProgress]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[preview,setPreview]=useState<any>(null),[confirmed,setConfirmed]=useState(false);const cancelled=useRef(false);
 useEffect(()=>()=>{cancelled.current=true;},[]);
 async function read(file:File){setBusy(true);setError('');setPreview(null);setConfirmed(false);cancelled.current=false;let worker:any,pdf:any;try{
  if(file.size>50*1024*1024)throw Error('O PDF deve ter até 50 MB.');
  const pdfjs=await import('pdfjs-dist');pdfjs.GlobalWorkerOptions.workerSrc='/pdf.worker.min.mjs';pdf=await pdfjs.getDocument({data:new Uint8Array(await file.arrayBuffer())}).promise;
  if(pdf.numPages>500)throw Error('Divida o PDF em arquivos de até 500 páginas.');let text='';
  for(let n=1;n<=pdf.numPages;n++){
   if(cancelled.current)throw Error('Leitura cancelada.');setProgress(`Lendo página ${n} de ${pdf.numPages}…`);
   const page=await pdf.getPage(n),content=await page.getTextContent(),lines=new Map<number,any[]>();
   for(const item of content.items as any[]){if(!item.str)continue;const y=Math.round(item.transform[5]/3)*3;lines.set(y,[...(lines.get(y)||[]),item]);}
   let pageText=[...lines.keys()].sort((a,b)=>b-a).map(y=>lines.get(y)!.sort((a,b)=>a.transform[4]-b.transform[4]).map(i=>i.str).join(' ')).join('\n');
   if(!/Conhecimento[^\n]*\n\s*\d{6}\/\d{4}/i.test(pageText)){
    setProgress(`Reconhecendo página ${n} de ${pdf.numPages} (OCR)…`);
    if(!worker){const {createWorker,PSM}=await import('tesseract.js');worker=await createWorker('eng',1,{workerPath:'https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/worker.min.js'});await worker.setParameters({tessedit_pageseg_mode:PSM.SINGLE_BLOCK});}
    const viewport=page.getViewport({scale:2.3}),canvas=document.createElement('canvas');canvas.width=Math.ceil(viewport.width);canvas.height=Math.ceil(viewport.height);
    await page.render({canvas,canvasContext:canvas.getContext('2d')!,viewport}).promise;
    pageText=(await worker.recognize(canvas)).data.text;canvas.width=0;canvas.height=0;
   }
   text+='\n'+pageText;page.cleanup();
  }
  if(cancelled.current)throw Error('Leitura cancelada.');setPreview(parseFreightDocuments(text,manifests,targetManifestId));
 }catch(e:any){setError(e.message);}finally{if(worker)await worker.terminate().catch(()=>{});if(pdf)await pdf.destroy().catch(()=>{});setBusy(false);setProgress('');}}
 async function save(){setBusy(true);setError('');try{await onSave(preview.records);}catch(e:any){setError(e.message);}finally{setBusy(false);}}
 return <>{guided&&<><p className="importstep">Etapa 2 de 2 · Conhecimentos</p><div className="importsuccess" role="status">Manifesto {targetManifestId} importado com sucesso.</div></>}<h2 id="modal-title">Importar conhecimentos</h2><p>Agora selecione o PDF dos conhecimentos individuais. Ele detalha as notas/fretes para consultar e pagar cada um separadamente.{targetManifestId&&` Os dados serão vinculados somente ao manifesto ${targetManifestId}.`}</p><p className="hint">O manifesto já permite pagar por conhecimento ou usar Pagar tudo. Esta etapa acrescenta o pagamento individual por nota/frete e preserva os pagamentos existentes.</p><label className="upload">Selecionar PDF dos conhecimentos<input type="file" accept="application/pdf,.pdf" disabled={busy} onChange={e=>{const file=e.target.files?.[0];if(file)read(file);e.target.value='';}}/></label><p className="hint">PDFs digitalizados são reconhecidos neste dispositivo por OCR. Arquivos grandes podem levar vários minutos; mantenha esta tela aberta.</p>{progress&&<div role="status"><p>{progress}</p><button className="secondary" onClick={()=>{cancelled.current=true;}}>Cancelar leitura</button></div>}
 {preview&&<div className="freightimportpreview"><h3>{preview.records.length} conhecimentos prontos para vincular</h3>{preview.records.map((record:any)=><article className="event" key={`${record.manifestId}:${record.rowId}`}><b>{record.rowId} · {record.client}</b><p>Viagem {record.manifestId} · {record.items.length} notas/fretes</p>{record.items.map((item:any)=><small key={item.id}>Nota {item.noteNumber} · {(item.freight/100).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}</small>)}</article>)}{preview.errors.length>0&&<div className="error"><b>{preview.errors.length} pendências de leitura (não serão importadas)</b><ul>{preview.errors.map((item:string,index:number)=><li key={index}>{item}</li>)}</ul></div>}<label><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/> Conferi os números e os valores das notas/fretes que serão vinculados.</label><button className="primary full" disabled={busy||!confirmed||!preview.records.length} onClick={save}>{busy?'Salvando…':`Vincular ${preview.records.length} conhecimentos conferidos`}</button></div>}{error&&<div className="error" role="alert">{error}</div>}{guided&&onSkip&&<button type="button" className="secondary full" disabled={busy} onClick={onSkip}>Importar conhecimentos depois</button>}</>;
}
