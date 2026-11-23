import { describe, expect, it } from 'vitest';
import { calcularStock, unidadesPorToma } from '../src/medicacao/stock.js';

describe('Unidades por toma', () => {
  it('lê a quantidade de comprimidos, cápsulas e frações', () => {
    expect(unidadesPorToma('1 comprimido')).toBe(1);
    expect(unidadesPorToma('2 comprimidos')).toBe(2);
    expect(unidadesPorToma('1/2 comprimido')).toBe(0.5);
    expect(unidadesPorToma('0,5 comprimido')).toBe(0.5);
    expect(unidadesPorToma('3 gotas')).toBe(3);
    expect(unidadesPorToma('2 cápsulas')).toBe(2);
  });

  it('uma concentração ("10 mg") não é uma quantidade: conta como 1 unidade', () => {
    for (const dose of ['10 mg', '500 mg', '20 mg', '0,5 mg', '5 ml', '1000 UI', '2,5mg', '50 mcg', '1 g', '10 MG']) {
      expect(unidadesPorToma(dose), dose).toBe(1);
    }
  });

  it('sem número, ou com texto, conta como 1', () => {
    expect(unidadesPorToma('gotas no olho')).toBe(1);
    expect(unidadesPorToma('')).toBe(1);
    expect(unidadesPorToma('0 nada')).toBe(1);
  });

  it('os dias que restam não ficam a zero por causa da concentração (o bug visto com dados reais)', () => {
    const fixas = { tipo: 'horas_fixas', horasLocais: ['09:00'] } as const;
    expect(calcularStock('10 mg', { ...fixas, horasLocais: ['09:00'] }, 40, 7)).toEqual({ unidadesRestantes: 33, diasRestantes: 33 });
    expect(calcularStock('20 mg', { tipo: 'horas_fixas', horasLocais: ['21:00'] }, 40, 3)).toEqual({ unidadesRestantes: 37, diasRestantes: 37 });
  });
});
