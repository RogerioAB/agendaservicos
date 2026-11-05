import { describe, expect, it } from 'vitest'
import { formatarCelular, normalizarCelular } from './telefone'

describe('normalizarCelular', () => {
  it('aceita formatos comuns', () => {
    expect(normalizarCelular('(11) 98765-4321')).toBe('5511987654321')
    expect(normalizarCelular('+55 11 98765 4321')).toBe('5511987654321')
    expect(normalizarCelular('11987654321')).toBe('5511987654321')
    expect(normalizarCelular('005511987654321')).toBe('5511987654321')
  })

  it('aceita número antigo de 8 dígitos', () => {
    expect(normalizarCelular('1187654321')).toBe('551187654321')
  })

  it('rejeita números inválidos', () => {
    expect(normalizarCelular('12345')).toBeNull()
    expect(normalizarCelular('+1 415 555 0100')).toBeNull()
    expect(normalizarCelular('11887654321')).toBeNull()
  })
})

describe('formatarCelular', () => {
  it('formata para exibição', () => {
    expect(formatarCelular('5511987654321')).toBe('(11) 98765-4321')
    expect(formatarCelular('551187654321')).toBe('(11) 8765-4321')
  })
})
