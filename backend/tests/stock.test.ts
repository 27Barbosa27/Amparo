import { describe, expect, it } from 'vitest';
import type { Horario } from '../src/medicacao/servico.js';
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
    expect(calcularStock('10 mg', { ...fixas, horasLocais: ['09:00'] }, 40, 7)).toEqual({ unidadesRestantes: 33, diasRestantes: 33, emFalta: null });
    expect(calcularStock('20 mg', { tipo: 'horas_fixas', horasLocais: ['21:00'] }, 40, 3)).toEqual({ unidadesRestantes: 37, diasRestantes: 37, emFalta: null });
  });

  it('diz quantas unidades faltam até ao fim da receita (24 comprimidos, 2 por dia, 3 meses)', () => {
    const agora = new Date('2026-11-25T08:00:00Z');
    const fim = new Date('2027-02-23T08:00:00Z'); // 90 dias
    const duasVezes: Horario = { tipo: 'horas_fixas', horasLocais: ['08:00', '20:00'] };
    // 2 comprimidos por toma, 2 tomas por dia = 4 por dia: 24 chegam para 6 dias, em 90 dias faltam 336.
    expect(calcularStock('2 comprimidos', duasVezes, 24, 0, fim, agora)).toEqual({ unidadesRestantes: 24, diasRestantes: 6, emFalta: 336 });
    // 1 comprimido por toma: 2 por dia, 24 chegam para 12 dias, faltam 156.
    expect(calcularStock('1 comprimido', duasVezes, 24, 0, fim, agora)).toEqual({ unidadesRestantes: 24, diasRestantes: 12, emFalta: 156 });
  });

  it('não falta nada quando o stock chega, nem depois do fim da receita', () => {
    const agora = new Date('2026-11-25T08:00:00Z');
    const umaVez: Horario = { tipo: 'horas_fixas', horasLocais: ['08:00'] };
    expect(calcularStock('1 comprimido', umaVez, 100, 0, new Date('2026-12-25T08:00:00Z'), agora)?.emFalta).toBe(0);
    expect(calcularStock('1 comprimido', umaVez, 5, 0, new Date('2026-11-01T08:00:00Z'), agora)?.emFalta).toBe(0);
  });
});
