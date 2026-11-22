import { readFileSync } from 'node:fs';
import { createApp } from './app.js';
import { lerChave } from './auth/cifra.js';
import { loadConfig } from './config.js';
import { createPool } from './db.js';
import { iniciarAgendador } from './jobs/agendador.js';
import { criarEnviadorFcm, enviadorNulo, type ContaServico } from './push/enviador.js';
import { criarEventosPush } from './push/servico.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const chaveCampos = lerChave(config.EMAIL_ENC_KEY);
const chaveMestra = lerChave(config.PROFILE_MASTER_KEY);

let enviador = enviadorNulo;
if (config.FCM_SERVICE_ACCOUNT_FILE) {
  enviador = criarEnviadorFcm(JSON.parse(readFileSync(config.FCM_SERVICE_ACCOUNT_FILE, 'utf8')) as ContaServico);
} else {
  console.warn('Push desligado: falta FCM_SERVICE_ACCOUNT_FILE.');
}

const app = createApp(db, config, { eventos: criarEventosPush(db, enviador, chaveCampos) });
const pararAgendador = iniciarAgendador({ db, enviador, chaveCampos, chaveMestra });

// Atrás do Caddy, o IP verdadeiro vem no cabeçalho; o Caddy fica na mesma máquina.
const servidor = app.listen(config.PORT, config.HOST, () => {
  console.log(`Amparo API a ouvir em http://${config.HOST}:${config.PORT}`);
});

const parar = () => {
  pararAgendador();
  servidor.close(() => void db.end().then(() => process.exit(0)));
};
process.on('SIGTERM', parar);
process.on('SIGINT', parar);
