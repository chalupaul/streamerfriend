#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'rest_client'
require 'active_support/inflector'

base_url = lambda{|region| "https://prod.api.pvp.net/api/lol/#{region}/v1.2/"}


def do_help()
  str = <<-EOS
  Usage:
  leaguefriend <summoner name> <region>
  Valid values for <region> are: euw, eune, na, tr, ru, oce, las, lan, br
  
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
  subs = {
    :"Magic Resist" => :MR,
    :"Cooldown Reduction" => :CDR,
    :"Ability Power" => :AP,
    :"Attack Damage" => :AD,
    :"Health Regeneration" => :"HP Regen",
    :"Movement Speed" => :MS,
    :Gold => :GP10,
    :Penetration => :Pen
  }
  tmp_name = name.split(' of ')[-1]
  if tmp_name.start_with?('Scaling')
    tmp_name = tmp_name.sub('Scaling ', '')
    tmp_name = tmp_name + ' per Level'
  end
  subs.keys.each {|s|
    tmp_name = tmp_name.gsub(s.to_s, subs[s].to_s)
  }
  tmp_name
end

url = base_url.call(region) + "summoner/#{summoner['id']}/runes"
begin
  runes = JSON.parse(RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}})
  #runes = RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}}
rescue => e
  $stderr.puts "Unable to retrieve runes for summoner: #{summoner_name} on region: #{region}."
  exit 1
end
runes_by_color = {:red => {}, :blue => {}, :yellow => {}, :quint => {}}
runes['pages'].each do |page|
  if page.keys.include?('slots') && page['current'] == true
    page['slots'].each do |slot|
      id = slot['rune']['id']
      color = reds.include?(slot['runeSlotId']) ? 'red' : yellows.include?(slot['runeSlotId']) ? 'yellow' : blues.include?(slot['runeSlotId']) ? 'blue' : 'quint'
      name = process_name(slot['rune']['name'])
      if !runes_by_color[:red].keys.include?(id) && !runes_by_color[:yellow].keys.include?(id) && !runes_by_color[:blue].keys.include?(id) && !runes_by_color[:quint].keys.include?(id)
        runes_by_color[color.to_sym][id] = {:name => name, :count => 1}
      else
        runes_by_color[color.to_sym][id][:count] += 1
      end
    end
  end
end

url = base_url.call(region) + "summoner/#{summoner['id']}/masteries"
begin
  masteries = JSON.parse(RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}})
  #masteries = RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}}
rescue => e
  $stderr.puts "Unable to retrieve masteries for summoner: #{summoner_name} on region: #{region}."
  exit 1
end
trees = {
  "offensive" => [
    "Double-Edged Sword",
    "Fury",
    "Sorcery",
    "Butcher",
    "Expose Weakness",
    "Brute Force",
    "Mental Force",
    "Feast",
    "Spell Weaving",
    "Martial Mastery",
    "Arcane Mastery",
    "Executioner",
    "Blade Weaving",
    "Warlord",
    "Archmage",
    "Dangerous Game",
    "Frenzy",
    "Devastating Strikes",
    "Arcane Blade",
    "Havoc"
  ],
  "defensive" => [
    "Block",
    "Recovery",
    "Enchanted Armor",
    "Tough Skin",
    "Unyielding",
    "Veteran's Scars",
    "Bladed Armor",
    "Oppression",
    "Juggernaut",
    "Hardiness",
    "Resistance",
    "Perseverance",
    "Swiftness",
    "Reinforced Armor",
    "Evasive",
    "Second Wind",
    "Legendary Guardian",
    "Runic Blessing",
    "Tenacious"
  ],
  "utility" => [
    "Phasewalker",
    "Fleet of Foot",
    "Meditation",
    "Scout",
    "Summoner's Insight",
    "Strength of Spirit",
    "Alchemist",
    "Greed",
    "Runic Affinity",
    "Vampirism",
    "Culinary Master",
    "Scavenger",
    "Wealth",
    "Expanded Mind",
    "Inspiration",
    "Bandit",
    "Intelligence",
    "Wanderer"
  ]
}
counts = {'offensive' => 0, 'defensive' => 0, 'utility' => 0}
mastery_page_name = ''
masteries['pages'].each { |page|
  if page['current'] == true
    mastery_page_name = page['name']
    page['talents'].each { |talent|
      counts.keys.each{ |k|
        if trees[k].include? talent['name']
          counts[k] += talent['rank']
        end
      }
    }
  end
}

rstr = [:red, :yellow, :blue, :quint].collect{ |color|
  runes = runes_by_color[color]
  if runes.length == 1
    runes.map{|k,v| "#{v[:name]} #{color.to_s.pluralize.capitalize}" }
  else
    runes.collect{|k,v| "#{v[:count]}x #{v[:name]}"}.join(", ") + " #{color.to_s.pluralize.capitalize}"
  end
}
puts "<xsplit>"
puts rstr.join("\n")
puts "#{counts['offensive']}/#{counts['defensive']}/#{counts['utility']}  (\"#{mastery_page_name}\" mastery page)"
puts "</xsplit>"
