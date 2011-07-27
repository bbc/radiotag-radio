require 'yaml'
require_relative 'erb_binding'

module ConfigHelper
  extend self

  def base_path(*path)
    # if path starts with / don't prefix
    if path.first =~ /^\//
      File.join(*path)
    else
      File.expand_path(File.join(File.dirname(__FILE__), '..', *path))
    end
  end

  def load_config(filename, erb_params = { })
    path = base_path(filename)
    if !File.exist?(path)
      abort "Configuration file #{path} does not exist"
    end
    res = load_from_path(path, erb_params)
    if res
      res
    else
      { }
    end
  end

  def load_from_path(path, erb_params = { })
    YAML::load(ErbBinding.erb(File.read(path), erb_params))
  end
end
