# -*- Ruby -*-
# girror config for current mirror
#
module Config

  # Program options for the current instance
  OPTIONS = {
    # custom commit message
    :commit_msg => "#{eval '"State for #{Time.now}, comitted by Pavel Argentov <argentoff@gmail.com>"'}",
  
    # local filename encoding
    :lenc => 'cp1251',
    
    # remote filename encoding
    :renc => 'koi8-r'
  }

end