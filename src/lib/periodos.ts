export type Periodo = 'manha' | 'tarde'
export type PeriodoPreferido = Periodo | 'tanto_faz'

export const PERIODOS: Record<Periodo, { rotulo: string; inicio: string; fim: string }> = {
  manha: { rotulo: 'Manhã', inicio: '08:00', fim: '12:00' },
  tarde: { rotulo: 'Tarde', inicio: '13:00', fim: '17:00' },
}
