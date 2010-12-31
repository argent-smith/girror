# 
# girror config for current mirror
#
module Config

  # Program options for the current instance
  OPTIONS = {
    # custom commit message
    :commit_msg => Proc.new {"State at #{Time.now}"},
  
    # local filename encoding
    :lenc => 'cp1251',
    
    # remote filename encoding
    :renc => 'koi8-r'
  }

end