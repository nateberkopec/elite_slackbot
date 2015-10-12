require 'net/http'
require 'slack-ruby-client'
require 'yajl'
require 'pry'
require 'knnball'
require 'optparse'

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: example.rb [options]"
    opts.on("-f", "--[no-]full", "Use full stations json") do |f|
      options[:full] = f
    end
end.parse!
p options
p ARGV

COMMODITY_CHANNEL = "elite_commodities"

Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
end

#client = Slack::Web::Client.new

#channel = client.channels_list['channels'].detect { |c| c['name'] == COMMODITY_CHANNEL }

# client.chat_postMessage(
#   channel: channel['id'],
#   text: 'Hello World',
#   username: 'eddb_commodity',
#   icon_emoji: ":chart_with_upwards_trend:"
# )

# binding.pry

# Stations_lite doesn't include listings, but regular Stations is ~190mb
# so lets use a local copy of the stations.json for now #jasonisfat
response = Net::HTTP.get_response("eddb.io","/archive/v3/stations_lite.json")
parser = Yajl::Parser.new
STATIONS_LITE = parser.parse(response.body)
response = nil

STATION = nil
if options[:full]
  parser = Yajl::Parser.new
  json = File.new("stations.json", 'r')
  STATIONS = parser.parse(json)
  puts "loaded full stations.json"
end

response = Net::HTTP.get_response("eddb.io","/archive/v3/systems.json")
parser = Yajl::Parser.new
SYSTEMS = parser.parse(response.body)
response = nil

response = Net::HTTP.get_response("eddb.io","/archive/v3/commodities.json")
parser = Yajl::Parser.new
COMMODITIES = parser.parse(response.body)
response = nil

class Index
  attr_accessor :hightech, :refinery, :extraction
  def initialize
    self.hightech = KnnBall.build(SYSTEMS.select {|s| s['primary_economy'] == "High Tech"}.map {|s| {id: s['id'], point: [s['x'], s['y'], s['z']]}})
    self.refinery = KnnBall.build(SYSTEMS.select {|s| s['primary_economy'] == "Refinery"}.map {|s| {id: s['id'], point: [s['x'], s['y'], s['z']]}})
    self.extraction = KnnBall.build(SYSTEMS.select {|s| s['primary_economy'] == "Extraction"}.map {|s| {id: s['id'], point: [s['x'], s['y'], s['z']]}})
  end
end

INDEX = Index.new
CLIENT = Slack::RealTime::Client.new

def calculate_distance(p1, p2)
  xd = p1[0] - p2[0]
  yd = p1[1] - p2[1]
  zd = p1[2] - p2[2]

  Math.sqrt(xd*xd + yd*yd + zd*zd)
end

CLIENT.on :message do |data|
  case data['text']
  when /^elite station/ then
    get_station_info(data['text'], data['channel'], options[:full])
  when /^elite listings/ then
    get_station_listings(data['text'], data['channel'], options[:full])
  when /^elite nearest_hightech/ then
    nearest_to_type(:hightech, data['text'], data['channel'])
  when /^elite nearest_extraction/ then
    nearest_to_type(:extraction, data['text'], data['channel'])
  when /^elite nearest_refinery/ then
    nearest_to_type(:refinery, data['text'], data['channel'])
  when /^elite price/ then
    get_price_avg(data['text'], data['channel'])
  end
end

def nearest_to_type(type, text, channel)
  system_name = text.gsub("elite nearest_#{type} ", "")
  system = SYSTEMS.detect { |s| s['name'].downcase == system_name.downcase }

  return nil if system.nil?

  system_point = [system['x'], system['y'], system['z']]
  result = INDEX.send(type.to_s).nearest(system_point)
  result_system = SYSTEMS.detect { |s| s['id'] == result[:id] }
  result_system_point = [result_system['x'], result_system['y'], result_system['z']]

  CLIENT.message channel: channel, text: "#{result_system['name']} - #{calculate_distance(system_point, result_system_point)} LY"
end

def get_price_avg(text, channel)
  commodity_name = text.gsub("elite price ", "")
  listing = COMMODITIES.detect{ |s| s['name'].downcase == commodity_name.downcase }

  return nil if listing.nil?

  price = listing['average_price']

  CLIENT.message channel: channel, text: "The galactic average price of #{commodity_name} is #{price}cr"
end

def get_station_info(text, channel, usingFull)
  station_name = text.gsub("elite station ", "")
  if !usingFull
    station = STATIONS_LITE.detect { |s| s['name'].downcase == station_name.downcase }
  else
    station = STATIONS.detect { |s| s['name'].downcase == station_name.downcase }
  end

  msg = ""
  if station.nil?
    msg << "That station doesn't exist"
  else
    if !usingFull
      station.each do |key, value|
        msg << "#{key}: #{value}\n"
      end
    else
      station.each do |key, value|
        next if key == "listings"
        msg << "#{key}: #{value}\n"
      end
    end
  end
  CLIENT.message channel: channel, text: msg
end

def get_station_listings(text, channel, usingFull)
  station_name = text.gsub("elite listings ", "")
  if !usingFull
    station = nil
  else
    station = STATIONS.detect { |s| s['name'].downcase == station_name.downcase }
  end

  msg = ""
  if station.nil?
    if !usingFull
      msg << "No listing data when using stations_lite.json, start bot with -full option"
    else
      msg << "That station doesn't exist"
    end
  else
    msg << "This method works, but there are too many commodities to list right now."
    # station.each do |key, value|
    #   next if key != "listings"
    #   msg << "#{key}: #{value}\n"
    # end
  end
  CLIENT.message channel: channel, text: msg
end


CLIENT.start!
