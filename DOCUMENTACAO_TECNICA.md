# Documentação Técnica - ControleFinanceiroApp

## 1. Visão Geral do Projeto
**Objetivo**: Aplicativo de controle financeiro pessoal para acompanhamento de receitas, despesas e pagamentos parcelados.  
**Stack Tecnológica**: Ruby 3.2, Sinatra 3.2, PStore (persistência), ERB (views), Bootstrap 5.3 (frontend), `write_xlsx` (exportação Excel), Chart.js (visualizações no dashboard).  
**Escopo Atual**: Usuário único, implantação local com desenvolvimento ágil iterativo.

---

## 2. Arquitetura
### 2.1 Camada de Dados
- **Banco de Dados**: PStore (armazenamento transacional baseado em arquivo) em `db/transactions.pstore`
- **Limitações**: Single-threaded, sem suporte multi-usuário, adequado para uso local com baixa concorrência
- **Migrações na Inicialização** (`app.rb:14-28`): Adiciona automaticamente campos faltantes (`status`, `paid_installments`) às transações existentes ao iniciar a aplicação.

### 2.2 Camada de Aplicação
- **Arquitetura em arquivo único**: Todas as rotas, helpers e lógica de negócio em `app.rb`
- **Views**: Templates ERB no diretório `views/` com estilização Bootstrap 5.3
- **Assets Estáticos**: Diretório `public/` para CSS/JS

---

## 3. Modelo de Dados
### 3.1 Atributos da Transação
| Campo | Tipo | Descrição | Padrão |
|-------|------|-------------|---------|
| `id` | Integer | Identificador único auto-incremental | `DB[:next_id]` |
| `transaction_date` | Date | Data da transação | Obrigatório |
| `description` | String | Descrição da transação | Obrigatório |
| `amount` | Float | Valor em BRL | Obrigatório |
| `transaction_type` | String | Tipo da transação | Obrigatório |
| `category` | String | Categoria de despesa (apenas para tipo `Gasto`) | Opcional |
| `payment_method` | String | Método de pagamento | Opcional |
| `financing_type` | String | `cartao`/`financiamento`/`pix` | Opcional |
| `installments` | Integer | Número de parcelas (1-120) | Opcional |
| `due_date` | Date | Data de vencimento para financiamentos | Opcional |
| `bank` | String | Banco/nome do cartão | Opcional |
| `card_name` | String | Nome personalizado do cartão/banco | Opcional |
| `status` | String | Status geral da transação (`Pago`/`Pendente`) | `Pendente` |
| `paid_installments` | Array | Lista de números de parcelas pagas (ex.: `[1,3]`) | `[]` |
| `created_at` | Time | Timestamp de criação | `Time.now` |
| `updated_at` | Time | Timestamp da última atualização | `Time.now` |

---

## 4. Funcionalidades e Regras de Negócio
### 4.1 Gerenciamento de Transações (CRUD)
- **Criar**: `POST /transactions` (`app.rb:144-159`)  
  Novas transações recebem por padrão `status: Pendente`
- **Ler**: `GET /` (lista principal com filtros de período `start_date`/`end_date`)
- **Atualizar**: `PATCH /transactions/:id` (`app.rb:170-185`)  
  Preserva campos não especificados (atualiza apenas parâmetros fornecidos)
- **Excluir**: `DELETE /transactions/:id` (`app.rb:187-190`)

### 4.2 Tipos de Transação
| Tipo | Descrição | Campos Obrigatórios |
|------|-------------|-----------------|
| `Gasto` | Despesa | `category`, `payment_method` |
| `Salário Mensal` | Salário mensal | - |
| `Ganho Extra` | Renda extra | - |
| `Financiamento` | Financiamento | `financing_type`, `installments`, `due_date`, `bank`/`card_name` |
| `Crédito Parcelado` | Crédito parcelado | `financing_type`, `installments`, `due_date`, `bank`/`card_name` |
| `Pix Parcelado` | Pix parcelado | `financing_type`, `installments`, `due_date`, `bank`/`card_name` |

### 4.3 Lógica de Parcelamento
- Parcelas > 1 são divididas em parcelas individuais no dashboard
- **Datas de vencimento das parcelas**: `due_date + (i-1)*30` dias (i = número da parcela, intervalos de 30 dias)
- **Status individual das parcelas**: Controlado via array `paid_installments` (contém números das parcelas pagas)
- **Alternar pagamento de parcela**: `POST /transactions/:id/toggle_installment` (`app.rb:161-177`)  
  Adiciona/remove número da parcela no array `paid_installments` (não afeta outras parcelas)

### 4.4 Gerenciamento de Status
- **Status Geral da Transação**: `Pago`/`Pendente` (alterna via `POST /transactions/:id/toggle_status`)
- **Colunas de Status no Dashboard**:
  - `📌 Pendente`: Status de pagamento individual da parcela (verde = Pago, amarelo = Pendente)
  - `📊 Vencimento`: Status da data de vencimento (vermelho = Vencida, amarelo = Vence hoje, verde = Em dia, cinza = Sem vencimento)

### 4.5 Filtros e Exportação
- **Filtro por Data**: Página principal (`GET /`) filtra transações por `start_date` e `end_date`
- **Exportação Excel** (`GET /export`):
  - Nome do arquivo: `transacoes_DDMMAAAA_seq.xlsx` (ex.: `transacoes_06052026_1.xlsx`)
  - Contador de exportação (`export_seq`) incrementado a cada exportação
  - 14 colunas: ID, Data, Descrição, Valor, Tipo, Categoria, Método de Pagamento, Tipo de Financiamento, Parcelas, Vencimento, Banco/Cartão, Status, Data de Criação, Data de Atualização
  - Timestamps formatados como `dd/mm/yyyy hh:mm:ss`

### 4.6 Dashboard (`GET /dashboard`)
- **Estatísticas**: Total Pago, Total Restante, Total Geral
- **Visualização**: Gráfico de rosca (Chart.js) mostrando valores pagos vs restantes
- **Lista Detalhada de Dívidas**: Detalhamento parcela a parcela com botões de alternância para status de pagamento individual
- **Cálculo de Vencimento**: Compara data de vencimento da parcela com `Date.today` para definir status

---

## 5. Documentação das Rotas
| Método | Caminho | Descrição | Parâmetros Principais |
|--------|------|-------------|------------|
| GET | `/` | Lista principal de transações | `start_date`, `end_date` |
| GET | `/new` | Formulário de nova transação | - |
| POST | `/transactions` | Criar transação | Todos os campos da transação |
| GET | `/transactions/:id/edit` | Formulário de edição | `id` |
| PATCH | `/transactions/:id` | Atualizar transação | `id`, campos atualizados |
| DELETE | `/transactions/:id` | Excluir transação | `id` |
| GET | `/dashboard` | Dashboard de dívidas | - |
| GET | `/export` | Exportar para Excel | `start_date`, `end_date` |
| POST | `/transactions/:id/toggle_status` | Alternar status da transação | `id` |
| POST | `/transactions/:id/toggle_installment` | Alternar pagamento de parcela | `id`, `installment` (número da parcela) |

---

## 6. Métodos Helpers (`app.rb:21-66`)
| Método | Descrição |
|--------|-------------|
| `format_currency(value)` | Formata float como BRL (ex.: `100.5` → `R$ 100,50`) |
| `parse_currency(value)` | Converte string BRL para float (ex.: `R$ 100,50` → `100.5`) |
| `normalize_date(d)` | Normaliza entrada de data (trata nil, strings, objetos Date) |
| `get_all_transactions()` | Retorna todas as transações ordenadas por data (decrescente) |
| `get_transaction(id)` | Retorna uma transação pelo ID |
| `save_transaction(data)` | Cria nova transação |
| `update_transaction(id, data)` | Atualiza transação existente |

---

## 7. Escalabilidade e Workflow Ágil
### 7.1 Limitações Atuais
- PStore não é adequado para cenários multi-usuário ou alta concorrência
- Arquitetura em arquivo único (`app.rb`) complica manutenção conforme funcionalidades crescem
- Sem testes automatizados (verificação manual apenas)
- Sem autenticação de usuário (apenas usuário único)

### 7.2 Roteiro de Escalabilidade
1. **Migração de Banco de Dados**: Substituir PStore por SQLite/PostgreSQL para melhor concorrência e consultas
2. **Refatoração de Código**: Separar models, controllers e helpers em arquivos modulares
3. **Testes**: Adicionar RSpec/Minitest para testes unitários/integração
4. **Separação de Frontend**: Dividir em API backend + frontend React/Vue para melhor escalabilidade
5. **Autenticação**: Adicionar contas de usuário para suporte multi-usuário
6. **Cache**: Implementar Redis para estatísticas de dashboard acessadas frequentemente

### 7.3 Práticas Ágeis
- **Desenvolvimento Iterativo**: Funcionalidades adicionadas em pequenos incrementos testáveis (ex.: flags de status → controle individual de parcelas)
- **Atualizações Centradas no Usuário**: Funcionalidades priorizadas baseadas no feedback do usuário (ex.: alternância individual de parcelas adicionada após feedback)
- **Migrações Seguras**: PStore é backupado para `db/transactions.pstore.backup` antes de mudanças de schema
- **Validação de Sintaxe**: Todas as alterações verificadas com `ruby -c app.rb` antes da implantação
- **Documentação**: Documentação técnica atualizada junto com mudanças de código

---

## 8. Estrutura de Arquivos
```
C:\ControleFinanceiroApp\
├── app.rb                         # Aplicação principal (rotas, lógica, helpers)
├── config.ru                      # Configuração Rack
├── Gemfile                        # Dependências
├── Gemfile.lock
├── DOCUMENTACAO_TECNICA.md        # Esta documentação
├── db\
│   ├── transactions.pstore        # Banco de dados PStore
│   └── transactions.pstore.backup # Backup
├── views\
│   ├── layout.erb                 # Layout HTML com Bootstrap
│   ├── index.erb                  # Lista principal de transações
│   ├── new.erb                    # Formulário nova transação
│   ├── edit.erb                   # Formulário edição
│   ├── dashboard.erb              # Dashboard de dívidas
│   └── (views legadas)            # Versões antigas de templates
├── public\                        # Assets estáticos
└── tmp\                           # Arquivos temporários
```

---

## 9. Notas de Implantação
- Iniciar servidor: `ruby app.rb` (padrão `http://localhost:4567`)
- Reinicialização necessária após mudanças de código (sem hot-reload)
- Permissões do arquivo PStore: Garantir que o diretório `db/` tenha permissão de escrita
