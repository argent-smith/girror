# Author::    Pavel Argentov <argentoff@gmail.com>
# Copyright:: (c) 2010-2011 Pavel Argentov
# License::   see LICENSE.txt
#
# Girror library code, the internals. Since the whole app is a CLI utility, 
# there's not a lot to document here.
# 
# The library now contains only one module Girror which contains class Application
# which is the app logic container. The methods have some documentation in the corresponding
# section (Girror::Application).
# 
# == Disclaimer
# 
# This documentation is written as an aid to further development of the program.
# For more user-friendly documentation see README.rdoc file.
#

######## Utility

$:.unshift File.dirname(__FILE__) # For use/testing when no gem is installed

# Require all of the Ruby files in the given directory.
#
# path - The String relative path from here to the directory.
#
# Returns nothing.
def require_all(path) # :nodoc:
  glob = File.join(File.dirname(__FILE__), path, '*.rb')
  Dir[glob].each do |f|
    require f
  end
end

######## Requires
require 'singleton'
require 'net/sftp'
require 'fileutils'
require 'git'
require 'iconv'

# This module encapsulates *girror*'s namespace.
module Girror
  # Version of the library.
  VERSION = "0.0.3"
  
  # Regexp to filter out 'technical' files which aren't normally a part of
  # the mirrored tree and therefore should be _ignored_.
  FILTER_RE = /^((\.((\.{0,1})|((git)(ignore)?)))|(_girror))$/

  # Application logic container.
  class Application
    include Singleton

    class << self # class things
      include FileUtils
      
      # Runs the app. Much like the C's main().
      def run ops
        # Logging setup
        @log = case ops[:log]
        when 'syslog'
          unless ENV['OS'] == 'Windows_NT'
            require 'syslog_logger'
            SyslogLogger.new('girror')
          else
            Logger.new STDERR
          end
        when nil
          Logger.new STDERR
        else
          Logger.new ops[:log]
        end
        @log.datetime_format = "%Y-%m-%d %H:%M:%S " if Logger.class == Logger
        log "Starting"
        @debug = true if ops[:verbose]
        debug "Current options are: #{ops.inspect}"

        # check the validity of a local directory
        @lpath = ops[:to]       # local save path
        log "Opening local git repo at #{@lpath}"
        @git = Git.open(@lpath) # local git repo
        
        cd ops[:to]; log "Changed to #{pwd}"
        
        # read the config and use CLI ops to override it
        $:.unshift(File.join(".", "_girror"))
        begin
          require 'config'
          ops = Config::OPTIONS.merge ops
          
          begin 
            debug "Program options:"
            ops.each do |pair|
              debug pair.inspect
            end
          end
          
        rescue LoadError => d
          log "Not using stored config: #{d.message}"
        end
                
        # set commit message for git
        ops[:commit_msg].nil? ? @commit_msg = Proc.new { Time.now.to_s } : @commit_msg = ops[:commit_msg]
        
        # name conversion encodings for Iconv
        ops[:renc].nil? ? @renc = "utf-8" :  @renc = ops[:renc]
        ops[:lenc].nil? ? @lenc = "utf-8" :  @lenc = ops[:lenc]

        # Check the validity of a remote url and run the remote connection
        if ops[:from] =~ /^((\w+)(:(\w+))?@)?(.+):(.*)$/
          $2.nil? ? @user = ENV["USERNAME"] : @user = $2
          @pass = $4
          @host = $5
          @path = $6

          debug "Remote data specified as: login: #{@user}; pass: #{@pass.inspect}; host: #{@host}; path: #{@path}"
          Net::SFTP.start(@host, @user, 
			  :password => @pass,
			  :keys => ops[:ssh][:keys],
			  :compression => ops[:ssh][:compression]
			 ) do |s|
            @sftp = s
            log "Connected to remote #{@host} as #{@user}"

            dl_if_needed @path

            log "Disconnected from remote #{@host}"
            
            # fix the local tree in the git repo
            begin
              log "Committing changes to local git repo"
              @git.add
              msg = if @commit_msg.class == Proc then @commit_msg.call
              else @commit_msg
              end . to_s
              @git.commit msg, :add_all => true
            rescue Git::GitExecuteError => detail
              case detail.message
              when /nothing to commit/
                log "Nothing to commit"
              else
                log detail.message
              end
            end
            
          end
     
        else
          raise "Bad remote specification!"
        end

        log "Finishing"
      end

      # Writes a debug message to @log.
      def debug string
        @log.debug string if @debug
      end

      # Writes a log message to @log.
      def log string
        @log.info string
      end

      # On-demand fetcher. Recursively fetches a directory entry 'name' (String) 
      # if there's no local copy of it or the remote mtime is newer or the 
      # attributes are to be updated.
      def dl_if_needed name
        debug "RNA: #{name}"
        lname = econv(File.join '.', name.gsub(/^#{@path}/,'')); debug "LNA: #{lname}"

        # get and hold the current direntry's stat in here
        begin
          rs  = @sftp.stat!(name); s_rs = [Time.at(rs.mtime), Time.at(rs.atime), rs.uid, rs.gid, "%o" % rs.permissions].inspect
        rescue Net::SFTP::StatusException => detail
          return if detail.code == 2 # silently ignore the broken remote link
        end
        debug "Remote stat for #{name} => #{s_rs}"

        # remote type filter: we only work with types 1..2 (regular, dir)
        begin
          debug "Remote file type #{rs.type} isn't supported, ignoring."
          return
        end if rs.type > 2

        # remove the local entry if local/remote entry type differ;
        # else compare remote/local owner/mode and schedule the update.
        if File.exist? lname
          if (
              rs.type != case File.ftype lname
              when "file"      then 1
              when "directory" then 2
              end
            )
            remove_entry_secure lname, :force => true
          else
            lrs = File.stat(lname)
            # we do mode comparison on Unices only,
            # and owner compaison only if we are root
            unless ENV['OS'] == "Windows_NT"
              set_attrs = true unless (
                if ENV['EUID'] == 0
                  debug "Comparing: #{[rs.permissions, rs.uid, rs.gid].inspect} <=> #{[lrs.mode, lrs.uid, lrs.gid].inspect}"
                  [lrs.mode, lrs.uid, lrs.gid] == [rs.permissions, rs.uid, rs.gid]
                else
                  debug "Comparing: #{rs.permissions} <=> #{lrs.mode}"
                  lrs.mode == rs.permissions
                end
              )
            end
          end
        end

        # do the type-specific fetch operations
        case rs.type
        when 1
          if (lrs.nil? or (lrs.mtime.to_i < rs.mtime))
            log "Fetching file #{name} -> #{lname.force_encoding("BINARY")} (#{rs.size} bytes)"
            @sftp.download! name, lname
            set_attrs = true
          end
        when 2
          # here we've got a dir
          # create the dir locally if needed
          unless File.exist?(lname)
            log "Fetching directory #{name} -> #{lname.force_encoding("BINARY")} | #{s_rs}"
            mkdir lname
            set_attrs = true
          end
          # recurse into the dir; get the remote list
          rlist = @sftp.dir.entries(name).map do |e| 
            unless e.name =~ FILTER_RE
              dl_if_needed(File.join(name, e.name))
              Iconv.conv("utf-8", @renc, e.name)
            end
          end . compact
          
          # get the local list
          llist = Dir.entries(lname).map do |n|
            Iconv.conv("utf-8", @lenc, n) unless n =~ FILTER_RE
          end . compact
          
          # differentiate the lists; remove what's needed from local repo
          diff = llist - rlist
          diff.each do |n|
            n = File.join(lname, n)
            log "Removing #{n}"
            @git.remove n, :recursive => true
          end
          
        end
        
        # do the common after-fetch tasks (chown, chmod, utime)
        unless lname == "./"
          unless ENV['OS'] == "Windows_NT"     # chmod/chown issues on that platform
            if ENV['EUID'] == 0
              log "Setting owner: #{lname} => #{[rs.uid, rs.gid].inspect}"
              File.chown rs.uid, rs.gid, lname 
            end
            log "Setting mode: #{lname} => #{"%o" % rs.permissions}"
            File.chmod rs.permissions, lname
          end
          log "Setting mtime: #{lname} => #{[rs.atime, rs.mtime].map{|t| Time.at(t).strftime("%Y-%m-%d %H:%M:%S")}.inspect}"
          File.utime rs.atime, rs.mtime, lname
        end if set_attrs
      end

      # Converts the String str from @renc to @lenc if both @renc and @lenc are 
      # set and aren't equal.
      # 
      # Returns the converted String.
      def econv str
        ((@lenc == @renc) or (@lenc.nil? or @renc.nil?)) ?
          str : Iconv.conv(@lenc, @renc, str)
      end

    end
  end
end
