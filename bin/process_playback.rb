#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'pp'

if ARGV.size > 0
  filename = ARGV[0]
else
  filename = "log.txt"
end

raw_log = File.readlines(filename)

def format(line)
  line.gsub! '-> ', ''
  line.gsub! '<- ', ''
  line
end

def convert_line(line)
  eval(line.strip.gsub('\r', '↵')).split("\n")
end

parsed_output = []
raw_log.each do |line|
  # fixup stupid re-capitalization by rest-client
  line = line.gsub(/X-Radiotag/i, 'X-RadioTAG')
  parsed_output << {:type => :header,   :content => line.split("/n")} if line =~ /^\*/
  parsed_output << {:type => :request,  :content => convert_line(format(line))} if line =~ /^<-/
  parsed_output << {:type => :response, :content => convert_line(format(line))} if line =~ /^->/
end

def blacklisted?(content)
  content =~ /^Accept: / ||
    content =~ /^X-Powered-By: / ||
    content =~ /^Accept-Encoding: / ||
    content =~ /^User-Agent: / ||
    content =~ /^Server: / ||
    content =~ /^X-Cache/ ||
    content =~ /^Via: / ||
    content =~ /^Connection: /
end

request_count = 0
context = ""
current_type = parsed_output[0][:type]
parsed_output.each do |s|
  new_type = s[:type]

  if new_type == :request and current_type == :header
    request_count += 1
    context = s[:content][0].gsub(/\s+HTTP.*$/, '')
    puts "** Request #{"%03d" % request_count} - #{context}"
    puts "#+begin_example"
  end

  if new_type == :response and current_type == :request
    puts "#+end_example"
    puts "** Response #{"%03d" % request_count} - #{context}"
    puts "#+begin_example"
  end

  if new_type == :request and current_type == :response
    puts "#+end_example"
    request_count += 1
    context = s[:content][0].gsub(/\s+HTTP.*$/, '')
    puts "** Request #{"%03d" % request_count} - #{context}"
    puts "#+begin_example"
  end

  if s[:type] == :header and current_type == :response
    puts "#+end_example"
  end

  s[:content].each {|l| puts l unless blacklisted?(l)}

  current_type = s[:type]
end
