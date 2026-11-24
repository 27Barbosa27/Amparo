import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Os testes que não são da verificação do email registam contas e usam-nas logo; os da verificação
    // (tests/verificacao-email.test.ts) ligam-na explicitamente.
    env: { EXIGIR_VERIFICACAO_EMAIL: 'false' },
  },
});
