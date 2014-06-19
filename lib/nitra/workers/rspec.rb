module Nitra::Workers
  class Rspec < Worker
    def self.files
      Dir["spec/**/*_spec.rb"].sort_by {|f| File.size(f)}.reverse
    end

    def self.filename_match?(filename)
      filename =~ /_spec\.rb/
    end

    def initialize(runner_id, worker_number, configuration)
      super(runner_id, worker_number, configuration)
    end

    def load_environment
      require 'rspec'
      RSpec::Core::Runner.disable_autorun!
    end

    def minimal_file
      <<-EOS
      require 'spec_helper'
      describe('nitra preloading') do
        it('preloads the fixtures') do
          expect(1).to eq(1)
        end
      end
      EOS
    end

    ##
    # Run an rspec file and write the results back to the runner.
    #
    # Doesn't write back to the runner if we mark the run as preloading.
    #
    def run_file(filename, preloading = false)
      attempt = 1
      begin
        args = ["-f", "p", filename]
        if RSpec::Core::const_defined?(:CommandLine)
          runner = RSpec::Core::CommandLine.new(args)
        else
          runner = RSpec::Core::Runner.new(RSpec::Core::ConfigurationOptions.new(args))
        end
        result = runner.run(io, io)

        if result.to_i != 0 && @configuration.exceptions_to_retry && attempt < @configuration.max_attempts &&
           io.string =~ @configuration.exceptions_to_retry
          raise RetryException
        end
      rescue LoadError => e
        io << "\nCould not load file #{filename}: #{e.message}\n\n"
        result = 1
      rescue RetryException
        channel.write("command" => "retry", "filename" => filename, "on" => "#{runner_id}:#{worker_number}")
        attempt += 1
        clean_up
        io.string = ""
        retry
      rescue Exception => e
        io << "Exception when running #{filename}: #{e.message}"
        io << e.backtrace[0..7].join("\n")
        result = 1
      end

      if preloading
        puts io.string
      else
        channel.write("command" => "result", "filename" => filename, "return_code" => result.to_i, "text" => io.string, "worker_number" => worker_number)
      end
    end

    def clean_up
      # Rspec.reset in 2.6 didn't destroy your rspec_rails fixture loading, we can't use it anymore for it's intended purpose.
      # This means our world object will be slightly polluted by the preload_framework code, but that's a small price to pay
      # to upgrade.
      #
      # RSpec.reset
      #
      RSpec.instance_variable_set(:@world, nil)
    end
  end
end
