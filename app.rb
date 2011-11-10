require 'sinatra'
require 'haml'
require 'redis'
require 'json'
require 'yaml'
require 'rack-flash'
require 'rack/no-www'

configure do
  redis_uri = URI.parse(ENV["REDISTOGO_URL"] || 'redis://localhost:6379/')
  REDIS = Redis.new(:host => redis_uri.host, :port => redis_uri.port, :password => redis_uri.password)

  set :haml, { :format => :html5 }

  use Rack::Flash, :accessorize => [:notice, :error]
  use Rack::NoWWW
  
  ON_PRODUCTION = (ENV['RACK_ENV'] == 'production')
end

get '/' do
  haml :home, :layout => false
end

post '/add' do

end

post '/remove' do

end

get '/feed/:name' do |name|
  name
end