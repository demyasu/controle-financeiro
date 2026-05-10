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

DB = Sequel.connect(database_url)

Sequel.extension :migration
migration_dir = ENV['MIGRATIONS_PATH'] || File.join(Dir.pwd, 'db', 'migrations')
puts "[DB] Running migrations from: #{migration_dir}"
puts "[DB] Files: #{Dir.glob(File.join(migration_dir, '*.rb')).inspect}"
Sequel::Migrator.run(DB, migration_dir)
