import express, { type ErrorRequestHandler } from 'express';
import { rateLimit } from 'express-rate-limit';
import helmet from 'helmet';
import { ZodError } from 'zod';
import { ErroAuth } from './auth/erros.js';
import { rotasAuth, type OpcoesAuth } from './auth/rotas.js';
import { rotasAlertPrefs } from './alertas/rotas.js';
import { lerChave } from './auth/cifra.js';
import { contactosDoPerfil } from './auth/conta.js';
import { exigirPrincipal, perfilDoPedido, soUtilizador } from './auth/principal.js';
import type { Config } from './config.js';
import { rotasPublicasDispositivo, type OpcoesDispositivos } from './dispositivos/rotas.js';
import { pingDb, type Db } from './db.js';
import { semEventos, type Eventos } from './eventos.js';
import { rotasMedicacao } from './medicacao/rotas.js';
import { ErroPerfil } from './perfis/acesso.js';
import { rotaPerfilAtivo, rotasPerfis } from './perfis/rotas.js';
import { rotasPush } from './push/rotas.js';
import { rotasTomas } from './tomas/rotas.js';

export interface OpcoesApp {
  auth?: OpcoesAuth;
  dispositivos?: OpcoesDispositivos;
  /** Ganchos de push e sincronização (por omissão não fazem nada). */
  eventos?: Eventos;
  /** Onde escrever o registo dos pedidos. Por omissão, a consola (menos nos testes). `false` desliga. */
  registar?: ((linha: Record<string, unknown>) => void) | false;
  /** Limite global de pedidos por IP. Por omissão só em produção. */
  limiteGlobal?: { janelaMs: number; maximo: number } | false;
}

export function createApp(db: Db, config: Config, opcoes: OpcoesApp = {}) {
  const app = express();
  app.disable('x-powered-by');
  if (config.TRUST_PROXY > 0) app.set('trust proxy', config.TRUST_PROXY);
  app.use(helmet());
  app.use(express.json({ limit: '100kb' }));

  // Registo dos pedidos: só o método, o padrão da rota (sem ids), o estado e a duração. Nunca corpo, query, cabeçalhos nem IP.
  const registar = opcoes.registar === undefined ? (config.NODE_ENV === 'test' ? false : (l: Record<string, unknown>) => console.log(JSON.stringify(l))) : opcoes.registar;
  if (registar) {
    app.use((req, res, next) => {
      const inicio = process.hrtime.bigint();
      res.on('finish', () => {
        const rota = req.originalUrl.split('?')[0]!.slice(0, 100); // sem a query
        registar({
          ts: new Date().toISOString(),
          metodo: req.method,
          rota: rota.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, ':id'),
          estado: res.statusCode,
          ms: Number((process.hrtime.bigint() - inicio) / 1_000_000n),
        });
      });
      next();
    });
  }

  // Estado do servidor (sem tocar na base de dados).
  app.get('/health', (_req, res) => {
    res.json({ estado: 'ok' });
  });

  // Estado do servidor e da base de dados.
  app.get('/health/db', async (_req, res) => {
    const ok = await pingDb(db);
    res.status(ok ? 200 : 503).json({ estado: ok ? 'ok' : 'sem_base_de_dados' });
  });

  // Rede de segurança contra abuso (os limites mais apertados estão nas rotas de entrada e de ligação).
  const global = opcoes.limiteGlobal === undefined ? (config.NODE_ENV === 'production' ? { janelaMs: 60_000, maximo: 600 } : false) : opcoes.limiteGlobal;
  if (global) {
    app.use(
      rateLimit({
        windowMs: global.janelaMs,
        limit: global.maximo,
        standardHeaders: 'draft-7',
        legacyHeaders: false,
        handler: (_req, res) => {
          res.status(429).json({ erro: 'demasiadas_tentativas' });
        },
      }),
    );
  }

  app.use('/auth', rotasAuth(db, config, opcoes.auth));
  app.use('/profiles', rotasPerfis(db, config, opcoes.eventos ?? semEventos));
  app.use('/push-tokens', rotasPush(db, config));
  app.use('/perfil-ativo', rotaPerfilAtivo(db, config));
  app.use(rotasPublicasDispositivo(db, config, opcoes.dispositivos));
  app.use('/tomas', rotasTomas(db, config, opcoes.eventos ?? semEventos));

  // O mapa do plano usa /receitas e /medicamentos com o perfil no cabeçalho X-Profile-Id (as mesmas rotas de /profiles/:id/...).
  const medicacaoPorCabecalho = express.Router();
  medicacaoPorCabecalho.use(['/receitas', '/medicamentos'], exigirPrincipal(db, config.JWT_SECRET), soUtilizador, perfilDoPedido(db));
  medicacaoPorCabecalho.use(rotasMedicacao(db, lerChave(config.PROFILE_MASTER_KEY), opcoes.eventos ?? semEventos));
  app.use(medicacaoPorCabecalho);
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
