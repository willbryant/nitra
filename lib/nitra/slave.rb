module Nitra::Slave
  class Client
    attr_reader :configuration, :slave_details_by_server

    def initialize(configuration)
      @configuration = configuration
      @slave_details_by_server = {}
    end

    ##
    # Starts the slave runners in forked processes.
    #
    # The slaves will request their configuration in parallel, to minimize startup time.
    #
    def connect
      @configuration.slaves.collect do |slave_details|
        start_host(slave_details)
      end
    end

    protected
    def start_host(slave_details)
      client, server = Nitra::Channel.pipe

      puts "Starting slave runner with command '#{slave_details[:command]}'" if configuration.debug
      slave_details_by_server[server] = slave_details

      pid = fork do
        server.close
        $stdin.reopen(client.rd)
        $stdout.reopen(client.wr)
        $stderr.reopen(client.wr)
        exec slave_details[:command]
      end
      client.close
      server
    end
  end

  class Server
    attr_reader :channel, :runner_id

    def run
      @runner_id = Socket.gethostname

      @channel = Nitra::Channel.new($stdin, $stdout)
      @channel.write("command" => "slave_configuration", "runner_id" => @runner_id)

      response = @channel.read
      unless response && response["command"] == "configuration"
        puts "handshake failed"
        exit 1
      end

      runner = Nitra::Runner.new(response["configuration"], channel, @runner_id)

      runner.run
    end
  end
end
