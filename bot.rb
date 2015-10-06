require 'net/http'
require 'slack-ruby-client'
require 'yajl'
require 'pry'
require 'knnball'

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

response = Net::HTTP.get_response("eddb.io","/archive/v3/stations_lite.json")
parser = Yajl::Parser.new
@stations = parser.parse(response.body)
response = nil

response = Net::HTTP.get_response("eddb.io","/archive/v3/systems.json")
parser = Yajl::Parser.new
@systems = parser.parse(response.body)
response = nil

hightech_index = KnnBall.build(@systems.select {|s| s['primary_economy'] == "High Tech"}.map {|s| {id: s['id'], point: [s['x'], s['y'], s['z']]}})

client = Slack::RealTime::Client.new

client.on :message do |data|
  case data['text']
  when /^elite station/ then
    station_name = data['text'].gsub("elite station ", "")
    station = @stations.detect { |s| s['name'].downcase == station_name.downcase }
    msg = ""
    station.each do |key, value|
      next if key == "listings"
      msg << "#{key}: #{value}\n"
    end

    client.message channel: data['channel'], text: msg
  when /^elite nearest_hightech/ then
    system_name = data['text'].gsub("elite nearest_hightech ", "")
    system = @systems.detect { |s| s['name'].downcase == system_name.downcase }
    result = hightech_index.nearest([system['x'], system['y'], system['z']])
    result_system = @systems.detect { |s| s['id'] == result[:id] }

    client.message channel: data['channel'], text: result_system['name']
  end
end

client.start!
