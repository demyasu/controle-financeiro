require 'sequel'
require 'dotenv/load'

DATABASE_URL = ENV['DATABASE_URL'] || ENV['DB_URL'] || "postgres://#{ENV['DB_USER'] || 'postgres'}:#{ENV['DB_PASSWORD'] || 'postgres'}@#{ENV['DB_HOST'] || 'localhost'}:#{ENV['DB_PORT'] || 5432}/#{ENV['DB_NAME'] || 'controle_financeiro'}"

DB = Sequel.connect(DATABASE_URL)

Sequel.extension :migration
Sequel::Migrator.run(DB, File.join(__dir__, '..', 'db', 'migrations'))
