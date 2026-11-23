import nodemailer from 'nodemailer';

export interface Email {
  para: string;
  assunto: string;
  texto: string;
}

/** Envio de email transacional. Qualquer fornecedor com SMTP serve (Brevo, Mailgun, SES, Scaleway...). */
export interface EnviadorEmail {
  enviar(e: Email): Promise<void>;
}

/** Sem SMTP configurado (desenvolvimento): não envia nada. */
export const enviadorEmailNulo: EnviadorEmail = {
  async enviar() {},
};

/** `smtpUrl` no formato `smtps://utilizador:palavra-passe@servidor:465` (ou `smtp://...:587`). */
export function criarEnviadorSmtp(smtpUrl: string, de: string): EnviadorEmail {
  const transporte = nodemailer.createTransport(smtpUrl);
  return {
    async enviar(e) {
      await transporte.sendMail({ from: de, to: e.para, subject: e.assunto, text: e.texto });
    },
  };
}
