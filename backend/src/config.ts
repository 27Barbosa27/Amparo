import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.string().min(1),
  /** Segredo para assinar os tokens de acesso (mínimo 32 caracteres). */
  JWT_SECRET: z.string().min(32),
  /** Segredo (pepper) do hash dos emails (mínimo 32 caracteres). */
  EMAIL_PEPPER: z.string().min(32),
});

export type Config = z.infer<typeof schema>;

/** Lê e valida as variáveis de ambiente. Falha logo ao arrancar se algo estiver mal. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const campos = parsed.error.issues.map((i) => i.path.join('.')).join(', ');
    throw new Error(`Configuração inválida: ${campos}`);
  }
  return parsed.data;
}
