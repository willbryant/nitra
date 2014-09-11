module Nitra::Workers
  class Cucumber < Worker
    def self.files
      Dir["features/**/*.feature"].sort_by {|f| File.size(f)}.reverse
    end

    def self.filename_match?(filename)
      filename =~ /\.feature/
    end

    def initialize(runner_id, worker_number, configuration)
      super(runner_id, worker_number, configuration)
    end

    def load_environment
      require 'cucumber'
      require 'nitra/ext/cucumber'
    end

    def minimal_file
      <<-EOS
      Feature: cucumber preloading
        Scenario: a fake scenario
          Given every step is unimplemented
          When we run this file
          Then Cucumber will load it's environment
      EOS
    end

    def cuke_runtime
      @cuke_runtime ||= ::Cucumber::ResetableRuntime.new  # This runtime gets reused, this is important as it's the part that loads the steps...
    end

    ##
    # Run a Cucumber file and write the results back to the runner.
    #
    # Doesn't write back to the runner if we mark the run as preloading.
    #
    def run_file(filename, preloading = false)
      attempt = 1
      begin
        failed = true
        cuke_config = ::Cucumber::Cli::Configuration.new(io, io)
        cuke_config.parse!(["--no-color", "--require", "features", filename])
        cuke_runtime.configure(cuke_config)
        cuke_runtime.run!

        if cuke_runtime.results.failure? && @configuration.exceptions_to_retry && attempt < @configuration.max_attempts &&
           cuke_runtime.results.scenarios(:failed).any? {|scenario| scenario.exception.to_s =~ @configuration.exceptions_to_retry}
          raise RetryException
        end
        failed = false unless cuke_runtime.results.failure?
      rescue LoadError => e
        debug "load error"
        io << "\nCould not load file #{filename}: #{e.message}\n\n"
      rescue RetryException
        channel.write("command" => "retry", "filename" => filename, "on" => on)
        attempt += 1
        clean_up
        io.string = ""
        retry
      rescue Exception => e
        debug "had exception #{e.inspect}"
        io << "Exception when running #{filename}: #{e.message}"
        io << e.backtrace[0..7].join("\n")
      end

      if preloading
        debug io.string
      else
        if m = io.string.match(/(\d+) scenarios?.+$/)
          test_count = m[1].to_i
          if m = io.string.match(/\d+ scenarios? \(.*(\d+) [failed|undefined].*\)/)
            failure_count = m[1].to_i
            failed = true if failure_count > 0
          else
            failure_count = 0
          end
        else
          test_count = failure_count = 0
        end

        channel.write(
          "command"       => "result",
          "filename"      => filename,
          "failed"        => failed,
          "test_count"    => test_count,
          "failure_count" => failure_count,
          "text"          => failed ? io.string : "",
          "on"            => on)
      end
    end

    def clean_up
      cuke_runtime.reset
    end
  end
end
