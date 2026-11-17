export const VESSELS = ['F/B SÃO DOMINGOS V','F/B DONA DOMINGAS'] as const;
export function validateVessel(value: unknown): string {
 if(typeof value!=='string'||!(VESSELS as readonly string[]).includes(value))throw Error('Selecione a embarcação: F/B SÃO DOMINGOS V ou F/B DONA DOMINGAS.');
 return value;
}
