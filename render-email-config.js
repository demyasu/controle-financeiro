const fs = require('fs');
const path = require('path');

const vars = {
  RENDER_SMTP_SERVER: process.env.RENDER_SMTP_SERVER || process.env.SMTP_SERVER || 'smtp.sendgrid.net',
  RENDER_SMTP_PORT: process.env.RENDER_SMTP_PORT || process.env.SMTP_PORT || '587',
  RENDER_SMTP_DOMAIN: process.env.RENDER_SMTP_DOMAIN || process.env.SMTP_DOMAIN || 'localhost',
  RENDER_SMTP_USERNAME: process.env.RENDER_SMTP_USERNAME || process.env.SMTP_USERNAME || 'apikey',
  RENDER_SMTP_PASSWORD: process.env.RENDER_SMTP_PASSWORD || process.env.SMTP_PASSWORD || process.env.SENDGRID_API_KEY || '',
  RENDER_SMTP_FROM: process.env.RENDER_SMTP_FROM || process.env.SMTP_FROM || '',
  RENDER_SMTP_FROM_NAME: process.env.RENDER_SMTP_FROM_NAME || process.env.SMTP_FROM_NAME || 'Controle Financeiro'
};

const quote = (value) => {
  if (value === undefined || value === null) {
    return '';
  }
  const text = String(value);
  if (/\s|"|#/.test(text)) {
    return `"${text.replace(/"/g, '\\"')}"`;
  }
  return text;
};

const filePath = path.resolve(__dirname, '.env');
const content = Object.entries(vars)
  .filter(([, value]) => value && String(value).length > 0)
  .map(([key, value]) => `${key}=${quote(value)}`)
  .join('\n') + '\n';

try {
  fs.writeFileSync(filePath, content, { encoding: 'utf8' });
  console.log('[EMAIL_CONFIG] .env atualizado com configuração SMTP');
} catch (error) {
  console.error('[EMAIL_CONFIG] falha ao gravar .env:', error.message);
  process.exit(1);
}
