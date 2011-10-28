#!/usr/bin/env ruby
# getting to the point where I'll need to build a DOM

$APP_DEBUG = ARGV.delete("--debug")

@ast = []

RX_LINK = /(\[\[.*?\]\])|(https?:\S+)/m

def parse_links(source)
  #p [:parse_links, line]
  structure = []
  # need to apply inline formatting to link text
  source.split(RX_LINK).each_slice(2) { |text, link|
    #p [:text, text, :link, link]
    if text
      structure << { :text => text }
    end
    if link
      case link
      when /^http/
        structure << { :link => { :href => link }}
      else
        match = link.match(/\[\[(.*?)(?:(?:\]\[)(.*))?\]\]/m)
        #p [link, :matches, match.captures]
        link = Hash[[:href, :text].zip(match.captures)]
        if link[:text].nil?
          link[:text] = link[:href]
        end
        structure << { :link => link }
      end
    end
  }
  #p [:structure, structure]
  structure
end

def format_rx(start_delimiter, end_delimiter = start_delimiter)
  /\B#{Regexp.quote(start_delimiter)}(.+?)#{Regexp.quote(end_delimiter)}\B/
end

FORMATS = {
  :italic => format_rx("/"),
  :bold   => format_rx("*"),
  :code   => format_rx("="),
}

def parse_inline(format, text)
  # need to apply inline formatting to link text
  structure = []
  text.split(FORMATS[format]).each_slice(2) do |before, formatted|
    # p [:before, before, :formatted, formatted]
    if before
      structure << { :text => before }
    end
    if formatted
      structure << { format => { :text => formatted }}
    end
  end
  structure
end

def process_line(line, &block)
  case line
  when Hash
    line.each do |key, value|
      if key == :text
        line[key] = process_line(value, &block)
      end
    end
    line
  when Array
    line.map do |element|
      process_line(element, &block)
    end
  when String
    block.call(line)
  else
    raise ArgumentError
  end
  #p [:line2, line]
end

def process_line(line, &block)
  elements = []
  line.each do |element|
    if t = element[:text]
      data[:text] = block.call
      elements.push(*block.call(t))
    else
      elements.push(element)
    end
  end
  elements
end

# def process_line(line, &block)
#   line.each do |element|
#     p [:element, element]
#     type = element.keys.first
#     data = element[type]
#     p [:type, type, :data, data]
#     if t = data[:text]
#       data[:text] = block.call(data[:text])
#       p [:data_text, data[:text]]
#     end
#   end
# end

def emit(type, *a)
  # print "%-64s " % @line
  element = [@line_number, type, *a]
  # p element
  ast_element = [type, @line_number]
  if a.size == 1
    ast_element << a.first
  end
  if a.size > 1
    ast_element << a
  end
  @ast << ast_element
end

def expand_link(link)
  # http://en.wikipedia.com/wiki/
  scheme, rest = link.split(/:/)
  case link
  when /wp:/
    scheme = "http://en.wikipedia.com/wiki/"
  when /[a-z+]:/
    scheme = scheme + ":"
  end
  dbg [:scheme, scheme, :rest, rest].inspect
  scheme + rest.to_s
end

def dbg(*a)
  STDERR.puts "DEBUG: " + a.inspect if $APP_DEBUG
end

in_quote = false
@in_block = false
spaces = 0
@line_number = 0
ARGF.each_line do |line|
  line = line.chomp
  @line_number += 1
  @line = line
  dbg :input, line
  case line
  # when /^\s*<(.*)>\s*$/i
  #   dbg :case, 1, :angle_date
  #   emit :date, $1
  #   next
  when /^\s*:\s*(.*)/i
    # code line
    dbg :case, 2.1, :code_line, $1
    line = { :code_line => { :raw => $1 }}
  when /^\s*(\$.*)/i
    # command line
    dbg :case, 2.2, :command_line, :text => $1
    line = { :command_line => { :raw => $1 }}
  when /^\s*#\+BEGIN_QUOTE/i
    # start quote
    dbg :case, 3, :begin_quote
    in_quote = true
    line = { :block => { :type => :quote }}
  when /^\s*#\+END_QUOTE/i
    # end quote
    dbg :case, 4, :end_quote
    in_quote = false
    line = { :end_block => { :type => :quote } }
  when /^\s*#\+BEGIN_SRC(\s+(.*))?/i
    # start code block
    dbg :case, 5, :begin_src
    @in_block = 0
    spaces = 0
    #dbg :BEGIN_SRC
    line = { :block => { :type => :source, :attributes => $2 }}
  when /^\s*#\+END_SRC/i
    # end code block
    dbg :case, 6, :end_src
    @in_block = false
    spaces = 0
    #dbg :END_SRC
    line = { :end_block => { :type => :source }}
  when /^\s*#\+BEGIN_EXAMPLE/i
    # start example block
    dbg :case, 5, :begin_example
    @in_block = 0
    spaces = 0
    line = { :block => { :type => :example, :attributes => $2 }}
  when /^\s*#\+END_EXAMPLE/i
    # end example block
    dbg :case, 6, :end_src
    @in_block = false
    spaces = 0
    #dbg :END_SRC
    line = { :end_block => { :type => :example }}
  when /^#\+(.*)$/i
    # directive
    dbg :case, 7, :directive
    line = { :directive => { :raw => $1 }}
  when /^\s*#(.*)$/i
    # comment
    dbg :case, 7, :comment
    line = { :comment => { :raw => $1 }}
  when /^\*+ !SLIDE/
    # SLIDES
    dbg :case, 8, :slide
    line = { :slide => { } }
  when /^(\*+)\s+(.*$)/
    # headings
    dbg :case, 9, :heading
    line = { :heading => { :level => $1.size, :text => $2 }}
  when /^\|\-+/
    dbg :case, 10, :table_header
    line = { :table_header => { } }
    # skip table header lines (note: this is for textile/confluence)
    next
  when /^(\s*)\-+\s+(.*)$/
    # bullet list
    dbg :case, 11, :bullet_list_item
    line = { :list_item => { :indent => $1.size, :text => $2 }}
  else
    line = { :line => { :text => line }}
  end
  line = [line]

  #p [:line1, line]

  # replace links

  line = process_line(line) { |text|
    parse_links(text)
  }

  [:italic, :bold, :code].each do |format|
    line = process_line(line) { |text|
      parse_inline(format, text)
    }
  end

  # formatting - bold, italic, etc.
  # inline code

  if @in_block
    dbg :in_blockcat , :@in_block
    # if first line of source block, remember indent
    if @in_block == 1
      if text = line.first[:text]
        m = text.match(/^\s+/)
        emit :block_attr, :indent => m.to_s.size
      end
    end
    # emit :DBG, line
    line[0] = {:line_number => @in_block }.merge(line[0])
    # emit :DBG, line
    emit :source, line
    @in_block += 1
  else
    dbg :output, line
    if in_quote
      emit :quote, line
    else
      if line == ""
        emit :newline
      else
        emit line
      end
    end
  end
end

# require 'yaml'
# puts @ast.to_yaml

require 'json'
puts JSON::pretty_generate(@ast)

=begin

- need to think about how to represent lines
- generic way for process :text elements
- don't mix up emit and lines (want to be able to process_links in headings as well as plain text)
- multiline - should concatenate all contiguous :text elements
- states - make sure I've got in block states correct

=end
