require 'thor'
require 'term/ansicolor'

module Rpush
  class CLI < Thor
    include Term::ANSIColor

    def self.detect_rails?
      ['bin/rails', 'script/rails'].any? { |path| File.exist?(path) }
    end

    def self.default_config_path
      detect_rails? ? 'config/initializers/rpush.rb' : 'config/rpush.rb'
    end

    class_option :config, type: :string, aliases: '-c', default: default_config_path
    class_option :rails_env, type: :string, aliases: '-e', default: 'development'

    option :foreground, type: :boolean, aliases: '-f', default: false
    option 'pid-file', type: :string, aliases: '-p'
    desc 'start', 'Start Rpush'
    def start
      if detect_rails? && options[:rails_env]
        STDOUT.write "* Booting Rails '#{options[:rails_env]}' environment... "
        STDOUT.flush
        ENV['RAILS_ENV'] = options[:rails_env]
        load 'config/environment.rb'
        puts green('✔')
      end

      load_config
      require 'rpush/daemon'
      Rpush::Daemon.start
    end

    desc 'stop', 'Stop Rpush'
    option 'pid-file', type: :string, aliases: '-p'
    def stop
      load_config

      if Rpush.config.pid_file.blank?
        STDERR.puts('*' + red("config.pid_file is not set."))
        return
      end

      if File.exist?(Rpush.config.pid_file)
        pid = File.read(Rpush.config.pid_file).strip.to_i
        STDOUT.write "* Stopping Rpush (pid #{pid})... "
        STDOUT.flush
        Process.kill('TERM', pid)

        while true
          begin
            Process.getpgid(pid)
            sleep 0.05
          rescue Errno::ESRCH
            break
          end
        end

        puts green('✔')
      else
        STDERR.puts("* Rpush isn't running? #{Rpush.config.pid_file} does not exist.")
        return
      end
    end

    desc 'init', 'Initialize Rpush into the current directory.'
    option 'active-record', type: :boolean, desc: 'Install ActiveRecord migrations.'
    def init
      require 'rails/generators'

      puts "* #{green('Installing config...')}"
      $RPUSH_CONFIG_PATH = default_config_path
      Rails::Generators.invoke('rpush_config')

      install_migrations = options['active-record']

      if !options.key?('active-record')
        has_answer = false
        until has_answer
          STDOUT.write "\n* #{green('Install ActiveRecord migrations?')} [y/n]: "
          STDOUT.flush
          answer = STDIN.gets.chomp.downcase
          has_answer = ['y', 'n'].include?(answer)
        end

        install_migrations = answer == 'y'
      end

      Rails::Generators.invoke('rpush_migration') if install_migrations

      puts "\n* #{green('Next steps:')}"
      puts "  - Run 'db:migrate'." if install_migrations
      puts "  - Create your first app, see https://github.com/rpush/rpush for examples."
      puts "  - Run 'rpush help' for commands and options."
    end

    private

    def detect_rails?
      self.class.detect_rails?
    end

    def default_config_path
      self.class.default_config_path
    end

    def load_config
      if !File.exist?(options[:config])
        STDERR.puts(red('ERROR: ') + "#{options[:config]} does not exist. Please run 'rpush init' to generate it or specify the --config option.")
        exit 1
      else
        load options[:config]
        Rpush.config.update(options)
      end
    end
  end
end
