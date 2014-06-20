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
      runner_id = "A"
      @configuration.slaves.collect do |slave_details|
        runner_id = runner_id.succ
        start_host(slave_details.merge(:runner_id => runner_id))
      end
    end

    protected
    def start_host(slave_details)
      client, server = Nitra::Channel.pipe

      puts "Starting slave runner #{slave_details[:runner_id]} with command '#{slave_details[:command]}'" if configuration.debug
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
    attr_reader :channel

    def run
      @channel = Nitra::Channel.new($stdin, $stdout)

      @channel.write("command" => "slave_configuration")

      response = @channel.read
      unless response && response["command"] == "configuration"
        puts "handshake failed"
        exit 1
      end

      runner = Nitra::Runner.new(response["configuration"], channel, response["runner_id"])

      runner.run
    end
  end
end
