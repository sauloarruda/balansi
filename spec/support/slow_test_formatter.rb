# Helper module to track and report slow tests (over 500ms threshold)
# Only shows tests that exceed the threshold to avoid cluttering output
module SlowTestTracker
  class << self
    attr_accessor :slow_examples, :slow_example_groups, :threshold_ms

    def initialize
      self.slow_examples = []
      self.slow_example_groups = Hash.new { |h, k| h[k] = { time: 0, count: 0 } }
      # Threshold: 500ms (0.5 seconds) - only show tests slower than this
      self.threshold_ms = 500
    end

    def track_example(example)
      return unless example.execution_result
      return if example.execution_result.status == :pending
      return unless example.execution_result.run_time

      execution_time_ms = example.execution_result.run_time * 1000
      return unless execution_time_ms > threshold_ms

      slow_examples << {
        description: example.full_description,
        location: example.location,
        time: execution_time_ms
      }

      # Track slow example groups
      group_key = example.example_group.parent_groups.last&.description || "Unknown"
      slow_example_groups[group_key][:time] += execution_time_ms
      slow_example_groups[group_key][:count] += 1
    end

    def report_slow_tests
      return if slow_examples.empty?

      output = $stdout
      print_slow_tests_header(output)
      print_slow_examples(output)
      print_slow_example_groups(output)
      output.puts
    end

    private

    def print_slow_tests_header(output)
      output.puts "\nSlow tests (over #{threshold_ms}ms / #{threshold_ms / 1000.0}s):"
      output.puts
    end

    def print_slow_examples(output)
      sorted_examples = slow_examples.sort_by { |e| -e[:time] }
      sorted_examples.each_with_index do |example, index|
        output.puts "  #{index + 1}. #{example[:description]}"
        output.puts "     #{format('%.2f', example[:time])}ms (#{format('%.3f', example[:time] / 1000.0)}s) #{example[:location]}"
      end
    end

    def print_slow_example_groups(output)
      slow_groups = slow_example_groups.select do |_group, data|
        (data[:time] / data[:count]) > threshold_ms
      end

      return if slow_groups.empty?

      output.puts "\nSlow example groups (average over #{threshold_ms}ms):"
      slow_groups.sort_by { |_group, data| -(data[:time] / data[:count]) }.each do |group, data|
        avg_time = data[:time] / data[:count]
        output.puts "  #{group}"
        output.puts "     #{format('%.2f', avg_time)}ms average (#{format('%.2f', data[:time])}ms / #{data[:count]} examples)"
      end
    end
  end
end
