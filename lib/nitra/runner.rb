require 'stringio'

class Nitra::Runner
  attr_reader :configuration, :server_channel, :runner_id, :workers, :tasks

  def initialize(configuration, server_channel, runner_id)
    ENV["RAILS_ENV"] = configuration.environment

    @workers           = {}
    @runner_id         = runner_id
    @configuration     = configuration
    @server_channel    = server_channel
    @tasks             = Nitra::Tasks.new(self)

    configuration.calculate_default_process_count
    server_channel.raise_epipe_on_write_error = true
  end

  def run
    tasks.run(:before_runner)

    load_rails_environment

    tasks.run(:before_worker, configuration.process_count)

    start_workers

    trap("SIGTERM") { $aborted = true }
    trap("SIGINT") { $aborted = true }

    hand_out_files_to_workers

    tasks.run(:after_runner)
  rescue => e
    server_channel.write("command" => "error", "process" => "runner", "text" => "#{e.message}\n#{e.backtrace.join "\n"}", "on" => runner_id) rescue nil
    kill_workers
  rescue Errno::EPIPE
  ensure
    trap("SIGTERM", "DEFAULT")
    trap("SIGINT", "DEFAULT")
  end

  def debug(*text)
    if configuration.debug
      server_channel.write("command" => "debug", "text" => text.join, "on" => runner_id)
    end
  end

  protected

  def load_rails_environment
    return unless File.file?('config/application.rb')
    server_channel.write("command" => "starting", "framework" => "rails", "on" => runner_id)

    ENV["TEST_ENV_NUMBER"] = "1"

    output = Nitra::Utils.capture_output do
      require './config/application'
      Rails.application.require_environment!
      ActiveRecord::Base.connection.disconnect!
    end

    server_channel.write("command" => "started", "framework" => "rails", "on" => runner_id)
    server_channel.write("command" => "stdout", "process" => "rails initialisation", "text" => output, "on" => runner_id) if configuration.debug
  end

  def start_workers
    (1..configuration.process_count).collect do |index|
      start_worker(index, configuration.frameworks.first)
    end
  end

  def start_worker(index, framework)
    pid, channel = Nitra::Workers::Worker.worker_classes[framework].new(runner_id, index, configuration).fork_and_run
    workers[index] = {:pid => pid, :channel => channel}
  end

  def worker_channels
    workers.collect {|index, worker_hash| worker_hash[:channel]}
  end

  def hand_out_files_to_workers
    while !$aborted && workers.length > 0
      Nitra::Channel.read_select(worker_channels + [server_channel]).each do |channel|

        # This is our back-channel that lets us know in case the master is dead.
        kill_workers if channel == server_channel && server_channel.rd.eof?

        unless data = channel.read
          worker_number = worker_number_of(channel)
          debug "Worker #{worker_number} unexpectedly died."
          workers.delete worker_number
          next
        end

        # we pass all commands straight through to the master - the workers aren't allowed to
        # communicate with it directly because they would need to mutex to share the pipe
        server_channel.write(data)

        # we only need to do something for the next_file command, for which the master sends
        # back a command that we need to interpret
        case data['command']
        when "next_file"
          handle_next_file_response(server_channel.read, worker_number_of(channel), channel)
        end
      end
    end
  end

  def handle_next_file_response(data, worker_number, worker_channel)
    case data["command"]
    when "drain"
      close_worker(worker_number, worker_channel)

    when "framework"
      close_worker(worker_number, worker_channel)
      start_worker(worker_number, data["framework"])

    when "process_file"
      worker_channel.write data
    end
  end

  def close_worker(worker_number, worker_channel)
    worker_channel.write "command" => "close"
    workers.delete worker_number
  end

  def worker_number_of(worker_channel)
    workers.find {|number, hash| hash[:channel] == worker_channel} .first
  end

  ##
  # Kill the workers.
  #
  def kill_workers
    workers.each do |index, hash|
      begin
        Process.kill('USR1', hash[:pid])
      rescue Errno::ESRCH
      end
    end
    Process.waitall
    exit
  end
end
