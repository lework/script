#!/opt/gitlab/embedded/bin/ruby
# Authors: gitlab.com/cody
# This script provides a unified method of gathering system information and
# GitLab application information. Please consider this script to be in an Alpha
# state.

require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'logger'
require 'optparse'
require 'pathname'

# allows logging to stdout and a log file
# https://stackoverflow.com/a/6407200
class MultiIO
  def initialize(*targets)
    @targets = targets
  end

  def write(*args)
    @targets.each { |t| t.write(*args) }
  end

  def close
    @targets.each(&:close)
  end
end

module GitLabSOS
  # If you intend to add a large file to this list, you'll need to change the
  # file.read call to something that streams rather than slurps
  module Files
    def list_files
      [
        { source: '/opt/gitlab/version-manifest.json', destination: './opt/gitlab/version-manifest.json' },
        { source: '/opt/gitlab/version-manifest.txt', destination: './opt/gitlab/version-manifest.txt' },
        { source: '/var/log/messages', destination: './var/log/messages' },
        { source: '/var/log/syslog', destination: './var/log/syslog' },
        { source: '/proc/mounts', destination: 'mount' },
        { source: '/proc/meminfo', destination: 'meminfo' },
        { source: '/proc/cpuinfo', destination: 'cpuinfo' },
        { source: '/etc/selinux/config', destination: './etc/selinux/config' },
        { source: '/proc/sys/kernel/tainted', destination: 'tainted' },
        { source: '/etc/os-release', destination: './etc/os-release' },
        { source: '/etc/fstab', destination: './etc/fstab' },
        { source: '/etc/security/limits.conf', destination: './etc/security/limits.conf' },
        { source: '/proc/sys/vm/swappiness', destination: 'running_swappiness' },
        { source: '/proc/pressure/io', destination: 'pressure_io.txt' },
        { source: '/proc/pressure/memory', destination: 'pressure_mem.txt' },
        { source: '/proc/pressure/cpu', destination: 'pressure_cpu.txt' }
      ]
    end

    def run_files
      list_files.each do |file_info|
        dest = File.join(tmp_dir, file_info[:destination])
        logger.debug "processing #{file_info[:source]}.."
        result = begin
          # this works better than FileUtils.cp for stuff like /proc/mounts
          `tail -c #{options[:max_file_size]} #{file_info[:source]}`
        rescue Errno::ENOENT => e
          # file doesn't exist
          e.message
        end
        FileUtils.mkdir_p(File.dirname(dest))
        logger.debug "writing #{result.bytesize} bytes to #{dest}"
        File.write(dest, result)
      end
    end

    def run_gitlab_rb
      return unless options[:grab_config]
      # don't run if __dir__ can't be resolved (i.e. downloaded via curl)
      return unless __dir__

      sanitizer = File.join(__dir__, 'sanitizer/sanitizer')
      if File.file?(sanitizer)
        logger.info 'Sanitizer module found. `gitlab.rb` file will be collected.'
        logger.info 'A copy will be printed on the screen for you to review.'
      else
        logger.info 'Sanitizer not found. `gitlab.rb` file will not be collected'
        return
      end

      dest = File.join(tmp_dir, 'etc/gitlab/gitlab.rb')
      FileUtils.mkdir_p(File.dirname(dest))

      logger.info 'Sanitizing /etc/gitlab/gitlab.rb file'
      `/opt/gitlab/embedded/bin/ruby #{sanitizer} --save #{dest}`

      # We use 'puts' to show the sanitized gitlab.rb file without
      # logging it in gitlabsos.log
      puts ''
      puts '======================== Sanitized gitlab.rb ========================'
      puts 'PLEASE CAREFULLY REVIEW THIS FILE FOR ANY SENSITIVE INFO'
      puts 'THE BELOW INFO WILL BE INCLUDED (SANITIZED) IN YOUR GITLABSOS ARCHIVE'
      puts '====================================================================='
      puts File.read(dest)
      puts '====================================================================='
      puts 'NOTICE: You can skip this with --skip-config'
      puts '====================================================================='
      puts ''
    end
  end

  module Commands
    # Add commands to this list that could help collect useful information
    # cmd is the command that you want to run, including its options
    # result_path is the filename for the output of the cmd that you want to run.
    def list_commands
      [
        { cmd: 'dmesg -T', result_path: 'dmesg' },
        { cmd: 'uname -a', result_path: 'uname' },
        { cmd: 'su - git -c "ulimit -a"', result_path: 'ulimit' },
        { cmd: 'hostname --fqdn', result_path: 'hostname' },
        { cmd: 'getenforce', result_path: 'getenforce' },
        { cmd: 'sestatus', result_path: 'sestatus' },
        { cmd: 'systemctl list-unit-files', result_path: 'systemctl_unit_files' },
        { cmd: 'uptime', result_path: 'uptime' },
        { cmd: 'df -hT', result_path: 'df_hT' },
        { cmd: 'df -iT', result_path: 'df_inodes' },
        { cmd: 'free -m', result_path: 'free_m' },
        { cmd: 'ps -eo user,pid,%cpu,%mem,vsz,rss,stat,start,time,wchan:24,command', result_path: 'ps' },
        { cmd: 'netstat -txnpl', result_path: 'netstat' },
        { cmd: 'netstat -i', result_path: 'netstat_i' },
        { cmd: 'vmstat -w 1 10', result_path: 'vmstat' },
        { cmd: 'mpstat -P ALL 1 10', result_path: 'mpstat' },
        { cmd: 'pidstat -l 1 15', result_path: 'pidstat' },
        { cmd: 'iostat -xz 1 10', result_path: 'iostat' },
        { cmd: 'nfsiostat 1 10', result_path: 'nfsiostat' },
        { cmd: 'nfsstat -v', result_path: 'nfsstat' },
        { cmd: 'iotop -aoPqt -b -d 1 -n 10', result_path: 'iotop' },
        { cmd: 'top -c -b -n 1 -o %CPU', result_path: 'top_cpu' },
        { cmd: 'top -c -b -n 1 -o RES', result_path: 'top_res' },
        { cmd: 'rpm -vV gitlab-ee', result_path: 'rpm_verify' },
        { cmd: 'sar -n DEV 1 10', result_path: 'sar_dev' },
        { cmd: 'sar -n TCP,ETCP 1 10', result_path: 'sar_tcp' },
        { cmd: 'lscpu', result_path: 'lscpu' },
        { cmd: 'ntpq -pn', result_path: 'ntpq' },
        { cmd: 'timedatectl', result_path: 'timedatectl' },
        { cmd: 'gitlab-ctl status', result_path: 'gitlab_status' },
        { cmd: 'gitlab-rake db:migrate:status', result_path: 'gitlab_migrations' },
        { cmd: 'ss -paxioe', result_path: 'sockstat' },
        { cmd: 'sysctl -a', result_path: 'sysctl_a' },
        { cmd: 'ifconfig', result_path: 'ifconfig' },
        { cmd: 'ip address', result_path: 'ip_address' }
      ]
    end

    def run_commands
      logger.info 'Collecting diagnostics. This will probably take a few minutes..'
      list_commands.each do |cmd_info|
        dest = File.join(tmp_dir, cmd_info[:result_path])
        full_cmd = "#{cmd_info[:cmd]} | tail -c #{options[:max_file_size]}"
        logger.debug "exec: #{full_cmd}"
        result = begin
          out, err, _status = Open3.capture3(full_cmd)
          out + err
        end
        File.write(dest, result)
      end
    end
  end

  module LogDirectories
    def run_log_dirs
      logger.info 'Getting GitLab logs..'
      logger.debug 'determining log directories..'

      # Ensure empty array if gitlab config file couldn't found or read
      log_dirs = config.key?('normal') ? deep_fetch(config['normal'], 'log_directory') : []
      log_dirs << '/var/log/gitlab'
      logger.debug "using #{log_dirs}"

      log_dirs.uniq.each do |log_dir|
        unless Dir.exist?(log_dir)
          logger.warn "log directory '#{log_dir}' does not exist or is not a directory"
          next
        end

        logger.debug "searching #{log_dir} for log files.."

        find_files(log_dir).each do |log|
          process_log(log) if log.mtime > Time.now - (60 * 60 * 12) && log.basename.to_s !~ /.*.gz|^@|lock/
        end
      end
    end

    def process_log(log)
      begin # rubocop:disable Style/RedundantBegin -- To maintain compatibility with Ruby < 2.5
        logger.debug "processing log - #{log}.."
        content = `tail -c #{options[:max_file_size]} #{log}`
        content = content.lines.drop(1).join unless content.lines.count < 2
        FileUtils.mkdir_p(File.dirname(File.join(tmp_dir, log)))
        logger.debug "writing #{content.bytesize} bytes to #{File.join(tmp_dir, log)}"
        File.write(File.join(tmp_dir, log), content)
      rescue => e
        logger.error "could not process log - #{log}"
        logger.error e.message
      end
    end

    def find_files(*paths)
      paths.flatten.map do |path|
        path = Pathname.new(path)
        path.file? ? [path] : find_files(path.children)
      end.flatten
    end
  end

  # This is the first itteration designed to make
  #   https://gitlab.com/gitlab-com/support/toolbox/gitlabsos/issues/11 and
  #   https://gitlab.com/gitlab-com/support/toolbox/gitlabsos/issues/7 easier and
  # any aditional options/filter we can think of in the futher.
  class Client
    attr_accessor :options, :logger, :log_file, :tmp_dir, :config
    include Files
    include Commands
    include LogDirectories

    HOSTNAME = `hostname`.strip
    REPORT_NAME = "gitlabsos.#{HOSTNAME}_#{Time.now.strftime('%Y%m%d%H%M%S')}".freeze
    TMP_DIR = File.join(ENV['TMP'] || ENV['TMPDIR'] || '/tmp', REPORT_NAME)

    def initialize(args)
      @args = args
      parse_options!
      setup_logger
      root_check
      setup_config
      run
    end

    def setup_config
      self.config = {}

      config_file = Dir.glob('/opt/gitlab/embedded/nodes/*.json').max_by { |f| File.mtime(f) }

      # Ignore if missing
      return nil unless config_file

      # Grab first file
      self.config = JSON.parse File.read(config_file)
    end

    def default_options
      {
        output_file: File.expand_path("./#{REPORT_NAME}.tar.gz"),
        logs_only: false,
        log_level: Logger::INFO,
        root_check: true,
        max_file_size: 10 * 1_000_000, # 10MB
        grab_config: true
      }
    end

    def root_check
      raise 'Script must be run as root' unless Process.uid.zero? || !options[:root_check]
    end

    def create_temp_directory
      self.tmp_dir = FileUtils.mkdir_p(TMP_DIR).join
    rescue Errno::ENOENT => e
      # TODO: Handle error Permission denied.
      e.message
    end

    def setup_logger
      create_temp_directory
      self.log_file ||= File.open(File.join(TMP_DIR, 'gitlabsos.log'), 'a')
      self.logger = Logger.new MultiIO.new(STDOUT, log_file)
      logger.level = options[:log_level]
      logger.progname = 'gitlabsos'
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%dT%H:%M:%S.%6N')}] #{severity} -- #{progname}: #{msg}\n"
      end
    end

    # this method is used to fetch all values out of a hash for any given key
    # I'm just using it to get custom log directories
    def deep_fetch(hash, key)
      hash.values.map do |obj|
        next if obj.class != Hash

        if obj.key? key
          obj[key]
        else
          deep_fetch(obj, key)
        end
      end.flatten.compact
    end

    def parse_options!
      self.options = default_options

      OptionParser.new do |opts|
        opts.banner = 'Usage: gitlabsos.rb [options]'

        opts.on('-o FILE', '--output-file FILE', 'Write gitlabsos report to FILE') do |file|
          options[:output_file] = File.expand_path(file)
        end

        opts.on('--debug', 'Set the log level to debug') do
          options[:log_level] = Logger::DEBUG
        end

        opts.on('--skip-root-check', 'Run the script as non-root. Warning: script might fail') do
          options[:root_check] = false
        end

        opts.on('--skip-config', 'Don\'t include a sanitized copy of the gitlab.rb configuration file.') do
          options[:grab_config] = false
        end

        opts.on('--max-file-size MB', 'Set the max file size (in megabytes) for any file in the report') do |mb|
          options[:max_file_size] = mb.to_i * 1_000_000
        end

        opts.on('-h', '--help', 'Prints this help') do
          puts opts
          exit
        end
      end.parse!(@args)
    end

    def run
      logger.info 'Starting gitlabsos report'
      logger.info 'Gathering configuration and system info..'

      run_files
      run_commands
      run_log_dirs
      run_gitlab_rb

      logger.info 'Report finished.'
      log_file.close

      puts "Saving to: '#{options[:output_file]}'"
      system("tar -czf #{options[:output_file]} #{File.basename(TMP_DIR)}",
             chdir: File.dirname(TMP_DIR))
      FileUtils.remove_dir(TMP_DIR)
    end
  end
end

GitLabSOS::Client.new(ARGV)
