export function crc16(payload:string){let crc=0xffff;for(const byte of new TextEncoder().encode(payload)){crc^=byte<<8;for(let n=0;n<8;n++)crc=crc&0x8000?((crc<<1)^0x1021)&0xffff:(crc<<1)&0xffff;}return crc.toString(16).toUpperCase().padStart(4,'0');}
export function field(id:string,value:string){const len=new TextEncoder().encode(value).length;if(len>99)throw Error('Campo Pix excede o tamanho permitido.');return id+String(len).padStart(2,'0')+value;}
export function merchantText(value:string,max:number){const result=value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9 ]/g,' ').replace(/\s+/g,' ').trim();if(!result||result.length>max)throw Error(`Nome ou cidade inválidos: utilize até ${max} caracteres sem acentos.`);return result;}
export function validatePixConfig(input:any){
 const keyType=String(input.keyType||'');let key=String(input.key||'').trim();if(['cpf','cnpj'].includes(keyType))key=key.replace(/[.\/-]/g,'');if(keyType==='email')key=key.toLowerCase();
 const patterns:Record<string,RegExp>={cpf:/^\d{11}$/,cnpj:/^\d{14}$/,email:/^[a-z0-9.!#$%&'*+\-/=?^_`{|}~]+@[a-z0-9.-]+\.[a-z]{2,}$/,phone:/^\+[1-9]\d{9,14}$/,random:/^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/i};
 if(!patterns[keyType]?.test(key)||key.length>77)throw Error('Chave Pix inválida para o tipo selecionado. Para telefone, use o código do país, por exemplo +5591999999999.');
 const name=merchantText(String(input.name||''),25),city=merchantText(String(input.city||''),15);return {keyType,key,name,city};
}
export function pixPayload(config:{key:string,name:string,city:string},cents:number,reference:string){if(!Number.isSafeInteger(cents)||cents<=0||cents>99999999999)throw Error('Valor Pix inválido.');if(!/^[A-Za-z0-9]{1,25}$/.test(reference))throw Error('Referência Pix inválida.');
 const account=field('00','br.gov.bcb.pix')+field('01',config.key);const payload=field('00','01')+field('26',account)+field('52','0000')+field('53','986')+field('54',(cents/100).toFixed(2))+field('58','BR')+field('59',config.name)+field('60',config.city)+field('62',field('05',reference))+'6304';return payload+crc16(payload);
}
