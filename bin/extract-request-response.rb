#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# Split trace org file into separate files each containing a request/response by name
def extract_sections(text)
  in_section = false
  sections = []
  text.each_line do |line|
    line = line.chomp
    case line
      # request/response header
    when /^\** (Request|Response)+/
      in_section = true
      section_name = line
      sections << [section_name, []]
      # some other header
    when /^\*+/
      in_section = false
      section_name = nil
    else
      if in_section
        sections[-1][-1] << line
      end
    end
  end
  sections
end

def construct_filename(type, number, api_call)
  api_call = api_call.gsub(/\W+/, '-')
  [number, type, api_call].map{ |x| x.downcase}.join('-')
end

def output_sections(filename, sections)
  if filename
    prefix =  File.join(File.dirname(filename), File.basename(filename, File.extname(filename)))
  else
    prefix = nil
  end
  sections.each do |section, lines|
    section = section.gsub(/\*+/, '').strip
    if match = section.match(/(Request|Response)\s+(\d+)\s+-\s+(.*)\s*/)
      if match.captures.size == 3
        fn = construct_filename(*match.captures)
        if prefix
          fn = [prefix, fn].join("-")
        end
        File.open(fn + ".org", "wb") do |file|
          file.puts "# #{section}"
          file.puts lines
        end
      end
    end
  end
end

if ARGV.size == 0
  text = STDIN.read
  prefix = nil
  filename = nil
elsif ARGV.size == 1
  filename = ARGV[0]
  text = File.read(filename)
else
  abort "usage: #{$0} [orgfile containing trace]"
end
sections = extract_sections(text)
output_sections(filename, sections)
