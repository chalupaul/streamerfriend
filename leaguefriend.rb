#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'rest_client'
require 'active_support/inflector'
require 'RMagick'
include Magick

base_url = lambda{|region| "https://prod.api.pvp.net/api/lol/#{region}/v1.2/"}


def do_help()
  str = <<-EOS
  Usage:
  leaguefriend <summoner name> <region> <outputdir>

  Valid values for <region> are: euw, eune, na, tr, ru, oce, las, lan, br
  
  Any directory you specify to <outputdir> must already exist.
  
  You must put your mashape api key in the RIOT_API_KEY environment variable.

  In bash (like if you're on a mac), you would do this on the command 
  line prior to running this script. You'd only need to do this once though.:
    export RIOT_API_KEY="your big key here"
  EOS
  str
end

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

if ARGV.length != 3 or ENV['RIOT_API_KEY'] == nil or !File.directory?(ARGV[2])
  $stderr.puts do_help()
  exit 1
end

$summoner_name = ARGV[0]
$region = ARGV[1].downcase
$output_dir = ARGV[2]

url = "http://www.lolskill.net/game-#{$region.upcase}-#{$summoner_name}"
game_status = !(RestClient.get(url).include?("No Active Game Found"))

if game_status == false
  [:red, :yellow, :blue, :quint, :mastery1, :mastery2].each{ |f|
    File.truncate(File.join(File.join($output_dir, "#{f.to_s}.txt")), 0)
  }
  f = File.open(File.join($output_dir, "overlay.html"), 'w')
  f.write "<html><head><meta http-equiv=\"refres\h" content=\"20\" /></head><body></body></html>"
  f.close
  exit 0
end

# First we get our summoner info
url = base_url.call($region) + "summoner/by-name/#{$summoner_name}"
begin
  summoner = JSON.parse(RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}})
rescue => e
  $stderr.puts "Unable to get any info on summoner: #{$summoner_name} on region: #{$region}."
  exit 1
end

# Now runes
reds = (1..9).to_a
yellows = (10..18).to_a
blues = (19..27).to_a
quints = (28..30).to_a



url = base_url.call($region) + "summoner/#{summoner['id']}/runes"
begin
  runes = JSON.parse(RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}})
  #runes = RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}}
rescue => e
  $stderr.puts "Unable to retrieve runes for summoner: #{$summoner_name} on region: #{$region}."
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

url = base_url.call($region) + "summoner/#{summoner['id']}/masteries"
begin
  masteries = JSON.parse(RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}})
  #masteries = RestClient.get url, {:params => {"api_key" => ENV['RIOT_API_KEY']}}
rescue => e
  $stderr.puts "Unable to retrieve masteries for summoner: #{$summoner_name} on $region: #{$region}."
  exit 1
end

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

$texts = []

[:red, :yellow, :blue, :quint].each{ |color|
  runes = runes_by_color[color]
  if runes.length == 1
    out_line = runes.map{|k,v| "#{v[:name]} #{color.to_s.pluralize.capitalize}" }[0]
  else
    out_line = runes.collect{|k,v| "#{v[:count]}x #{v[:name]}"}.join(", ") + " #{color.to_s.pluralize.capitalize}"
  end
  f = File.open(File.join($output_dir, "#{color.to_s}.txt"), 'w')
  $texts << out_line
  f.write("<xsplit>")
  f.write out_line
  f.write("</xsplit>")
  f.close
}

def write_mastery(file, contents)
  $texts << contents
  f = File.open(file, 'w')
  f.write "<xsplit>"
  f.write contents
  f.write "</xsplit>"
  f.close
end
write_mastery File.join($output_dir, "mastery1.txt"), "#{counts['offensive']}/#{counts['defensive']}/#{counts['utility']}"
#write_mastery File.join($output_dir, "mastery2.txt"), "(\"#{mastery_page_name}\" masteries)"

max_len = $texts.group_by(&:size).max.first
text = $texts.map{|t| sprintf("%#{max_len}s", t)}.join("\n")
f = File.open(File.join($output_dir, "overlay.html"), 'w')
f.write "<html><head><meta http-equiv=\"refresh\" content=\"20\" /></head><body><p style=\"text-align:right;color:white\">#{text.gsub(/\n/, "<br />\n")}</p></body></html>"
f.close

canvas = Image.new(400, 85) do |c|
  c.background_color= "Transparent"
end
watermark_text = Draw.new
watermark_text.annotate(canvas, 0,0,398,0, text) do
  self.gravity = WestGravity
  self.pointsize = 10
  self.font = "Courier-Bold"
  self.fill = 'white'
  self.stroke = "none"
  self.align = RightAlign
end
canvas.write(File.join($output_dir, 'overlay.png'))


