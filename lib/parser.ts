import {normalizeCity} from './cities';
const DEFAULT_CITIES=['ALMEIRIM','GURUPA','PORTO DE MOZ'];
export function parseManifest(text:string,cityNames:string[]=DEFAULT_CITIES){
 const money=(s:string)=>Math.round(Number(s.replaceAll('.','').replace(',','.'))*100);
 const knownCities=new Set([...DEFAULT_CITIES,...cityNames].map(normalizeCity));
 let city='',kind='FOB';const rows:any[]=[];
 const trip=text.match(/(?:VIAGE\w*\s+)?(\d{6}\/\d{4})\s+(\d{2}\/\d{2}\/\d{4})\s+(\d{2}:\d{2})\s+([^\n]+)/);
 for(const raw of text.split('\n')){const line=raw.trim(),normalized=normalizeCity(line);
 if(knownCities.has(normalized)){city=line;continue;}
 if(/^(FOB|CIF|VEICULO|VEÍCULO)$/.test(line)){kind=line;continue;}
 const m=line.match(/^(\d{6}\/\d{4})\s+(.+?)\s+([\d.,]+)\s+(\d+)\s+([\d.,]+)$/);
 if(m){if(!city)throw Error('Cadastre a cidade de destino em Cidades antes de importar este manifesto.');rows.push({id:m[1],client:m[2].trim(),city,kind,goods:money(m[3]),volumes:Number(m[4]),freight:money(m[5]),payments:[]});continue;}
 if(normalized.length>=2&&normalized.length<=80&&/^[A-Z][A-Z .'-]+$/.test(normalized)&&!/^(MANIFESTO|CONHECIMENT|CLIENTE|MERCADOR|VOLUMES|FRETE|TOTAL|VIAGE)/.test(normalized))throw Error(`Destino não cadastrado: ${line}. Cadastre a cidade antes de importar.`);
 }
 if(!trip||!rows.length)throw Error('Não foi possível reconhecer o manifesto. Utilize um PDF com texto no modelo do exemplo.');
 if(new Set(rows.map(r=>r.id)).size!==rows.length)throw Error('O arquivo contém conhecimentos duplicados. Revise antes de importar.');
 const count=text.match(/TOTAL DA VIAGEM:\s*QTD:\s*(\d+)/);if(count&&Number(count[1])!==rows.length)throw Error('A quantidade extraída difere do total do manifesto. Revise o arquivo antes de importar.');
 return {id:trip[1],date:trip[2],time:trip[3],route:trip[4].trim(),rows};
}
