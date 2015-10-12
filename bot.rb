require 'net/http'
require 'slack-ruby-client'
require 'yajl'
require 'pry'
require 'knnball'
require 'optparse'

Slack.configure do |config|
  fail "SLACK_API_TOKEN not set" unless ENV['SLACK_API_TOKEN']
  config.token = ENV['SLACK_API_TOKEN']
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on("-f", "--[no-]full", "Use full stations json") do |f|
    options[:full] = f
  end
end.parse!

class EDDB
  attr_accessor :parser, :stations, :stations_lite, :systems, :commodities

  def load!(options)
    %w[stations stations_lite systems commodities].each do |resource|
      next if resource == "stations" && !options[:full]
      load_resource(resource)
    end
  end

  def stations
    @stations ? @stations : @stations_lite
  end

  def full_stations_loaded?
    !!@stations
  end

  private

  def load_resource(name)
    parser = Yajl::Parser.new
    response = Net::HTTP.get_response("eddb.io", "/archive/v3/#{name}.json")

    send(name + "=", parser.parse(response.body))
  end
end

class Index
  attr_accessor :eddb, :hightech, :refinery, :extraction

  FULLNAME = { hightech: "High Tech", refinery: "Refinery", extraction: "Extraction" }
  def initialize(opts)
    self.eddb = opts[:eddb]
    %w[refinery extraction hightech].each do |station_type|
      send(station_type + "=", build_index(station_type))
    end
  end

  private

  def build_index(type)
    applicable_systems = eddb.systems.select { |s| s['primary_economy'] == FULLNAME[type] }
    applicable_systems.map! do |s|
      {
        id: s['id'],
        point: [
          s['x'], s['y'], s['z']
        ]
      }
    end
    KnnBall.build(applicable_systems)
  end
end

@eddb = EDDB.new
@eddb.load!(options)
@index = Index.new(eddb: @eddb)
@client = Slack::RealTime::Client.new

@client.on :message do |data|
  msg = case data['text']
  when /^elite station/
    get_station_info(data['text'])
  when /^elite listings/
    get_station_listings(data['text'])
  when /^elite nearest_hightech/
    nearest_to_type(:hightech, data['text'])
  when /^elite nearest_extraction/
    nearest_to_type(:extraction, data['text'])
  when /^elite nearest_refinery/
    nearest_to_type(:refinery, data['text'])
  when /^elite price/
    get_price_avg(data['text'])
  end

  @client.message channel: data['channel'], text: msg if msg
end

def nearest_to_type(type, text)
  system_name = text.gsub("elite nearest_#{type} ", "")
  system = @eddb.systems.detect { |s| s['name'].downcase == system_name.downcase }

  return nil if system.nil?

  system_point = [system['x'], system['y'], system['z']]
  result = @index.send(type.to_s).nearest(system_point)
  result_system = @eddb.systems.detect { |s| s['id'] == result[:id] }
  result_system_point = [result_system['x'], result_system['y'], result_system['z']]

  "#{result_system['name']} - #{calculate_distance(system_point, result_system_point)} LY"
end

def calculate_distance(p1, p2)
  xd = p1[0] - p2[0]
  yd = p1[1] - p2[1]
  zd = p1[2] - p2[2]

  Math.sqrt(xd * xd + yd * yd + zd * zd)
end

def get_price_avg(text)
  commodity_name = text.gsub("elite price ", "")
  listing = @eddb.commodities.detect { |s| s['name'].downcase == commodity_name.downcase }

  return nil if listing.nil?

  price = listing['average_price']

  "The galactic average price of #{commodity_name} is #{price}cr"
end

def get_station_info(text)
  station_name = text.gsub("elite station ", "")
  station = @eddb.stations.detect { |s| s['name'].downcase == station_name.downcase }

  if station.nil?
    "That station doesn't exist"
  else
    station.map do |key, value|
      next if key == "listings"
      "#{key}: #{value}"
    end.join("\n")
  end
end

def get_station_listings(text)
  station_name = text.gsub("elite listings ", "")
  station = @eddb.stations.detect { |s| s['name'].downcase == station_name.downcase }

  if station.nil?
    if @eddb.full_stations_loaded?
      "No listing data when using stations_lite.json, start bot with -full option"
    else
      "That station doesn't exist"
    end
  else
    "This method works, but there are too many commodities to list right now."
    # station.each do |key, value|
    #   next if key != "listings"
    #   msg << "#{key}: #{value}\n"
    # end
  end
end

puts "Client start successful"
@client.start!
