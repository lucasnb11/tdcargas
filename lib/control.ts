export const paid = (row: any): number => row.payments.reduce((sum: number, payment: any) => sum + payment.amount, 0);
export const status = (row: any): string => paid(row) >= row.freight ? 'Pago' : paid(row) > 0 ? 'Parcial' : 'Pendente';
export const tripRows = (manifest: any): any[] => (manifest?.rows || []).map((row: any) => ({...row, manifestId: manifest.id, tripRoute: manifest.route, tripDate: manifest.date}));
export const pendingRows = (manifests: any[]): any[] => manifests.flatMap(tripRows).filter(row => row.freight - paid(row) > 0);
export function tripSummary(manifest: any) {
 const rows = tripRows(manifest);
 return {count: rows.length, total: rows.reduce((sum, row) => sum + row.freight, 0), received: rows.reduce((sum, row) => sum + paid(row), 0), balance: rows.reduce((sum, row) => sum + Math.max(0, row.freight - paid(row)), 0), pendingCount: rows.filter(row => row.freight > paid(row)).length};
}
