#!/usr/bin/env ruby
require 'json'
require 'pp'

if ARGV.size > 0
  text = File.read(ARGV[0])
else
  text = STDIN.read
end

data = JSON.parse(text)
# pp data

def emit(*a)
  # p a
end

puts "@startuml"

def output
  if @lines.size > 0
    if @title
      puts @title
      @title = nil
    end
    if @client
      print "Radio -> TagService: "
    else
      print "TagService -> Radio: "
    end
    puts @lines.join('\\n')
    @lines = []
  end
end

@title = nil
@client = true
@in_block = false
@lines = []
data.each do |line|
  if line[0] == "source"
    type, line_number, attributes = *line
    attributes = attributes.first
    #STDERR.puts attributes.pretty_inspect
    if attributes["block"]
      if @in_block
        # end previous block
        output
      else
        @in_block = true
      end
      # start new block
    else
      @in_block = true
      @lines << attributes["line"]["text"]
    end
  else
    if @in_block
      output
      @in_block = false
    end
    attributes = line[0][0]
    if h = attributes["heading"]
      case h["text"]
      when /^Request/
        @client = true
      when /^Response/
        @client = false
      else
        if h["level"] == 1
          @title = "== #{h["text"]} =="
        end
      end
    end
  end
end
output
puts "@enduml"
