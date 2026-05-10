# Technical Documentation - ControleFinanceiroApp

## 1. Project Overview
**Purpose**: Personal finance control application for tracking income, expenses, and installment payments.  
**Tech Stack**: Ruby 3.2, Sinatra 3.2, PStore (persistence), ERB (views), Bootstrap 5.3 (frontend), `write_xlsx` (Excel export), Chart.js (dashboard visualizations).  
**Current Scope**: Single-user, local deployment with iterative agile development.

---

## 2. Architecture
### 2.1 Data Layer
- **Database**: PStore (file-based transactional storage) at `db/transactions.pstore`
- **Limitations**: Single-threaded, no multi-user support, suitable for low-concurrency local use
- **Startup Migrations** (`app.rb:14-28`): Automatically adds missing fields (`status`, `paid_installments`) to existing transactions on application start.

### 2.2 Application Layer
- **Single-file architecture**: All routes, helpers, and business logic in `app.rb`
- **Views**: ERB templates in `views/` directory with Bootstrap 5.3 styling
- **Static Assets**: `public/` directory for CSS/JS

---

## 3. Data Model
### 3.1 Transaction Attributes
| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `id` | Integer | Auto-incrementing unique identifier | `DB[:next_id]` |
| `transaction_date` | Date | Transaction date | Required |
| `description` | String | Transaction description | Required |
| `amount` | Float | Amount in BRL | Required |
| `transaction_type` | String | Transaction category | Required |
| `category` | String | Expense category (only for `Gasto` type) | Optional |
| `payment_method` | String | Payment method | Optional |
| `financing_type` | String | `cartao`/`financiamento`/`pix` | Optional |
| `installments` | Integer | Number of installments (1-120) | Optional |
| `due_date` | Date | Due date for financing | Optional |
| `bank` | String | Bank/card issuer | Optional |
| `card_name` | String | Custom card/bank name | Optional |
| `status` | String | Overall transaction status (`Pago`/`Pendente`) | `Pendente` |
| `paid_installments` | Array | List of paid installment numbers (e.g., `[1,3]`) | `[]` |
| `created_at` | Time | Creation timestamp | `Time.now` |
| `updated_at` | Time | Last update timestamp | `Time.now` |

---

## 4. Features & Business Rules
### 4.1 Transaction Management (CRUD)
- **Create**: `POST /transactions` (`app.rb:144-159`)  
  New transactions default to `status: Pendente`
- **Read**: `GET /` (main list with date range filters `start_date`/`end_date`)
- **Update**: `PATCH /transactions/:id` (`app.rb:170-185`)  
  Preserves unspecified fields (only updates provided params)
- **Delete**: `DELETE /transactions/:id` (`app.rb:187-190`)

### 4.2 Transaction Types
| Type | Description | Required Fields |
|------|-------------|-----------------|
| `Gasto` | Expense | `category`, `payment_method` |
| `Salário Mensal` | Monthly salary | - |
| `Ganho Extra` | Extra income | - |
| `Financiamento` | Financing | `financing_type`, `installments`, `due_date`, `bank`/`card_name` |
| `Crédito Parcelado` | Installment credit | `financing_type`, `installments`, `due_date`, `bank`/`card_name` |
| `Pix Parcelado` | Installment Pix | `financing_type`, `installments`, `due_date`, `bank`/`card_name` |

### 4.3 Installment Logic
- Installments > 1 are split into individual parcels in the dashboard
- **Parcel due dates**: `due_date + (i-1)*30` days (i = parcel number, 30-day intervals)
- **Individual parcel status**: Tracked via `paid_installments` array (contains paid parcel numbers)
- **Toggle parcel payment**: `POST /transactions/:id/toggle_installment` (`app.rb:161-177`)  
  Adds/removes parcel number from `paid_installments` array (does not affect other parcels)

### 4.4 Status Management
- **Overall Transaction Status**: `Pago`/`Pendente` (toggle via `POST /transactions/:id/toggle_status`)
- **Dashboard Status Columns**:
  - `📌 Pendente`: Individual parcel payment status (green = Pago, yellow = Pendente)
  - `📊 Vencimento`: Due date status (red = Vencida, yellow = Vence hoje, green = Em dia, gray = Sem vencimento)

### 4.5 Filtering & Export
- **Date Filtering**: Main page (`GET /`) filters transactions by `start_date` and `end_date`
- **Excel Export** (`GET /export`):
  - Filename: `transacoes_DDMMAAAA_seq.xlsx` (e.g., `transacoes_06052026_5.xlsx`)
  - 14 columns: ID, Data, Descrição, Valor, Tipo, Categoria, Método de Pagamento, Tipo de Financiamento, Parcelas, Vencimento, Banco/Cartão, Status, Data de Criação, Data de Atualização
  - Timestamps formatted as `dd/mm/yyyy hh:mm:ss`

### 4.6 Dashboard (`GET /dashboard`)
- **Stats**: Total Pago, Total Restante, Total Geral
- **Visualization**: Doughnut chart (Chart.js) showing paid vs remaining amounts
- **Detailed Debt List**: Parcel-by-parcel breakdown with toggle buttons for individual payment status
- **Due Date Calculation**: Compares parcel due date to `Date.today` for status

---

## 5. Routes Documentation
| Method | Path | Description | Key Params |
|--------|------|-------------|------------|
| GET | `/` | Main transaction list | `start_date`, `end_date` |
| GET | `/new` | New transaction form | - |
| POST | `/transactions` | Create transaction | All transaction fields |
| GET | `/transactions/:id/edit` | Edit transaction form | `id` |
| PATCH | `/transactions/:id` | Update transaction | `id`, updated fields |
| DELETE | `/transactions/:id` | Delete transaction | `id` |
| GET | `/dashboard` | Debt dashboard | - |
| GET | `/export` | Export to Excel | `start_date`, `end_date` |
| POST | `/transactions/:id/toggle_status` | Toggle transaction status | `id` |
| POST | `/transactions/:id/toggle_installment` | Toggle parcel payment | `id`, `installment` (parcel number) |

---

## 6. Helper Methods (`app.rb:21-66`)
| Method | Description |
|--------|-------------|
| `format_currency(value)` | Formats float as BRL (e.g., `100.5` → `R$ 100,50`) |
| `parse_currency(value)` | Parses BRL string to float (e.g., `R$ 100,50` → `100.5`) |
| `normalize_date(d)` | Normalizes date input (handles nil, strings, Date objects) |
| `get_all_transactions()` | Returns all transactions sorted by date (descending) |
| `get_transaction(id)` | Returns single transaction by ID |
| `save_transaction(data)` | Creates new transaction |
| `update_transaction(id, data)` | Updates existing transaction |

---

## 7. Scalability & Agile Workflow
### 7.1 Current Limitations
- PStore is not suitable for multi-user or high-concurrency scenarios
- Single-file architecture (`app.rb`) complicates maintenance as features grow
- No automated testing (manual verification only)
- No user authentication (single-user only)

### 7.2 Scalability Roadmap
1. **Database Migration**: Replace PStore with SQLite/PostgreSQL for better concurrency and querying
2. **Code Refactoring**: Separate models, controllers, and helpers into modular files
3. **Testing**: Add RSpec/minitest for unit/integration tests
4. **Frontend Separation**: Split into API backend + React/Vue frontend for better scalability
5. **Authentication**: Add user accounts for multi-user support
6. **Caching**: Implement Redis for frequently accessed dashboard stats

### 7.3 Agile Practices
- **Iterative Development**: Features are added in small, testable increments (e.g., status flags → individual parcel handling)
- **User-Centric Updates**: Features prioritized based on user feedback (e.g., individual parcel toggles added post-feedback)
- **Safe Migrations**: PStore is backed up to `db/transactions.pstore.backup` before schema changes
- **Syntax Validation**: All changes verified with `ruby -c app.rb` before deployment
- **Documentation**: Technical docs updated alongside code changes

---

## 8. File Structure
```
C:\ControleFinanceiroApp\
├── app.rb                    # Main application (routes, logic, helpers)
├── config.ru                 # Rack configuration
├── Gemfile                   # Dependencies
├── Gemfile.lock
├── TECHNICAL_DOCS.md         # This documentation
├── db\
│   ├── transactions.pstore   # PStore database
│   └── transactions.pstore.backup  # Backup
├── views\
│   ├── layout.erb            # HTML layout with Bootstrap
│   ├── index.erb             # Main transaction list
│   ├── new.erb               # New transaction form
│   ├── edit.erb              # Edit transaction form
│   ├── dashboard.erb         # Debt dashboard
│   └── (legacy views)        # Older template versions
├── public\                   # Static assets
└── tmp\                      # Temporary files
```

---

## 9. Deployment Notes
- Start server: `ruby app.rb` (defaults to `http://localhost:4567`)
- Restart required after code changes (no hot-reload)
- PStore file permissions: Ensure `db/` directory is writable
