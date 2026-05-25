require 'minitest/autorun'
require 'rack/test'
require 'net/smtp'
require 'net/http'

SMTP_CONFIG = {
  server:   'smtp.sendgrid.net',
  port:     587,
  domain:   'localhost',
  username: 'apikey',
  password: nil,
  from:     'test@test.com',
  from_name: 'Controle Financeiro'
}

def smtp_configured?
  pass = SMTP_CONFIG[:password]
  pass && !pass.empty?
end

def send_email(to:, subject:, body:)
  unless smtp_configured?
    puts "[EMAIL] SMTP não configurado. Para: #{to}, Assunto: #{subject}"
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

  begin
    smtp = Net::SMTP.new(SMTP_CONFIG[:server], SMTP_CONFIG[:port])
    smtp.open_timeout = 15
    smtp.read_timeout = 30
    if SMTP_CONFIG[:port] == 465
      smtp.enable_ssl
    else
      smtp.enable_starttls
    end
    smtp.start(SMTP_CONFIG[:domain], SMTP_CONFIG[:username], SMTP_CONFIG[:password], :login) do |s|
      s.send_message(msg, SMTP_CONFIG[:from], to)
    end
    puts "[EMAIL] Enviado para #{to}: #{subject}"
    return
  rescue => e
    puts "[EMAIL] SMTP falhou para #{to}: #{e.message}"
    puts "[EMAIL] Tentando API SendGrid..."
  end

  send_email_via_api(to:, subject:, body:)
end

def send_email_via_api(to:, subject:, body:)
  api_key = SMTP_CONFIG[:password]
  unless api_key && !api_key.empty?
    puts "[EMAIL] API key não disponível para fallback"
    return
  end

  require 'net/http'
  require 'json'

  uri = URI('https://api.sendgrid.com/v3/mail/send')
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 15
  http.read_timeout = 30
  http.use_ssl = true

  payload = {
    personalizations: [{ to: [{ email: to }] }],
    from: { email: SMTP_CONFIG[:from], name: SMTP_CONFIG[:from_name] },
    subject: subject,
    content: [{ type: 'text/html', value: body }]
  }

  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{api_key}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(payload)

  response = http.request(request)

  if response.code.to_i.between?(200, 299)
    puts "[EMAIL] Enviado via API para #{to}: #{subject}"
  else
    puts "[EMAIL] ERRO ao enviar via API para #{to}: #{response.code} #{response.body}"
  end
rescue => e
  puts "[EMAIL] ERRO ao enviar para #{to}: #{e.message}"
  puts e.backtrace.first(3).join("\n") if e.backtrace
end

class AppForTestingEmailRoutes
  attr_reader :last_email_to, :last_email_subject, :last_email_body

  def forgot_password(email)
    reset_link = "http://test.com/reset/token123"
    if smtp_configured?
      send_email(
        to: email,
        subject: 'Redefinição de senha',
        body: "<h2>Redefinição de senha</h2><p>Clique no link abaixo para redefinir sua senha:</p><p><a href=\"#{reset_link}\">#{reset_link}</a></p>"
      )
      @last_email_to = email
      @last_email_subject = 'Redefinição de senha'
      @last_email_body = "<h2>Redefinição de senha</h2><p>Clique no link abaixo para redefinir sua senha:</p><p><a href=\"#{reset_link}\">#{reset_link}</a></p>"
    else
      send_email(to: email, subject: 'Redefinição de senha', body: '')
    end
  end

  def send_verification_code(email, code)
    send_email(
      to: email,
      subject: 'Seu código de verificação',
      body: "<h2>Código de verificação</h2><p>Seu código é: <strong>#{code}</strong></p>"
    )
    @last_email_to = email
    @last_email_subject = 'Seu código de verificação'
    @last_email_body = "<h2>Código de verificação</h2><p>Seu código é: <strong>#{code}</strong></p>"
  end

  def send_registration_link(email, token)
    reg_link = "http://test.com/register/#{token}"
    send_email(
      to: email,
      subject: 'Confirme seu cadastro',
      body: "<h2>Cadastro no Controle Financeiro</h2><p>Clique no link abaixo para criar sua conta:</p><p><a href=\"#{reg_link}\">#{reg_link}</a></p>"
    )
    @last_email_to = email
    @last_email_subject = 'Confirme seu cadastro'
    @last_email_body = "<h2>Cadastro no Controle Financeiro</h2><p>Clique no link abaixo para criar sua conta:</p><p><a href=\"#{reg_link}\">#{reg_link}</a></p>"
  end
end

class EmailRoutesIntegrationTest < Minitest::Test
  def setup
    SMTP_CONFIG[:password] = 'test-password'
    @app = AppForTestingEmailRoutes.new
  end

  def test_forgot_password_email
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; end
    def smtp_mock.start(*args); yield self; end
    def smtp_mock.send_message(*args); end

    Net::SMTP.stub(:new, smtp_mock) do
      out, _ = capture_io do
        @app.forgot_password('user@test.com')
      end
      assert out.include?('[EMAIL] Enviado para user@test.com: Redefinição de senha')
    end

    assert_equal 'user@test.com', @app.last_email_to
    assert_equal 'Redefinição de senha', @app.last_email_subject
    assert @app.last_email_body.include?('Clique no link abaixo')
  end

  def test_verification_code_email
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; end
    def smtp_mock.start(*args); yield self; end
    def smtp_mock.send_message(*args); end

    Net::SMTP.stub(:new, smtp_mock) do
      out, _ = capture_io do
        @app.send_verification_code('user@test.com', '123456')
      end
      assert out.include?('[EMAIL] Enviado para user@test.com: Seu código de verificação')
    end

    assert_equal '123456', @app.last_email_body.match(/<strong>(\d+)<\/strong>/)[1]
  end

  def test_registration_email
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; end
    def smtp_mock.start(*args); yield self; end
    def smtp_mock.send_message(*args); end

    Net::SMTP.stub(:new, smtp_mock) do
      out, _ = capture_io do
        @app.send_registration_link('user@test.com', 'token_abc_123')
      end
      assert out.include?('[EMAIL] Enviado para user@test.com: Confirme seu cadastro')
    end

    assert @app.last_email_body.include?('token_abc_123')
  end

  def test_forgot_password_email_without_smtp
    SMTP_CONFIG[:password] = nil

    out, _ = capture_io do
      @app.forgot_password('user@test.com')
    end

    assert out.include?('[EMAIL] SMTP não configurado.')
    assert_nil @app.last_email_to
  end
end
