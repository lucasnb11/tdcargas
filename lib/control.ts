export const paid = (row: any): number => row.payments.reduce((sum: number, payment: any) => sum + payment.amount, 0);
export const status = (row: any): string => paid(row) >= row.freight ? 'Pago' : paid(row) > 0 ? 'Parcial' : 'Pendente';
export const tripRows = (manifest: any): any[] => (manifest?.rows || []).map((row: any) => ({...row, manifestId: manifest.id, tripRoute: manifest.route, tripDate: manifest.date, tripVessel: manifest.vessel}));
export const pendingRows = (manifests: any[]): any[] => manifests.flatMap(tripRows).filter(row => row.freight - paid(row) > 0);
export function tripSummary(manifest: any) {
 const rows = tripRows(manifest);
 return {count: rows.length, total: rows.reduce((sum, row) => sum + row.freight, 0), received: rows.reduce((sum, row) => sum + paid(row), 0), balance: rows.reduce((sum, row) => sum + Math.max(0, row.freight - paid(row)), 0), pendingCount: rows.filter(row => row.freight > paid(row)).length};
}

export function clientSummary(manifests: any[]) {
 const groups = new Map<string, any>();
 for (const row of manifests.flatMap(tripRows)) {
  const key = String(row.client).trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const group = groups.get(key) || {key, name: row.client, rows: [], manifestIds: new Set<string>(), total: 0, received: 0, balance: 0};
  group.rows.push(row); group.manifestIds.add(row.manifestId);
  group.total += row.freight; group.received += paid(row); group.balance += Math.max(0,row.freight-paid(row));
  groups.set(key,group);
 }
 return [...groups.values()].sort((a,b)=>a.name.localeCompare(b.name,'pt-BR'));
}

export const pendingRowsForManifest = (manifests: any[], manifestId: string): any[] => pendingRows(manifests.filter(manifest => manifest.id === manifestId));

// Mantém a identidade do manifesto e de cada conhecimento no agrupamento.
export function recipientGroups(rows: any[]) {
 const groups = new Map<string, any>();
 for (const row of rows) {
  const recipientKey = String(row.client).trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const key = JSON.stringify([row.manifestId,recipientKey]);
  const group = groups.get(key) || {key, recipientKey, client:row.client, manifestId:row.manifestId, tripDate:row.tripDate, vessel:row.tripVessel, rows:[], freight:0, received:0, balance:0, cities:new Set<string>(), conferenceCount:0};
  group.rows.push(row); group.freight+=row.freight; group.received+=paid(row); group.balance+=Math.max(0,row.freight-paid(row)); group.cities.add(row.city);
  if(row.conferences?.length)group.conferenceCount++;
  groups.set(key,group);
 }
 return [...groups.values()];
}
