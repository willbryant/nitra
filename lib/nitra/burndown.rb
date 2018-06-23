require 'ostruct'
require 'erb'

class Nitra::Burndown
  attr_accessor :runners, :started_at, :finished_at, :all_results

  class Result < OpenStruct
    def filename_without_path
      File.split(filename).last
    end

    def duration
      end_time - start_time
    end

    def short_label
      result = (filename ? filename_without_path : framework).tr('<>&', '_')
      result << " (#{'%0.2f' % duration}s)"
      result
    end

    def label
      result = (filename ? filename : "#{framework} initialization").tr('<>&', '_')
      result << " (#{'%0.2f' % duration}s)"
      if failures.to_i > 0
        result << ": #{failures} of #{tests} failed"
      elsif tests.to_i > 0
        result << ": #{tests} tests"
      end
      result
    end
  end

  def initialize
    @runners = {}
    @all_results = []
  end

  def start
    @started_at = Time.now
  end

  def next_file(on_worker, framework, file)
    results = worker_results(on_worker)
    results.last[:end_time] ||= Time.now - @started_at if results.last # set the end time on framework initialization
    results << Result.new(
      :framework => framework,
      :filename => file,
      :start_time => Time.now - @started_at
    )
  end

  def result(on_worker, framework, file, tests, failures, failure)
    result = worker_result(on_worker, file)
    result[:end_time] = Time.now - @started_at
    result[:tests] = tests
    result[:failures] = failures
    result[:failure] = failure
    @all_results << result
    result.duration
  end

  def retry(on_worker, framework, file)
    result = worker_result(on_worker, file)
    result[:end_time] = Time.now - @started_at
    result[:retried] = next_file(on_worker, framework, file) # sets up for the retry
    result.duration
  end

  def finish(report_filename)
    @finished_at = Time.now

    # some runners may have be partway through restarting workers with a new framework
    runners.each do |runner_id, workers|
      workers.each do |worker_id, results|
        results.last.end_time ||= @finished_at - @started_at
      end
    end

    if report_filename
      File.open(report_filename, "w") {|file| file.write report}
    end
  end

protected
  def worker_results(on_worker)
    runner_id, worker_id = on_worker.split(':')
    workers_for_runner = (runners[runner_id] ||= {})
    workers_for_runner[worker_id] ||= []
  end

  def worker_result(on_worker, filename)
    result = worker_results(on_worker).last
    raise "No file was in progress on #{on_worker}" unless result
    raise "Expected #{result.filename} to be in progress on #{on_worker} but was given a result for #{filename}" unless result.filename == filename
    result
  end

  def report_template_path
    File.expand_path("#{__FILE__}/../../../templates/burndown.html.erb")
  end

  def report_template
    File.read(report_template_path)
  end

  def report
    ERB.new(report_template).result(binding)
  end

  def runtime
    @finished_at - @started_at
  end
end
