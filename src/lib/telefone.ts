/**
 * Normaliza um celular brasileiro para o formato que o Supabase Auth guarda em auth.users.phone:
 * apenas dígitos, com DDI 55 (ex.: "5511987654321"). Retorna null se não parecer um celular válido.
 */
export function normalizarCelular(entrada: string): string | null {
  let d = entrada.replace(/\D/g, '')
  if (d.startsWith('00')) d = d.slice(2)
  if (d.length === 10 || d.length === 11) d = `55${d}`
  if (!d.startsWith('55')) return null
  // 55 + DDD (2) + número (8 ou 9 dígitos). Celular com 9 dígitos começa com 9.
  if (d.length === 13 && d[4] === '9') return d
  if (d.length === 12) return d
  return null
}

/** Formata "5511987654321" como "(11) 98765-4321". */
export function formatarCelular(normalizado: string): string {
  const d = normalizado.replace(/^55/, '')
  const ddd = d.slice(0, 2)
  const num = d.slice(2)
  const corte = num.length - 4
  return `(${ddd}) ${num.slice(0, corte)}-${num.slice(corte)}`
}
