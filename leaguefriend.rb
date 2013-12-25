#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'rest_client'

base_url = lambda{|region| "https://prod.api.pvp.net/api/lol/#{region}/v1.2/"}


def do_help()
  str = <<-EOS
  Usage:
  leaguefriend <summoner name> <region>
  Valid values for <region> are: EUW, EUNE, NA, TR, RU, OCE, LAS, LAN, BR
  
  You must put your mashape api key in the RIOT_API_KEY environment variable.

  In bash (like if you're on a mac), you would do this on the command 
  line prior to running this script. You'd only need to do this once though.:
    export RIOT_API_KEY="your big key here"
  EOS
  str
end

if ARGV.length != 2 or ENV['RIOT_API_KEY'] == nil
  $stderr.puts do_help()
  exit 1
end

summoner_name = ARGV[0]
region = ARGV[1].downcase

# First we get our summoner info
url = base_url.call(region) + "summoner/by-name/#{summoner_name}"
begin
  summoner = JSON.parse(RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}})
rescue => e
  $stderr.puts "Unable to get any info on summoner: #{summoner_name} on region: #{region}."
  exit 1
end

# Now runes
reds = (1..9).to_a
yellows = (10..18).to_a
blues = (19..27).to_a
quints = (28..30).to_a

def process_name(name)
  tmp_name = name.split(' of ')[-1]
  if tmp_name.start_with?('Scaling')
    tmp_name = tmp_name.sub('Scaling ', '')
    tmp_name = tmp_name + ' per Level'
  end
  tmp_name
end

url = base_url.call(region) + "summoner/#{summoner['id']}/runes"
begin
  runes = JSON.parse(RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}})
  #runes = RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}}
rescue => e
  $stderr.puts "Unable to retrieve masteries for summoner: #{summoner_name} on region: #{region}."
  exit 1
end
colors = {:red => {}, :blue => {}, :yellow => {}, :quint => {}}
runes['pages'].each do |page|
  if page.keys.include?('slots')
    page['slots'].each do |slot|
      id = slot['rune']['id']
      color = reds.include?(slot['runeSlotId']) ? 'red' : yellows.include?(slot['runeSlotId']) ? 'yellow' : blues.include?(slot['runeSlotId']) ? 'blue' : 'quint'
      name = process_name(slot['rune']['name'])
      if !colors[:red].keys.include?(id) && !colors[:yellow].keys.include?(id)  && !colors[:blue].keys.include?(id) && !colors[:quint].keys.include?(id)
        colors[color.to_sym][id] = name
      end
    end
  end
end

puts colors.to_json