require 'dotenv/load'
require 'sequel'

namespace :db do
  desc 'Run migrations'
  task :migrate do
    require_relative 'config/database'
    Sequel.extension :migration
    Sequel::Migrator.run(DB, File.join(__dir__, 'db', 'migrations'))
    puts 'Migrations completed!'
  end

  desc 'Create the database'
  task :create do
    db_name = ENV['DB_NAME'] || 'controle_financeiro'
    db_user = ENV['DB_USER'] || 'postgres'
    db_host = ENV['DB_HOST'] || 'localhost'
    db_port = ENV['DB_PORT'] || 5432

    system("createdb -U #{db_user} -h #{db_host} -p #{db_port} #{db_name}")
    puts "Database '#{db_name}' created!"
  end

  desc 'Seed admin user'
  task :seed do
    require_relative 'config/database'
    require 'openssl'
    require 'base64'
    require 'securerandom'

    admin_email = ENV['ADMIN_EMAIL'] || 'pcyasuic@ideiasti.com'
    admin_password = ENV['ADMIN_PASSWORD'] || 'admin123'

    unless User[admin_email]
      salt = SecureRandom.hex(16)
      iter = 100_000
      key_len = 32
      hash = OpenSSL::PKCS5.pbkdf2_hmac(admin_password, salt, iter, key_len, 'SHA256')
      User.create(
        email: admin_email,
        username: 'Admin',
        admin: true,
        password_hash: "#{salt}:#{iter}:#{Base64.strict_encode64(hash)}",
        created_at: Time.now
      )
      puts "Admin user '#{admin_email}' created!"
    else
      puts "Admin user '#{admin_email}' already exists."
    end
  end
end
