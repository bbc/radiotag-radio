#!/usr/bin/env ruby
## simulate a radio with RadioTag capabilities
## preamble
require 'rest_client'
require './lib/config_helper'
require './lib/this_method'
require 'json'
require 'highline'
require 'pp'

## command line args
$APP_DEBUG    = ARGV.delete("--debug")
$APP_RECORD   = ARGV.delete("--record")
$APP_PLAYBACK = ARGV.delete("--playback")
$APP_TRACE    = ARGV.delete("--trace")

## set up HTTP tracing if requested
# if HTTP tracing, hotwire Net::HTTP to always output debug to stderr
# (because RestClient log doesn't do plain HTTP trace)
if $APP_TRACE
  require 'logger'
  # RestClient.log = Logger.new(STDERR)
  class Net::HTTP
    old_init = instance_method(:initialize)
    define_method :initialize do |*args, &b|
      old_init.bind(self).call(*args, &b)
      set_debug_output $stderr
    end
  end
end

## config
default_config = {
  :auth_service => "http://radiotag.prototype0.net",
  :tag_service  => "http://radiotag.prototype0.net",
  :http_proxy   => ENV['http_proxy']
}
config = default_config.merge(ConfigHelper.load_config("config/config.yml"))
pp config if $APP_DEBUG

if config[:http_proxy]
  RestClient.proxy = config[:http_proxy]
end

## Radio
class Radio
  STATE_FILE = ConfigHelper.base_path("var", "radio_state.json")
  STATIONS = {
    "BBC Radio 1"      => "0.c221.ce15.ce1.dab",
    "BBC Radio 2"      => "0.c222.ce15.ce1.dab",
    "BBC Radio 3"      => "0.c223.ce15.ce1.dab",
    "BBC Radio 4"      => "0.c224.ce15.ce1.dab",
    "BBC Radio 5 Live" => "0.c225.ce15.ce1.dab",
  }

  attr_reader :state
  attr_accessor :playback_file

  def initialize(authority, resource)
    @authority = authority
    @resource = resource
    @record = Hash.new { |h,k| h[k] = Array.new }
    @playback_file = "recording.json"
    reset
    restore_state
  end

  def dbg(*a)
    pp a if $APP_DEBUG
  end

  def log_state
    dbg [:state, @state]
  end

  def reset
    @state = { }
    @state[:grants] = { }
  end

  def display(key)
    dbg [:display, :key, key, @state[key]]
  end

  def get_registration_key
    response = @resource["/registration_key"].post({
                                                     'grant_scope' => current_grant[:scope],
                                                     'grant_token' => current_grant[:token]
                                                   }) { |response, request, reply| response }
    update_grant(response)
    case response.code
    when 200..299
      @state[:registration_key] = response.headers[:x_radiotag_registration_key]
      @state[:registration_url] = response.headers[:x_radiotag_registration_url]
      p [:REGISTRATION_INFO, @state[:registration_key], @state[:registration_url]]
      enter_pin
    else
      p [:get_registration_key, :UNHANDLED_ERROR, response.code, response]
      nil
    end
  end

  def register
    params = { :registration_key => state[:registration_key] }
    response = @authority["/assoc"].post(params) { |response, request, reply| response }
    case response.code
    when 200..299
      data = JSON.parse(response.body)
      dbg [:registered, data]
      data
    when 400..499
      puts [:register, response.code.to_s, response].join(": ")
      nil
    else
      p [:register, :UNHANDLED_ERROR, response.code, response]
      nil
    end
  end

  def do_tag(token, station, time)
    params = {
      :station => station,
      :time => time
    }
    headers = {
      'X-radiotag-auth-token' => token
    }
    response = @resource["/tag"].post(params, headers) { |response, request, reply| response }
    update_grant(response)
    @last_tag_response_code = response.code
    response
  end

  def tag
    begin
      state[:current_tag] ||= { :station => state[:station][1], :time => Time.now.utc.to_i }

      log_state

      response = do_tag(state[:token], state[:current_tag][:station], state[:current_tag][:time])

      case response.code
      when 401
        if unpaired_grant?
          get_unpaired_token
          if state[:token]
            response = do_tag(state[:token], state[:current_tag][:station], state[:current_tag][:time])

            case response.code
            when 201
              state.delete :current_tag
              log_state
              puts "201 RESPONSE A: " + response
              ok_register_menu
            else
              p [:unpaired_tag_error, response, response.code]
            end
          else
            p [:unpaired_tag_error, "no token", response]
          end
        else
          p [:unpaired_grant?, "malformed response", response]
        end
      when 201
        state.delete(:current_tag)
        state.delete(:registration_key)
        log_state
        puts "201 RESPONSE B: " + response
        ok_register_menu
      when 200
        state.delete(:current_tag)
        log_state
        puts "200 RESPONSE: " + response
        ok_register_menu
      else
        p [:tag, :UNHANDLED_RESPONSE, response.code, response]
      end
    rescue Errno::ECONNREFUSED
      puts "Could not connect to website: is it running?"
      throw :restart
    ensure
      @last_tag_response_code = nil
    end
  end

  def tags
    response = @resource["/tags"].get({ 'X-radiotag-auth-token' => state[:token] }) { |response, request, reply| response }
    case response.code
    when 200..299
      puts response.body
    else
      puts "Error #{response.code} requesting /tags for token #{state[:token]}"
      puts response.body
    end
  end

  def unpaired_grant?
    grant = current_grant
    grant && grant[:scope] == 'unpaired'
  end

  def can_register?
    grant = current_grant
    grant && grant[:scope] == 'can_register'
  end

  def update_grant(response)
    scope = response.headers[:x_radiotag_grant_scope]
    token = response.headers[:x_radiotag_grant_token]
    state[:grants][current_service] = {:scope => scope, :token => token}
  end

  def current_grant
    state[:grants][current_service]
  end

  def get_token
    response = @resource["/register"].post(
                                           {
                                             :registration_key => state[:registration_key],
                                             :pin => state[:pin],
                                           },
                                           {  'X-radiotag-auth-token' => state[:token] }
                                           )  { |response, request, reply| response }
    update_grant(response)
    case response.code
    when 200..299
      # FIXME: should be by current service
      state[:token] = response.headers[:x_radiotag_auth_token]
      state[:account_name] = response.headers[:x_radiotag_account_name]
      log_state

      # if was not unpaired then tag
      if @last_tag_response_code == 200
        tag
      end
    when 400..499
      puts [:get_token, response.code.to_s, response].join(": ")
    else
      p [:get_token, :UNHANDLED_RESPONSE, response.code, response]
    end
  end

  def get_unpaired_token
    response = @resource["/token"].post(
                                        {
                                          'grant_scope' => current_grant[:scope],
                                          'grant_token' => current_grant[:token]
                                        }
                                        )  { |response, request, reply| response }
    update_grant(response)
    case response.code
    when 200..299
      state[:token] = response.headers[:x_radiotag_auth_token]
      log_state
    when 400..499
      puts [:get_unpaired_token, response.code.to_s, response].join(": ")
    else
      p [:get_unpaired_token, :UNHANDLED_RESPONSE, response.code, response]
    end
  end

  def record(method, result)
    @record[method] << result
  end

  def trace_header(text)
    if $APP_TRACE
      STDERR.puts "-" * 60
      STDERR.puts "* #{text}"
      STDERR.puts "-" * 60
    end
  end

  def prompt_enter_pin(pin = "0000")
    if $APP_PLAYBACK
      trace_header "Entering PIN"
      result = @record[this_method].shift
    else
      result = HighLine.new.ask("Enter PIN: ") { |q|
        q.default = pin if pin
        q.validate = /\A[0-9]{4}\Z/
      }
      if $APP_RECORD
        record(this_method, result)
      end
    end
    result
  end

  def prompt_tune
    if $APP_PLAYBACK
      result = @record[this_method].shift
      trace_header "Tuned radio to #{result}"
    else
      hl = HighLine.new
      result = hl.choose do |menu|
        menu.prompt = "Station: "
        menu.choices(*STATIONS.keys)
      end
      if $APP_RECORD
        record(this_method, result)
      end
    end
    result
  end

  def prompt_ok_register
    if $APP_PLAYBACK
      result = @record[this_method].shift
      trace_header "Pressed #{result}"
    else
      hl = HighLine.new
      actions = %w[ok]
      if can_register?
        actions += %w[register]
      end
      result = hl.choose do |menu|
        menu.prompt = "Action: "
        menu.choices(*actions)
      end
      if $APP_RECORD
        record(this_method, result)
      end
    end
    result
  end

  def prompt_menu
    if $APP_PLAYBACK
      result = @record[this_method].shift
      trace_header "Pressed #{result}"
    else
      hl = HighLine.new
      actions = %w[tune tag tags reset dump_state quit]
      if @state[:station].nil?
        actions.delete("tag")
      end
      result = hl.choose do |menu|
        menu.prompt = "Action: "
        menu.choices(*actions)
      end
      if $APP_RECORD
        record(this_method, result)
      end
    end
    result
  end

  def enter_pin(pin = nil)
    state[:pin] = prompt_enter_pin
    if state[:pin] == "0000"
      trace_header "Registering with web front end to get PIN"
      # FIXME: Use stored account details

      # curl -d registration_key=$registration_key -d account_id=$account_id http://localhost:4567/register
      response = @authority["/assoc"].post(
                                           {
                                             :registration_key => state[:registration_key],
                                             # TODO: magic number 9 = account id for 'sean'
                                             :id => 9
                                           }) { |response, request, reply| response }
      case response.code
      when 200..299
        data = JSON.parse(response.body)
        state[:pin] = data["pin"]
      else
        puts "ERROR getting pin"
      end
    end
    trace_header "Entered PIN '#{state[:pin]}'"
    get_token
  end

  def tune
    result = prompt_tune
    @service_id = STATIONS[result]
    @state[:station] = [result, @service_id]
  end

  def restore_state
    if File.exist?(STATE_FILE)
      data = JSON.parse(File.read(STATE_FILE))
      @state = Hash[data.map{ |k, v| [k.to_sym, v ]}]
    end
  end

  def save_state
    File.open(STATE_FILE, "wb") do |file|
      file.write @state.to_json
    end
  end

  def dump_state
    pp @state
  end

  def save_recording
    if $APP_RECORD
      File.open(playback_file, "wb") do |file|
        file.write @record.to_json
      end
    end
  end

  def load_recording
    if $APP_PLAYBACK
      @record = JSON.parse(File.read(playback_file))
    end
  end

  def quit
    save_state
    save_recording
    throw :quit
  end

  def current_station
    @state[:station] && @state[:station][0] || "(untuned)"
  end

  def current_service
    TagService
  end

  def ok_register_menu
    result = prompt_ok_register
    case result
    when "ok"
      puts "OK"
    when "register"
      get_registration_key
    else
      puts "Error"
    end
  end

  def menu
    puts "Listening to #{current_station}"
    puts "Console RadioTag Simulator (q to quit)"
    result = prompt_menu
    send(result)
  end

  def run
    load_recording
    catch :quit do
      loop do
        catch :restart do
          begin
            menu
          rescue EOFError
            throw :quit
          end
        end
      end
    end
  end
end

AuthService = RestClient::Resource.new(config[:auth_service])
TagService = RestClient::Resource.new(config[:tag_service])

catch :cancel do
  radio = Radio.new(AuthService, TagService)
  if $APP_RECORD or $APP_PLAYBACK
    if ARGV.size > 0
      radio.playback_file = ARGV[0]
    end
  end
  radio.run
end

