class Nitra::Progress
  attr_accessor :file_count, :files_completed, :test_count, :failure_count, :output, :failure

  def initialize
    @file_count = @files_completed = @test_count = @failure_count = 0
    @output = ""
    @failure = false
  end

  def file_progress(tests, failures, failure, text)
    self.files_completed += 1
    self.test_count += tests
    self.failure_count += failures
    self.failure ||= failure
    self.output.concat text
  end

  def fail(message)
    self.failure = true
    self.output.concat message
  end

  def filtered_output
    output.gsub(/\n\n\n+/, "\n\n")
  end
end
