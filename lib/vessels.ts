export const VESSELS = ['F/B SÃO DOMINGOS V','F/B DONA DOMINGAS'] as const;
export function validateVessel(value: unknown): string {
 if(typeof value!=='string'||!(VESSELS as readonly string[]).includes(value))throw Error('Selecione a embarcação: F/B SÃO DOMINGOS V ou F/B DONA DOMINGAS.');
 return value;
}

export function displayVessel(manifest:any):string {
 if(typeof manifest?.vessel==='string'&&manifest.vessel.trim())return manifest.vessel.trim();
 const route=String(manifest?.route||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase();
 if(/\bSAO\s+DOMINGOS\s+V\b/.test(route))return 'F/B SÃO DOMINGOS V';
 if(/\bDONA\s+DOMINGAS\b/.test(route))return 'F/B DONA DOMINGAS';
 return 'Embarcação não informada';
}
export function departureDate(value:unknown):{date:string;weekday:string;iso:string} {
 const raw=typeof value==='string'?value.trim():'';
 const br=raw.match(/^(\d{2})\/(\d{2})\/(\d{4})$/),iso=raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
 const parts=br?[Number(br[3]),Number(br[2]),Number(br[1])]:iso?[Number(iso[1]),Number(iso[2]),Number(iso[3])]:null;
 if(!parts)return {date:raw||'Data não informada',weekday:'',iso:''};
 const [year,month,day]=parts,parsed=new Date(Date.UTC(year,month-1,day));
 if(parsed.getUTCFullYear()!==year||parsed.getUTCMonth()!==month-1||parsed.getUTCDate()!==day)return {date:raw,weekday:'',iso:''};
 const weekdays=['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado'];
 return {date:`${String(day).padStart(2,'0')}/${String(month).padStart(2,'0')}/${year}`,weekday:weekdays[parsed.getUTCDay()],iso:`${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`};
}
export function displayRoute(manifest:any):string {
 return String(manifest?.route||'').replace(/\s*(?:[-–—]\s*)?F\s*\/\s*B\b.*$/iu,'').trim()||'Rota não informada';
}
