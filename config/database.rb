require 'sequel'
require 'dotenv/load'

database_url = ENV['DATABASE_URL'] || ENV['DB_URL'] || begin
  user = ENV['DB_USER'] || 'postgres'
  pass = ENV['DB_PASSWORD'] || 'postgres'
  host = ENV['DB_HOST'] || 'localhost'
  port = ENV['DB_PORT'] || 5432
  name = ENV['DB_NAME'] || 'controle_financeiro'
  "postgres://#{user}:#{pass}@#{host}:#{port}/#{name}"
end

begin
  DB = Sequel.connect(database_url)
  DB.extension :pg_json if DB.adapter_scheme == :postgres
  Sequel.extension :migration

  migration_dir = File.join(__dir__, '..', 'db', 'migrations')
  if Dir.exist?(migration_dir)
    Sequel::Migrator.run(DB, migration_dir)
  else
    puts "[DB] WARNING: Migration directory not found: #{migration_dir}"
  end
rescue Sequel::DatabaseConnectionError => e
  puts "[DB] ERRO ao conectar ao PostgreSQL: #{e.message}"
  puts "[DB] DATABASE_URL: #{database_url.gsub(/:[^:@]+@/, ':****@')}"
  raise
end