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

current_type = parsed_output[0][:type]
parsed_output.each do |s|
  new_type = s[:type]

  if new_type == :request and current_type == :header
    puts "** Request"
    puts "#+begin_example"
  end

  if new_type == :response and current_type == :request
    puts "#+end_example"
    puts "** Response"
    puts "#+begin_example"
  end

  if new_type == :request and current_type == :response
    puts "#+end_example"
    puts "** Request"
    puts "#+begin_example"
  end

  if s[:type] == :header and current_type == :response
    puts "#+end_example"
  end

  s[:content].each {|l| puts l unless blacklisted?(l)}

  current_type = s[:type]
end

