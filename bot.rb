require 'slack-ruby-client'
require 'yajl'
require 'pry'

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

response = Net::HTTP.get_response("eddb.io","/archive/v3/stations.json")
parser = Yajl::Parser.new
@stations = parser.parse(response.body)
response = nil

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
  end
end

client.start!
