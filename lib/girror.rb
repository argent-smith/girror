# Author:: Pavel Argentov <argentoff@gmail.com>
#
# Girror library code.
#

######## Utility

$:.unshift File.dirname(__FILE__) # For use/testing when no gem is installed

# Require all of the Ruby files in the given directory.
#
# path - The String relative path from here to the directory.
#
# Returns nothing.
def require_all(path)
  glob = File.join(File.dirname(__FILE__), path, '*.rb')
  Dir[glob].each do |f|
    require f
  end
end

##### Requires:
require 'net/sftp'
require 'fileutils'; include FileUtils
require 'git'

module Girror
  VERSION = "0.0.0"

  class << self

    # Runs the program: sorta 'main'.
    def run ops

      # main logs go here
      @log = Logger.new STDERR
      log "Starting"

      # debug logs go here
      @debug = Logger.new STDERR if ops[:verbose]
      debug "Current options are: #{ops.inspect}"

      # check the validity of a local directory
      @git = Git.open(ops[:to], :log => Logger.new(STDERR))
      cd ops[:to]; log "Changed to #{pwd}"
      
      # Check the validity of a remote url and run the remote connection
      if ops[:from] =~ /^((\w+)(:(\w+))?@)?(.+):(.*)$/
        $2.nil? ? @user = ENV["USERNAME"] : @user = $2
        @pass = $4
        @host = $5
        @path = $6

        debug "Remote data specified as: login: #{@user}; pass: #{@pass.inspect}; host: #{@host}; path: #{@path}"
        Net::SFTP.start(@host, @user, :password => @pass) do |s|
          @sftp = s
          debug "Opened sftp session #{@sftp}"

          dl_if_needed @path

          debug "Closing sftp session #{@sftp}"
        end

      else
        raise "Bad remote specification!"
      end

      log "Finishing"
    end

    # Does STDERR.puts of a given string if debugging mode is set.
    def debug string
      @debug.debug string if @debug
    end

    def log string
      @log.info string
    end

    def dl_if_needed name
      if @sftp.file.directory? name
        debug "DIR: #{name}"
        @sftp.dir.foreach name do |e|
          n = File.join name, e.name
          dl_if_needed n unless e.name =~ /^\.{1,2}$/
        end
      else
        debug "FIL: #{name}"
      end
    end

  end

end
