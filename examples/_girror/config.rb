# -*- Ruby -*-
# girror config for current mirror
#
module Config

  # Program options for the current instance
  OPTIONS = {
    # custom commit message
    :commit_msg => Proc.new {"State at #{Time.now}"},
  
    # local filename encoding
    :lenc => 'koi8-r',
    
    # remote filename encoding
    :renc => 'cp1251',

    # some specific ssh options
    # currently available are:
    # - :keys
    # - :compression
    :ssh => {
      # specific ssh secret key files are listed in this array
      :keys        => ['/home/paul/.ssh/id_dsa_somekey'],

      # you may set this to true or one of algo settings 
      # (see docs for Net::SSH.start)
      :compression => true
    }

  }

end
