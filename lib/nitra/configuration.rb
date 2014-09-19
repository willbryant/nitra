require 'nitra/utils'

module Nitra
  class Configuration
    attr_accessor :debug, :quiet, :print_failures, :burndown_report, :rake_tasks, :split_files, :start_framework, :exceptions_to_retry, :max_attempts
    attr_accessor :process_count, :environment, :slaves, :slave_mode, :frameworks

    def initialize
      self.environment = "test"
      self.slaves = []
      self.rake_tasks = {}
      self.frameworks = []
      self.max_attempts = 5
      calculate_default_process_count
    end

    def add_framework(framework)
      frameworks << framework
    end

    def add_rake_task(name, list)
      rake_tasks[name] = list
    end

    def add_slave(command)
      slaves << {:command => command, :cpus => nil}
    end

    def calculate_default_process_count
      self.process_count ||= Nitra::Utils.processor_count
    end

    def set_process_count(n)
      if slaves.empty?
        self.process_count = n
      else
        slaves.last[:cpus] = n
      end
    end
  end
end
