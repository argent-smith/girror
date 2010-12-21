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
            log "Connected to remote #{@host} as #{@user}"

            dl_if_needed @path

            log "Disconnected from remote #{@host}"
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

      # On-demand fetcher
      def dl_if_needed name
        debug "RNA: #{name}"
        lname = File.join '.', name.gsub(/^#{@path}/,''); debug "LNA: #{lname}"

        # get and hold the current direntry's stat in here
        rs  = @sftp.stat!(name); s_rs = [Time.at(rs.mtime), Time.at(rs.atime), rs.uid, rs.gid, "%o" % rs.permissions].inspect
        debug "Remote stat for #{name} => #{s_rs}"

        # remote type filter: we only work with types 1..2 (regular, dir)
        begin
          debug "Remote file type #{rs.type} isn't supported, ignoring."
          return
        end if rs.type > 2

        # remove the local entry if local/remote entry type differ
        if File.exist? lname
          if (
              rs.type != case File.ftype lname
              when "file"      then 1
              when "directory" then 2
              end
            )
            remove_entry_secure lname, :force => true
          end
        end

        # do the type-specific fetch operations
        case rs.type
        when 1
          lrs = File.lstat(lname) if File.exist?(lname)
          if (lrs.nil? or (lrs.mtime.to_i < rs.mtime))
            log "Downloading #{name} -> #{lname}"
            @sftp.download! name, lname
            set_attrs = true
          end
        when 2
          # here we've got a dir
          # create the dir locally if needed
          unless File.exist?(lname)
            log "Getting #{name} -> #{lname} | #{s_rs}"
            mkdir lname
            set_attrs = true
          end
          # recurse into the dir
          @sftp.dir.foreach name do |e|
            n = File.join name, e.name
            dl_if_needed n unless ((e.name =~ /^\.{1,2}$/) or (n == File.join(@path, ".git")))
          end
        end
        
        # do the common after-fetch tasks (chown, chmod, utime)
        unless lname == "./"
          chown rs.uid, rs.gid, lname
          chmod rs.permissions, lname
          File.utime rs.atime, rs.mtime, lname
        end if set_attrs
      end
    end
  end
end