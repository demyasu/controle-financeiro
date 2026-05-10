require 'sinatra/activerecord'
require 'sqlite3'

Sinatra::ActiveRecord::Tasks.load!

db_config = {
  adapter: 'sqlite3',
  database: 'db/financeiro.db'
}

ActiveRecord::Base.establish_connection(db_config)

namespace :db do
  desc 'Create database'
  task :create do
    if File.exist?('db/financeiro.db')
      puts 'Database already exists'
    else
      SQLite3::Database.new('db/financeiro.db')
      puts 'Database created'
    end
  end

  desc 'Run migrations'
  task :migrate do
    ActiveRecord::MigrationContext.new('db/migrate').migrate
    puts 'Migrations completed'
  end
end
