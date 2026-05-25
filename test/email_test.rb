require 'minitest/autorun'
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

class EmailTest < Minitest::Test
  def setup
    SMTP_CONFIG[:server]   = 'smtp.test.com'
    SMTP_CONFIG[:port]     = 587
    SMTP_CONFIG[:domain]   = 'localhost'
    SMTP_CONFIG[:username] = 'test@test.com'
    SMTP_CONFIG[:password] = 'test-password'
    SMTP_CONFIG[:from]     = 'test@test.com'
    SMTP_CONFIG[:from_name] = 'Test'
  end

  def test_smtp_configured_with_password
    assert smtp_configured?
  end

  def test_smtp_not_configured_without_password
    SMTP_CONFIG[:password] = nil
    refute smtp_configured?
  end

  def test_smtp_not_configured_with_empty_password
    SMTP_CONFIG[:password] = ''
    refute smtp_configured?
  end

  def test_send_email_uses_correct_smtp_settings
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; end
    def smtp_mock.start(domain, user, pass, auth)
      @domain, @user, @pass, @auth = domain, user, pass, auth
      yield self
    end
    def smtp_mock.send_message(msg, from, to)
      @msg, @from, @to = msg, from, to
    end

    Net::SMTP.stub(:new, smtp_mock) do
      out, _ = capture_io do
        send_email(to: 'user@test.com', subject: 'Test Subject', body: '<p>Test body</p>')
      end
      assert out.include?('[EMAIL] Enviado para user@test.com: Test Subject')
    end

    assert_equal 'user@test.com', smtp_mock.instance_variable_get(:@to)
    msg = smtp_mock.instance_variable_get(:@msg)
    assert msg.include?('Test Subject')
    assert msg.include?('<p>Test body</p>')
    assert msg.include?('From: Test <test@test.com>')
    assert msg.include?('To: user@test.com')
  end

  def test_send_email_logs_when_smtp_not_configured
    SMTP_CONFIG[:password] = nil
    out, _ = capture_io do
      send_email(to: 'user@test.com', subject: 'No SMTP', body: 'test')
    end
    assert out.include?('[EMAIL] SMTP não configurado.')
  end

  def test_send_email_uses_ssl_on_port_465
    SMTP_CONFIG[:port] = 465

    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_ssl; @ssl_called = true; end
    def smtp_mock.start(*args); yield self; end
    def smtp_mock.send_message(*args); end

    Net::SMTP.stub(:new, smtp_mock) do
      send_email(to: 'a@b.com', subject: 'SSL test', body: 'test')
    end

    assert smtp_mock.instance_variable_get(:@ssl_called)
  end

  def test_send_email_uses_starttls_on_port_587
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; @starttls_called = true; end
    def smtp_mock.start(*args); yield self; end
    def smtp_mock.send_message(*args); end

    Net::SMTP.stub(:new, smtp_mock) do
      send_email(to: 'a@b.com', subject: 'STARTTLS test', body: 'test')
    end

    assert smtp_mock.instance_variable_get(:@starttls_called)
  end

  def test_send_email_passes_correct_smtp_auth
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; end
    def smtp_mock.start(domain, user, pass, auth)
      @domain, @user, @pass, @auth = domain, user, pass, auth
      yield self
    end
    def smtp_mock.send_message(*args); end

    Net::SMTP.stub(:new, smtp_mock) do
      send_email(to: 'a@b.com', subject: 'Auth test', body: 'test')
    end

    assert_equal 'localhost', smtp_mock.instance_variable_get(:@domain)
    assert_equal 'test@test.com', smtp_mock.instance_variable_get(:@user)
    assert_equal 'test-password', smtp_mock.instance_variable_get(:@pass)
    assert_equal :login, smtp_mock.instance_variable_get(:@auth)
  end

  def test_send_email_falls_back_to_api_on_smtp_error
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; end
    def smtp_mock.start(*args); raise RuntimeError, 'Connection failed'; end
    def smtp_mock.send_message(*args); end

    http_mock = Object.new
    def http_mock.open_timeout=(val); end
    def http_mock.read_timeout=(val); end
    def http_mock.use_ssl=(val); end
    def http_mock.request(req)
      r = Object.new
      def r.code; '202'; end
      def r.body; 'accepted'; end
      r
    end

    out, _ = capture_io do
      Net::SMTP.stub(:new, smtp_mock) do
        Net::HTTP.stub(:new, http_mock) do
          send_email(to: 'a@b.com', subject: 'Error test', body: 'test')
        end
      end
    end

    assert out.include?('[EMAIL] SMTP falhou para a@b.com: Connection failed')
    assert out.include?('[EMAIL] Tentando API SendGrid...')
    assert out.include?('[EMAIL] Enviado via API para a@b.com: Error test')
  end

  def test_email_message_format
    smtp_mock = Object.new
    def smtp_mock.open_timeout=(val); end
    def smtp_mock.read_timeout=(val); end
    def smtp_mock.enable_starttls; end
    def smtp_mock.start(*args); yield self; end
    def smtp_mock.send_message(msg, from, to)
      @msg = msg; @from = from; @to = to
    end

    Net::SMTP.stub(:new, smtp_mock) do
      send_email(to: 'user@example.com', subject: 'Assunto Teste', body: '<h1>Olá</h1>')
    end

    msg = smtp_mock.instance_variable_get(:@msg)
    assert msg.start_with?('From:')
    assert msg.include?("From: Test <test@test.com>")
    assert msg.include?("To: user@example.com")
    assert msg.include?("Subject: Assunto Teste")
    assert msg.include?("MIME-Version: 1.0")
    assert msg.include?("Content-Type: text/html; charset=UTF-8")
    assert msg.include?("<h1>Olá</h1>")
  end
end
