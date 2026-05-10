workers Integer(ENV.fetch('WEB_CONCURRENCY', 2))
threads_count = Integer(ENV.fetch('MAX_THREADS', 5))
threads threads_count, threads_count

port        ENV.fetch('PORT', 8080)
environment ENV.fetch('RACK_ENV', 'production')

on_worker_boot do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end