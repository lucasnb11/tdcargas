export function normalizeCity(value:unknown){return String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().replace(/\s+/g,' ').toUpperCase();}
export function canAccessCity(user:{role:string,city?:string|null}|null,city:unknown){return !!user&&(user.role==='admin'||user.role==='entregador'&&!!normalizeCity(user.city)&&normalizeCity(user.city)===normalizeCity(city));}
