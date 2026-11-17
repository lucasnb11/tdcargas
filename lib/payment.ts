export const PARTIAL_REASONS = ['Sem dinheiro','Acordo com administração','Pagamento parcelado','Outros'] as const;

export function partialPaymentNote(reason: unknown, installments: unknown, note: unknown): string {
 if(typeof reason!=='string'||!(PARTIAL_REASONS as readonly string[]).includes(reason))throw Error('Selecione a justificativa do pagamento parcial.');
 if(reason==='Pagamento parcelado'){
  if(typeof installments!=='number'||!Number.isSafeInteger(installments)||installments<2)throw Error('Informe uma quantidade inteira de parcelas, a partir de 2.');
  return `Pagamento parcelado em ${installments} vezes`;
 }
 if(reason==='Outros'){
  if(typeof note!=='string'||!note.trim())throw Error('Descreva a justificativa em Outros.');
  if(note.trim().length>1900)throw Error('A justificativa deve ter até 1900 caracteres.');
  return `Outros: ${note.trim()}`;
 }
 return reason;
}
