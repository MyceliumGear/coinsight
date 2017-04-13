ENV['PUMA_THREADS_MIN'] ||= '1'
ENV['PUMA_THREADS_MAX'] ||= '10'
ENV['PUMA_WORKERS']     ||= '1'
ENV['PUMA_BIND']        ||= 'tcp://0.0.0.0:3000'

bind ENV['PUMA_BIND']
threads ENV['PUMA_THREADS_MIN'].to_i, ENV['PUMA_THREADS_MAX'].to_i
workers ENV['PUMA_WORKERS'].to_i
daemonize false
rackup File.expand_path('../config.ru', __FILE__)
