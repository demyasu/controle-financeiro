require 'sinatra'
require 'dotenv/load'
require 'pstore'
require 'date'
require 'write_xlsx'
require 'tempfile'
require 'fileutils'
require 'set'
require 'openssl'
require 'base64'
require 'securerandom'
require 'rack/protection/encrypted_cookie'
require 'net/smtp'

# ─── SMTP CONFIG ──────────────────────────────────────
SMTP_CONFIG = {
  server:   ENV['SMTP_SERVER']   || 'smtp.office365.com',
  port:     (ENV['SMTP_PORT']    || 587).to_i,
  domain:   ENV['SMTP_DOMAIN']   || 'localhost',
  username: ENV['SMTP_USERNAME'],
  password: ENV['SMTP_PASSWORD'],
  from:     ENV['SMTP_FROM']     || ENV['SMTP_USERNAME'],
  from_name: ENV['SMTP_FROM_NAME'] || 'Controle Financeiro'
}

def send_email(to:, subject:, body:)
  unless SMTP_CONFIG[:username] && SMTP_CONFIG[:password]
    puts "[EMAIL] SMTP não configurado. Para: #{to}, Assunto: #{subject}"
    puts "[EMAIL] Link (dev): #{body[/https?:\/\/[^\s<]+/]}" if body
    return
  end

  msg = <<~EMail
    From: #{SMTP_CONFIG[:from_name]} <#{SMTP_CONFIG[:from]}>
    To: #{to}
    Subject: #{subject}
    MIME-Version: 1.0
    Content-Type: text/html; charset=UTF-8

    #{body}
  EMail

  smtp = Net::SMTP.new(SMTP_CONFIG[:server], SMTP_CONFIG[:port])
  smtp.enable_ssl if SMTP_CONFIG[:port] == 465
  smtp.start(SMTP_CONFIG[:domain], SMTP_CONFIG[:username], SMTP_CONFIG[:password], :login) do |s|
    s.send_message(msg, SMTP_CONFIG[:from], to)
  end
  puts "[EMAIL] Enviado para #{to}: #{subject}"
rescue => e
  puts "[EMAIL] ERRO ao enviar para #{to}: #{e.message}"
  puts "[EMAIL] Fallback - código/link disponível no console"
  puts "[EMAIL] Link: #{body[/https?:\/\/[^\s<]+/]}" if body && body.include?('http')
end

enable :method_override
disable :sessions
use Rack::Protection::EncryptedCookie, secret: (ENV['SESSION_SECRET'] || SecureRandom.hex(32)), old_secret: nil

# PStore database
DB = PStore.new('db/transactions.pstore')

# Initialize DB
unless File.exist?('db/transactions.pstore')
  DB.transaction do
    DB[:transactions] = {}
    DB[:next_id] = 1
    DB[:export_seq] = 0
  end
end

# Migrate: ensure user_email on all transactions
DB.transaction do
  transactions = DB[:transactions] || {}
  updated = false
  transactions.each do |id, t|
    if t.is_a?(Hash)
      unless t.key?(:paid_installments)
        t[:paid_installments] = []
        t[:status] = 'Pendente' unless t.key?(:status)
        updated = true
      end
      unless t.key?(:user_email)
        t[:user_email] = 'pcyasuic@ideiasti.com'
        updated = true
      end
    end
  end
  DB[:export_seq] = 0 unless DB[:export_seq]
  DB[:transactions] = transactions if updated
end

# Ensure admin user exists
ADMIN_EMAIL = 'pcyasuic@ideiasti.com'
DB.transaction do
  users = DB[:users] || {}
  if users[ADMIN_EMAIL]
    users[ADMIN_EMAIL][:admin] = true
  else
    require 'securerandom'
    require 'openssl'
    require 'base64'
    salt = SecureRandom.hex(16)
    iter = 100_000
    key_len = 32
    default_hash = OpenSSL::PKCS5.pbkdf2_hmac('admin123', salt, iter, key_len, 'SHA256')
    users[ADMIN_EMAIL] = {
      id: SecureRandom.uuid, username: 'Admin',
      email: ADMIN_EMAIL, admin: true,
      password_hash: "#{salt}:#{iter}:#{Base64.strict_encode64(default_hash)}",
      created_at: Time.now
    }
  end
  DB[:users] = users
end

# Helper methods
def format_currency(value)
  return 'R$ 0,00' if value.nil? || value == 0
  "R$ #{format('%.2f', value).gsub('.', ',')}"
end

def parse_currency(value)
  return 0 if value.nil? || value.empty?
  value.gsub('R$', '').gsub('.', '').gsub(',', '.').to_f
end

def normalize_date(d)
  return Date.new(1900, 1, 1) if d.nil?
  return d if d.is_a?(Date)
  if d.is_a?(String) && !d.empty?
    begin
      Date.parse(d)
    rescue
      Date.new(1900, 1, 1)
    end
  else
    Date.new(1900, 1, 1)
  end
end

def current_user_email
  session[:user_email]
end

def admin?
  user = DB.transaction(true) { DB[:users][session[:user_email]] }
  user && user[:admin]
end

def get_user_transactions(user_email = nil)
  all = get_all_transactions
  return all if user_email.nil?
  all.select { |t| t[:user_email] == user_email }
end

def get_my_transactions
  get_user_transactions(current_user_email)
end

def get_all_users
  DB.transaction(true) do
    users = DB[:users] || {}
    users.values.sort_by { |u| u[:created_at] || Time.now }
  end
end

def get_all_transactions
  DB.transaction(true) do
    transactions = DB[:transactions] || {}
    result = []
    transactions.each do |id, t|
      next unless t.is_a?(Hash)
      t[:status] = 'Pendente' unless t.key?(:status)
      t[:id] = id unless t.key?(:id)
      result << t
    end
    result.sort do |a, b|
      begin
        date_a = normalize_date(a[:transaction_date])
        date_b = normalize_date(b[:transaction_date])
        date_b <=> date_a
      rescue
        (a[:id] || 0) <=> (b[:id] || 0)
      end
    end
  end
end

def get_transaction(id)
  DB.transaction(true) do
    transactions = DB[:transactions] || {}
    transactions[id]
  end
end

def save_transaction(data)
  DB.transaction do
    transactions = DB[:transactions] || {}
    next_id = DB[:next_id] || 1

    transaction = {
      id: next_id,
      transaction_date: data[:transaction_date],
      description: data[:description],
      amount: data[:amount],
      transaction_type: data[:transaction_type],
      category: data[:category],
      payment_method: data[:payment_method],
      financing_type: data[:financing_type],
      installments: data[:installments],
      due_date: data[:due_date],
      bank: data[:bank],
      card_name: data[:card_name],
      status: data[:status] || 'Pendente',
      user_email: data[:user_email] || current_user_email,
      paid_installments: [],
      created_at: Time.now,
      updated_at: Time.now
    }

    transactions[next_id] = transaction
    DB[:transactions] = transactions
    DB[:next_id] = next_id + 1
    transaction
  end
end

def update_transaction(id, data)
  DB.transaction do
    transactions = DB[:transactions] || {}
    if transactions[id]
      transactions[id][:transaction_date] = data[:transaction_date] if data.key?(:transaction_date)
      transactions[id][:description] = data[:description] if data.key?(:description)
      transactions[id][:amount] = data[:amount] if data.key?(:amount)
      transactions[id][:transaction_type] = data[:transaction_type] if data.key?(:transaction_type)
      transactions[id][:category] = data[:category] if data.key?(:category)
      transactions[id][:payment_method] = data[:payment_method] if data.key?(:payment_method)
      transactions[id][:financing_type] = data[:financing_type] if data.key?(:financing_type)
      transactions[id][:installments] = data[:installments] if data.key?(:installments)
      transactions[id][:due_date] = data[:due_date] if data.key?(:due_date)
      transactions[id][:bank] = data[:bank] if data.key?(:bank)
      transactions[id][:card_name] = data[:card_name] if data.key?(:card_name)
      transactions[id][:status] = data[:status] if data.key?(:status)
      transactions[id][:income_type] = data[:income_type] if data.key?(:income_type)
      transactions[id][:updated_at] = Time.now
      DB[:transactions] = transactions
    end
    transactions[id]
  end
end

def delete_transaction(id)
  DB.transaction do
    transactions = DB[:transactions] || {}
    transactions.delete(id)
    DB[:transactions] = transactions
  end
end

# ─── AUTH HELPERS ───────────────────────────────────
def hash_password(password)
  salt = SecureRandom.hex(16)
  iter = 100_000
  key_len = 32
  hash = OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iter, key_len, 'SHA256')
  "#{salt}:#{iter}:#{Base64.strict_encode64(hash)}"
end

def verify_password(password, stored)
  salt, iter, stored_hash = stored.split(':', 3)
  iter = iter.to_i
  key_len = 32
  hash = OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iter, key_len, 'SHA256')
  Base64.strict_encode64(hash) == stored_hash
end

def generate_token
  SecureRandom.hex(32)
end

def generate_code
  format('%06d', rand(1_000_000))
end

# Initialize auth data
DB.transaction do
  DB[:users] ||= {}
  DB[:reg_tokens] ||= {}
  DB[:login_tokens] ||= {}
end

# ─── BEFORE FILTERS ────────────────────────────────
before do
  @notice = session.delete(:notice) if session[:notice]
  @error = session.delete(:error) if session[:error]
end

before do
  pass if ['/login', '/register', '/verify', '/authenticate', '/verify_token', '/logout'].include?(request.path)
  pass if request.path =~ %r{^/register/[^/]+$}
  pass if session[:user_email]
  redirect '/login'
end

# ─── AUTH ROUTES ────────────────────────────────────
get '/login' do
  redirect '/' if session[:user_email]
  erb :login
end

post '/authenticate' do
  email = params[:email].to_s.strip.downcase
  password = params[:password].to_s
  user = DB.transaction(true) { DB[:users][email] }
  unless user && verify_password(password, user[:password_hash])
    @error = 'Email ou senha inválidos'
    return erb :login
  end
  code = generate_code
  token = generate_token
  DB.transaction do
    DB[:login_tokens][token] = { email: email, code: code, created_at: Time.now, used: false }
  end
  send_email(
    to: email,
    subject: 'Seu código de verificação',
    body: "<h2>Código de verificação</h2><p>Seu código é: <strong>#{code}</strong></p><p>Este código expira em 10 minutos.</p>"
  )
  session[:pending_token] = token
  @code = code
  @email = email
  @smtp_configured = SMTP_CONFIG[:username] && SMTP_CONFIG[:password]
  erb :verify_token
end

post '/verify_token' do
  redirect '/login' unless session[:pending_token]
  token_data = DB.transaction(true) { DB[:login_tokens][session[:pending_token]] }
  if token_data && !token_data[:used] && token_data[:code] == params[:code].to_s.strip
    DB.transaction { DB[:login_tokens][session[:pending_token]][:used] = true }
    session[:user_email] = token_data[:email]
    session.delete(:pending_token)
    session[:notice] = 'Login realizado com sucesso!'
    redirect '/'
  else
    @error = 'Código inválido ou expirado'
    erb :verify_token
  end
end

get '/register' do
  erb :register
end

post '/register' do
  email = params[:email].to_s.strip.downcase
  existing = DB.transaction(true) { DB[:users][email] }
  if existing
    @error = 'Este email já está cadastrado'
    return erb :register
  end
  token = generate_token
  DB.transaction do
    DB[:reg_tokens][token] = { email: email, created_at: Time.now, used: false }
  end
  reg_link = "#{request.base_url}/register/#{token}"
  send_email(
    to: email,
    subject: 'Confirme seu cadastro',
    body: "<h2>Cadastro no Controle Financeiro</h2><p>Clique no link abaixo para criar sua conta:</p><p><a href=\"#{reg_link}\">#{reg_link}</a></p><p>Este link expira em 24 horas.</p>"
  )
  @dev_link = reg_link
  @email = email
  @smtp_configured = SMTP_CONFIG[:username] && SMTP_CONFIG[:password]
  erb :register_sent
end

get '/register/:token' do
  token_data = DB.transaction(true) { DB[:reg_tokens][params[:token]] }
  if token_data.nil? || token_data[:used]
    @error = 'Link inválido ou expirado'
    return erb :register
  end
  @token = params[:token]
  @email = token_data[:email]
  erb :set_password
end

post '/register/:token' do
  token_data = DB.transaction(true) { DB[:reg_tokens][params[:token]] }
  if token_data.nil? || token_data[:used]
    @error = 'Link inválido ou expirado'
    return erb :register
  end
  username = params[:username].to_s.strip
  password = params[:password].to_s
  confirm = params[:confirm_password].to_s
  if username.empty?
    @error = 'Nome de usuário é obrigatório'; @token = params[:token]; @email = token_data[:email]
    return erb :set_password
  end
  if password.length < 6
    @error = 'Senha deve ter no mínimo 6 caracteres'; @token = params[:token]; @email = token_data[:email]
    return erb :set_password
  end
  if password != confirm
    @error = 'Senhas não conferem'; @token = params[:token]; @email = token_data[:email]
    return erb :set_password
  end
  pwd_hash = hash_password(password)
  DB.transaction do
    DB[:reg_tokens][params[:token]][:used] = true
    DB[:users][token_data[:email]] = {
      id: SecureRandom.uuid, username: username, email: token_data[:email],
      password_hash: pwd_hash, created_at: Time.now
    }
  end
  session[:notice] = 'Conta criada com sucesso! Faça seu login.'
  redirect '/login'
end

get '/logout' do
  session.clear
  redirect '/login'
end

# ─── ROUTES ─────────────────────────────────────────
post '/transactions/:id/toggle_installment' do
  DB.transaction do
    transactions = DB[:transactions] || {}
    id = params[:id].to_i
    t = transactions[id]
    next unless t && (t[:user_email] == current_user_email || admin?)
    installment = params[:installment].to_i
    paid = t[:paid_installments] || []
    if paid.include?(installment)
      paid.delete(installment)
    else
      paid << installment
    end
    t[:paid_installments] = paid
    t[:updated_at] = Time.now
    DB[:transactions] = transactions
  end
  redirect back
end

post '/transactions/:id/toggle_status' do
  DB.transaction do
    transactions = DB[:transactions] || {}
    id = params[:id].to_i
    t = transactions[id]
    next unless t && (t[:user_email] == current_user_email || admin?)
    t[:status] = t[:status] == 'Pago' ? 'Pendente' : 'Pago'
    t[:updated_at] = Time.now
    DB[:transactions] = transactions
  end
  redirect back
end

get '/' do
  @notice = case params[:notice]
            when 'created' then 'Transação criada com sucesso!'
            when 'updated' then 'Transação atualizada com sucesso!'
            when 'deleted' then 'Transação excluída com sucesso!'
            end
  @transactions = if admin? && params[:user] && !params[:user].empty?
    get_user_transactions(params[:user])
  else
    get_my_transactions
  end

  @start_date = if params[:start_date] && !params[:start_date].empty?
    Date.parse(params[:start_date])
  else
    Date.new(Date.today.year, Date.today.month, 1)
  end

  @end_date = if params[:end_date] && !params[:end_date].empty?
    Date.parse(params[:end_date])
  else
    Date.new(Date.today.year, Date.today.month, -1)
  end

  if params[:start_date] && params[:end_date]
    date_range = (@start_date..@end_date)
    @transactions = @transactions.select { |t| date_range.include?(t[:transaction_date]) }
  end

  @total_gastos = @transactions.select { |t| ['Gasto', 'Financiamento', 'Crédito Parcelado', 'Pix Parcelado'].include?(t[:transaction_type]) }.sum { |t| t[:amount] }
  @total_creditos = @transactions.select { |t| ['Salário Mensal', 'Ganho Extra'].include?(t[:transaction_type]) }.sum { |t| t[:amount] }
  @balanco = @total_creditos - @total_gastos

  @all_users = get_all_users if admin?
  @selected_user = params[:user]

  erb :index
end

get '/new' do
  erb :new
end

def can_modify?(t)
  t && (t[:user_email] == current_user_email || admin?)
end

post '/transactions' do
  save_transaction(
    transaction_date: Date.parse(params[:transaction_date]),
    description: params[:description],
    amount: parse_currency(params[:amount]),
    transaction_type: params[:transaction_type],
    category: params[:category],
    payment_method: params[:payment_method],
    financing_type: params[:financing_type],
    installments: params[:installments] && !params[:installments].empty? ? params[:installments].to_i : nil,
    due_date: params[:due_date] && !params[:due_date].empty? ? Date.parse(params[:due_date]) : nil,
    bank: params[:bank],
    card_name: params[:card_name],
    status: params[:status],
    user_email: current_user_email
  )
  redirect '/?notice=created'
end

get '/transactions/:id/edit' do
  @transaction = get_transaction(params[:id].to_i)
  unless can_modify?(@transaction)
    redirect '/'
  else
    erb :edit
  end
end

patch '/transactions/:id' do
  t = get_transaction(params[:id].to_i)
  unless can_modify?(t)
    redirect '/'
  end
  update_transaction(params[:id].to_i,
    transaction_date: Date.parse(params[:transaction_date]),
    description: params[:description],
    amount: parse_currency(params[:amount]),
    transaction_type: params[:transaction_type],
    category: params[:category],
    payment_method: params[:payment_method],
    financing_type: params[:financing_type],
    installments: params[:installments] && !params[:installments].empty? ? params[:installments].to_i : nil,
    due_date: params[:due_date] && !params[:due_date].empty? ? Date.parse(params[:due_date]) : nil,
    bank: params[:bank],
    card_name: params[:card_name],
    status: params[:status]
  )
  redirect '/?notice=updated'
end

delete '/transactions/:id' do
  t = get_transaction(params[:id].to_i)
  if can_modify?(t)
    delete_transaction(params[:id].to_i)
  end
  redirect '/?notice=deleted'
end

get '/dashboard' do
  @transactions = if admin? && params[:user] && !params[:user].empty?
    get_user_transactions(params[:user])
  else
    get_my_transactions
  end
  @all_users = get_all_users if admin?
  @selected_user = params[:user]
  @debts = @transactions.select do |t|
    (t[:transaction_type] == 'Gasto' && t[:category] == 'Financiamento') ||
    ['Financiamento', 'Crédito Parcelado', 'Pix Parcelado', 'Crédito à Vista'].include?(t[:transaction_type])
  end
  
  @upcoming = []
  @total_paid = 0.0
  @total_remaining = 0.0
  today = Date.today
  
  @debts.each do |debt|
    amount = debt[:amount].to_f
    paid_installments = debt[:paid_installments] || []
    if debt[:installments] && debt[:installments] > 1 && debt[:due_date]
      parcel_value = amount / debt[:installments].to_f
      (1..debt[:installments]).each do |i|
        due = debt[:due_date] + (i-1)*30
        is_paid = paid_installments.include?(i)
        if is_paid
          @total_paid += parcel_value
        else
          @total_remaining += parcel_value
        end
        @upcoming << {
          id: debt[:id],
          description: "#{debt[:description]} (Parcela #{i} de #{debt[:installments]})",
          amount: parcel_value,
          due_date: due,
          bank: debt[:bank],
          card_name: debt[:card_name],
          financing_type: debt[:financing_type],
          category: debt[:category],
          installments: debt[:installments],
          current_installment: i,
          is_paid: is_paid,
          vencimento_status: due < today ? 'Vencida' : (due == today ? 'Vence hoje' : 'Em dia')
        }
      end
    elsif debt[:due_date]
      is_paid = paid_installments.include?(1)
      if debt[:due_date] < today
        @total_paid += amount if is_paid
      else
        @total_remaining += amount unless is_paid
      end
      @upcoming << debt.merge(
        current_installment: 1,
        installments: 1,
        is_paid: is_paid,
        vencimento_status: (debt[:due_date] < today ? 'Vencida' : (debt[:due_date] == today ? 'Vence hoje' : 'Em dia'))
      )
    else
      is_paid = paid_installments.include?(1)
      @total_remaining += amount unless is_paid
      @upcoming << debt.merge(
        due_date: nil,
        is_paid: is_paid,
        vencimento_status: 'Sem vencimento',
        current_installment: 1,
        installments: 1
      )
    end
  end
  
  @upcoming.sort_by! do |d|
    normalize_date(d[:due_date])
  end
  erb :dashboard
end

get '/export' do
  @transactions = admin? ? get_all_transactions : get_my_transactions

  if params[:start_date] && params[:end_date] && !params[:start_date].empty? && !params[:end_date].empty?
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])
    date_range = (start_date..end_date)
    @transactions = @transactions.select { |t| date_range.include?(t[:transaction_date]) }
  end

  # Gerar XLSX
  tempfile = Tempfile.new(['transacoes', '.xlsx'])
  tempfile.close  # Close the file handle to avoid permission issues
  workbook = WriteXLSX.new(tempfile.path)
  
  # Aba principal
  worksheet = workbook.add_worksheet('Transações')

  # Formatação
  header_format = workbook.add_format(
    bg_color: '#4472C4',
    color: 'white',
    bold: true,
    align: 'center',
    border: 1,
    border_color: '#000000'
  )
  data_format = workbook.add_format(
    align: 'left'
  )
  currency_format = workbook.add_format(
    align: 'right',
    num_format: 'R$ #,##0.00'
  )
  date_format = workbook.add_format(
    align: 'center',
    num_format: 'dd/mm/yyyy'
  )
  datetime_format = workbook.add_format(
    align: 'center',
    num_format: 'dd/mm/yyyy hh:mm:ss'
  )

  # Configurar impressão
  worksheet.print_area('A1:O' + (@transactions.size + 5).to_s)
  worksheet.fit_to_pages(1, 0)
  worksheet.set_margins(0.5)
  worksheet.hide_gridlines(0)  # Show gridlines

  # Cabeçalho principal
  title_format = workbook.add_format(
    bold: true,
    size: 18,
    align: 'center',
    bg_color: '#4472C4',
    color: 'white',
    border: 2,
    border_color: '#000000'
  )
  worksheet.merge_range('A1:O1', '🍀 PcYasuic Soluções Financeira', title_format)
  worksheet.set_row(0, 30)

  # Cabeçalhos das colunas
  headers = ['ID', 'Data', 'Descrição', 'Valor Total', 'Valor Parcela', 'Tipo', 'Categoria', 'Método de Pagamento', 'Tipo de Financiamento', 'Parcelas', 'Vencimento', 'Banco/Cartão', 'Status', 'Data de Criação', 'Data de Atualização']
  headers.each_with_index do |header, index|
    worksheet.write(1, index, header, header_format)
  end
  worksheet.set_row(1, 20)

  # Filtros
  worksheet.autofilter('A2:O' + (@transactions.size + 2).to_s)

  # Dados
  total_gastos = 0.0
  total_creditos = 0.0
  seen_ids = Set.new
  row = 2

  @transactions.each do |transaction|
    installment_count = transaction[:installments].to_i > 1 ? transaction[:installments].to_i : 1
    parcel_value = installment_count > 1 ? (transaction[:amount].to_f / installment_count).round(2) : transaction[:amount]

    (1..installment_count).each do |i|
      due_date = if installment_count > 1 && transaction[:due_date]
        transaction[:due_date] + (i - 1) * 30
      else
        transaction[:due_date]
      end

      description = if installment_count > 1
        "#{transaction[:description]} (Parcela #{i} de #{installment_count})"
      else
        transaction[:description]
      end

      installment_text = installment_count > 1 ? "#{i} de #{installment_count}" : (transaction[:installments].to_i > 0 ? "1 de #{transaction[:installments]}" : '-')

      worksheet.write(row, 0, transaction[:id], data_format)
      worksheet.write(row, 1, transaction[:transaction_date], date_format)
      worksheet.write(row, 2, description, data_format)
      worksheet.write(row, 3, transaction[:amount], currency_format)
      worksheet.write(row, 4, parcel_value, currency_format)
      worksheet.write(row, 5, transaction[:transaction_type], data_format)
      worksheet.write(row, 6, transaction[:category], data_format)
      worksheet.write(row, 7, transaction[:payment_method], data_format)
      worksheet.write(row, 8, transaction[:financing_type] || '-', data_format)
      worksheet.write(row, 9, installment_text, data_format)
      worksheet.write(row, 10, due_date ? due_date : '-', due_date ? date_format : data_format)
      worksheet.write(row, 11, (transaction[:bank] || transaction[:card_name] || '-'), data_format)
      worksheet.write(row, 12, transaction[:status] || 'Pendente', data_format)
      worksheet.write(row, 13, transaction[:created_at] ? transaction[:created_at] : '-', transaction[:created_at] ? datetime_format : data_format)
      worksheet.write(row, 14, transaction[:updated_at] ? transaction[:updated_at] : '-', transaction[:updated_at] ? datetime_format : data_format)

      row += 1
    end

    unless seen_ids.include?(transaction[:id])
      seen_ids.add(transaction[:id])
      if ['Gasto', 'Financiamento', 'Crédito Parcelado', 'Pix Parcelado'].include?(transaction[:transaction_type])
        total_gastos += transaction[:amount]
      elsif ['Salário Mensal', 'Ganho Extra'].include?(transaction[:transaction_type])
        total_creditos += transaction[:amount]
      end
    end
  end

  # Linha de total
  total_row = row
  worksheet.write(total_row, 2, 'TOTAL GASTOS', header_format)
  worksheet.write(total_row, 3, total_gastos, currency_format)
  worksheet.write(total_row + 1, 2, 'TOTAL CRÉDITOS', header_format)
  worksheet.write(total_row + 1, 3, total_creditos, currency_format)
  worksheet.write(total_row + 2, 2, 'SALDO', header_format)
  worksheet.write(total_row + 2, 3, total_creditos - total_gastos, currency_format)

  # Ajustar largura das colunas
  worksheet.set_column('A:A', 5)
  worksheet.set_column('B:B', 12)
  worksheet.set_column('C:C', 30)
  worksheet.set_column('D:D', 15)
  worksheet.set_column('E:E', 15)
  worksheet.set_column('F:F', 20)
  worksheet.set_column('G:G', 15)
  worksheet.set_column('H:H', 20)
  worksheet.set_column('I:I', 20)
  worksheet.set_column('J:J', 10)
  worksheet.set_column('K:K', 12)
  worksheet.set_column('L:L', 20)
  worksheet.set_column('M:M', 10)
  worksheet.set_column('N:N', 20)
  worksheet.set_column('O:O', 20)

  # Aba de Resumo
  summary_sheet = workbook.add_worksheet('Resumo')
  summary_sheet.write(0, 0, 'Resumo Financeiro', title_format)
  summary_sheet.merge_range('A1:B1', 'Resumo Financeiro', title_format)
  summary_sheet.set_row(0, 30)
  
  summary_format = workbook.add_format(bold: true, align: 'left')
  summary_sheet.write(2, 0, 'Total Gastos:', summary_format)
  summary_sheet.write(2, 1, total_gastos, currency_format)
  summary_sheet.write(3, 0, 'Total Créditos:', summary_format)
  summary_sheet.write(3, 1, total_creditos, currency_format)
  summary_sheet.write(4, 0, 'Saldo:', summary_format)
  summary_sheet.write(4, 1, total_creditos - total_gastos, currency_format)
  
  summary_sheet.set_column('A:A', 20)
  summary_sheet.set_column('B:B', 15)

  workbook.close
  export_seq = DB.transaction do
    seq = DB[:export_seq] || 0
    seq += 1
    DB[:export_seq] = seq
    seq
  end
  filename = "transacoes_#{Date.today.strftime('%d%m%Y')}_#{export_seq}.xlsx"
  send_file tempfile.path, filename: filename, type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  File.delete(tempfile.path) rescue nil
end
