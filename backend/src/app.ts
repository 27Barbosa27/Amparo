import express, { type ErrorRequestHandler } from 'express';
import helmet from 'helmet';
import { ZodError } from 'zod';
import { ErroAuth } from './auth/erros.js';
import { rotasAuth, type OpcoesAuth } from './auth/rotas.js';
import { rotasAlertPrefs } from './alertas/rotas.js';
import { lerChave } from './auth/cifra.js';
import { contactosDoPerfil } from './auth/conta.js';
import { exigirPrincipal, perfilDoPedido } from './auth/principal.js';
import type { Config } from './config.js';
import { rotasPublicasDispositivo, type OpcoesDispositivos } from './dispositivos/rotas.js';
import { pingDb, type Db } from './db.js';
import { semEventos, type Eventos } from './eventos.js';
import { ErroPerfil } from './perfis/acesso.js';
import { rotaPerfilAtivo, rotasPerfis } from './perfis/rotas.js';
import { rotasPush } from './push/rotas.js';
import { rotasTomas } from './tomas/rotas.js';

export interface OpcoesApp {
  auth?: OpcoesAuth;
  dispositivos?: OpcoesDispositivos;
  /** Ganchos de push e sincronização (por omissão não fazem nada). */
  eventos?: Eventos;
}

export function createApp(db: Db, config: Config, opcoes: OpcoesApp = {}) {
  const app = express();
  app.disable('x-powered-by');
  if (config.TRUST_PROXY > 0) app.set('trust proxy', config.TRUST_PROXY);
  app.use(helmet());
  app.use(express.json({ limit: '100kb' }));

  // Estado do servidor (sem tocar na base de dados).
  app.get('/health', (_req, res) => {
    res.json({ estado: 'ok' });
  });

  // Estado do servidor e da base de dados.
  app.get('/health/db', async (_req, res) => {
    const ok = await pingDb(db);
    res.status(ok ? 200 : 503).json({ estado: ok ? 'ok' : 'sem_base_de_dados' });
  });

  app.use('/auth', rotasAuth(db, config, opcoes.auth));
  app.use('/profiles', rotasPerfis(db, config, opcoes.eventos ?? semEventos));
  app.use('/push-tokens', rotasPush(db, config));
  app.use('/perfil-ativo', rotaPerfilAtivo(db, config));
  app.use(rotasPublicasDispositivo(db, config, opcoes.dispositivos));
  app.use('/tomas', rotasTomas(db, config, opcoes.eventos ?? semEventos));
  app.use('/alert-prefs', rotasAlertPrefs(db, config));

  // Quem cuida da pessoa e tem telefone (para o botão "Ligar"): cuidadores e o telemóvel da pessoa.
  app.get('/contacto', exigirPrincipal(db, config.JWT_SECRET), perfilDoPedido(db), async (req, res) => {
    res.json({ contactos: await contactosDoPerfil(db, req.perfil!.id, lerChave(config.EMAIL_ENC_KEY)) });
  });

  app.use((_req, res) => {
    res.status(404).json({ erro: 'nao_encontrado' });
  });

  const erros: ErrorRequestHandler = (err, _req, res, _next) => {
    if (err instanceof ErroAuth) {
      res.status(err.estado).json({ erro: err.codigo });
      return;
    }
    if (err instanceof ErroPerfil) {
      res.status(err.estado).json({ erro: err.codigo });
      return;
    }
    if (err instanceof ZodError) {
      // Só os nomes dos campos: nunca devolvemos os valores (podem ser palavras-passe).
      res.status(400).json({ erro: 'pedido_invalido', campos: [...new Set(err.issues.map((i) => i.path.join('.')))] });
      return;
    }
    if (err instanceof SyntaxError && 'body' in err) {
      res.status(400).json({ erro: 'pedido_invalido', campos: [] });
      return;
    }
    // Nunca devolve detalhes internos ao cliente (podem conter dados de saúde).
    console.error('Erro não tratado:', err instanceof Error ? err.message : 'desconhecido');
    res.status(500).json({ erro: 'erro_interno' });
  };
  app.use(erros);

  return app;
}
