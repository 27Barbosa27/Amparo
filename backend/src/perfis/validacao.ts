import { z } from 'zod';

export const timezoneSchema = z
  .string()
  .max(64)
  .refine((tz) => {
    try {
      new Intl.DateTimeFormat('pt-PT', { timeZone: tz });
      return true;
    } catch {
      return false;
    }
  }, 'fuso desconhecido');
