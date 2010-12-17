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
require 'fileutils'
require 'git'

module Girror
  VERSION = "0.0.0"

  # Encapsulates the app logic.
  class Application

    class << self # class things
      include FileUtils
      # Runs the app.
      def run ops

        # main logs go here
        @log = Logger.new STDERR
        log "Starting"

        # debug logs go here
        @debug = Logger.new STDERR if ops[:verbose]
        debug "Current options are: #{ops.inspect}"

        # check the validity of a local directory
        @lpath = ops[:to]                                   # local save path
        @git = Git.open(@lpath, :log => Logger.new(STDERR)) # local git repo
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
        if @sftp.file.directory? name  # here we've got a dir
          debug "DIR: #{name}"
          # create/adjust the dir locally if needed
          # - get remote owner & mode
          # - mkdir/chown/chmod as needed
          @sftp.dir.foreach name do |e|
            n = File.join name, e.name
            dl_if_needed n unless ((e.name =~ /^\.{1,2}$/) or (n == File.join(@path, ".git")))
          end
        else                           # here's a file OR SYMLINK (!)
          lfile = File.join '.', name.gsub(/^#{@path}/,''); debug "LFI: #{lfile}"
          debug "FIL: #{name}"
          if File.exists? lfile
            debug "File exists in local tree: skipping"
          else
            debug "Downloading #{name} -> #{lfile}"
            #@sftp.download! name, lfile, :progress => CustomHandler.new(self)
          end
        end
      end
    end
  end

  # Displays the download progress.
  class CustomHandler

    # Initialises the CustomHandler. Takes 'app' parameter which holds the
    # Application where 'log' method should be found. For further reference see
    # docs of 'dl_if_needed' method.
    def initialize app
      @app = app
    end

    def on_open(downloader, file)
      @app.log "starting download: #{file.remote} -> #{file.local} (#{file.size} bytes)"
    end

    def on_get(downloader, file, offset, data)
      @app.log "writing #{data.length} bytes to #{file.local} starting at #{offset}"
    end

    def on_close(downloader, file)
      @app.log "finished with #{file.remote}"
    end

    def on_mkdir(downloader, path)
      @app.log "creating directory #{path}"
    end

    def on_finish(downloader)
      @app.log "all done!"
    end
  end

end