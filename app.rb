require 'sinatra'
require 'haml'
require 'redis'
require 'json'
require 'yaml'
require 'date'
require 'uuid'
require 'rest_client'
require 'rack-flash'
require 'rack/no-www'

configure do
  redis_uri = URI.parse(ENV["REDISTOGO_URL"] || 'redis://localhost:6379/')
  REDIS = Redis.new(:host => redis_uri.host, :port => redis_uri.port, :password => redis_uri.password)
  UUID.state_file = false

  set :haml, { :format => :html5 }
  enable :sessions

  use Rack::Flash, :accessorize => [:notice, :error]
  use Rack::NoWWW
  
  ON_PRODUCTION = (ENV['RACK_ENV'] == 'production')
end

def feed_url_at_offset( feed_template_url, offset )
  if feed_template_url[0..0] == '{'
    feed_template_proc = eval('lambda' + feed_template_url)
    feed_template_proc.call(offset)
  else
    feed_template_url % offset
  end
end

def add_item( feed_name, url, offset )
  details = {
    'time' => Time.now.to_i,
    'url' => url,
    'offset' => offset,
    'id' => UUID.generate
  }
  
  REDIS.lpush("feeditems:#{feed_name}", details.to_json)
  REDIS.ltrim("feeditems:#{feed_name}", 0, 100)
  
  true
end

def check_item( feed_name, url )
  begin
    RestClient::Request.execute(:method => 'HEAD', :url => url, :open_timeout => 6, :timeout => 6)
    true
  rescue
    false
  end
end

def check_feed( feed_name )
  details = JSON.parse( REDIS.hget('details', feed_name) )
  offset = REDIS.hget('offsets', feed_name).to_i + 1
  test_url = feed_url_at_offset(details['test_template'], offset)
  link_url = feed_url_at_offset(details['link_template'], offset)

  if check_item( feed_name, test_url )
    add_item( feed_name, link_url, offset )
    REDIS.hincrby('offsets', feed_name, 1)
  end

  REDIS.hset('lastcheck', feed_name, Time.now.to_i)
end

get '/' do
  details = REDIS.hgetall('details')
  offsets = REDIS.hgetall('offsets')
  
  @feeds = details.map do |name, details_blob|
    feed = {}
    feed_details = JSON.parse( details_blob )

    feed[:shortname] = name
    feed[:title] = feed_details['title']
    feed[:offset] = offsets[name].to_i
    feed[:url] = "/feed/#{name}"
    feed
  end
  
  haml :home, :layout => false
end

post '/add' do
  name = params[:shortname]
  offset = [1, params[:offset].to_i].max
  halt if REDIS.hexists('details', name)
  
  details = {
    'source' => params[:source],
    'test_template' => params[:testtemplate],
    'link_template' => params[:linktemplate],
    'title' => params[:title],
    'id' => UUID.generate
  }
  
  REDIS.hset('details', name, details.to_json)
  REDIS.hset('offsets', name, offset)
  
  check_feed(name)

  redirect '/'
end

post '/remove' do
  REDIS.hdel('details', params[:name])
  REDIS.hdel('offsets', params[:name])
  REDIS.hdel('lastcheck', params[:name])
  REDIS.del("feeditems:#{params[:name]}")

  redirect '/'
end

get '/feed/:name' do |name|
  halt unless details_blob = REDIS.hget('details', name)
  details = JSON.parse(details_blob)
  last_check = REDIS.hget('lastcheck', name).to_i
  
  if (Time.now.to_i - last_check) > (5 * 60) or (params[:check] == '1')
    check_feed( name )
  end
  
  @feed = {
    :title => details['title'],
    :source_url => details['source'],
    :updated => DateTime.parse( Time.at( last_check ).to_s ),
    :uuid => details['id']
  }

  @items = REDIS.lrange("feeditems:#{name}", 0, -1).map do |item_details_blob|
    item_details = JSON.parse(item_details_blob)

    item = {}
    item[:url] = item_details['url']
    item[:uuid] = item_details['id']
    item[:offset] = item_details['offset']
    item[:updated] = DateTime.parse( Time.at( item_details['time'].to_i ).to_s )
    item
  end
   
  content_type 'application/rss+xml'
  haml :rss, :format => :xhtml, :escape_html => true, :layout => false
end