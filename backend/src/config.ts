import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.string().min(1),
  /** Segredo para assinar os tokens de acesso (mínimo 32 caracteres). */
  JWT_SECRET: z.string().min(32),
  /** Segredo (pepper) do hash dos emails (mínimo 32 caracteres). */
  EMAIL_PEPPER: z.string().min(32),
  /** Chave AES-256 (32 bytes em base64url) para cifrar o email, usado na recuperação de palavra-passe. */
  EMAIL_ENC_KEY: z.string().length(43),
  /** Chave-mestra AES-256 (32 bytes em base64url) que protege a chave de cada perfil. */
  PROFILE_MASTER_KEY: z.string().length(43),
  /** Entrar com a Apple: o identificador da aplicação (`aud` do ID token). Sem isto o endpoint responde 501. */
  APPLE_CLIENT_ID: z.string().min(1).optional(),
  /** Entrar com a Google: os identificadores de cliente aceites (web, Android, iOS), separados por vírgulas. */
  GOOGLE_CLIENT_IDS: z
    .string()
    .optional()
    .transform((v) => (v ? v.split(',').map((s) => s.trim()).filter(Boolean) : undefined)),
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
