module GenerateID
  def rand_token(n = 4)
    n.times.map{|x| (65 + rand(26)).chr }.join('')
  end

  def rand_pin(n = 4)
    n.times.map{|x| (48 + rand(10)).chr }.join('')
  end

  def rand_hex(n = 8)
    n.times.map{|x| "%x" % rand(16) }.join('')
  end

  def uuid
    #`uuidgen`.chomp
    rand_hex(8)
  end
  extend self
end

