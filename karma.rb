# Usage: redis-cli publish message.achannel hello
require 'thin'
require 'sinatra'
require 'erb'
require 'redis'

configure do
  set :server, 'thin'
  
  require 'redis'
  redisUri = ENV["REDISTOGO_URL"] || 'redis://localhost:6379'
  uri = URI.parse(redisUri) 
  REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

conns = Hash.new {|h, k| h[k] = [] }

Thread.abort_on_exception = true

get '/' do
  erb :index
end

get '/subscribe/:channel', provides: 'text/event-stream' do
  stream(:keep_open) do |out|
    channel = params[:channel]

    conns[channel] << out

    out.callback do
      conns[channel].delete(out)
    end
  end
end

post '/send/:channel' do
  channel = params[:channel]
  REDIS.publish "message.#{channel}", params[:msg]
  204 # response without entity body
end

Thread.new do
  redis = Redis.connect

  redis.psubscribe('message', 'message.*') do |on|
    on.pmessage do |match, channel, message|
      channel = channel.sub('message.', '')

      conns[channel].each do |out|
        out << "data: #{message}\n\n"
      end
    end
    on.punsubscribe do |event, total|
      puts "Unsubscribed for ##{event} (#{total} subscriptions)"
    end
  end
end
