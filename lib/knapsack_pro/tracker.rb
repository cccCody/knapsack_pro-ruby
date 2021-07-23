module KnapsackPro
  class Tracker
    include Singleton

    # when test file is pending, empty with no tests or has syntax error then assume time execution
    # to better allocate it in Queue Mode for future CI build runs
    DEFAULT_TEST_FILE_TIME = 0.0 # seconds

    attr_reader :global_time_since_beginning, :global_time, :test_files_with_time, :prerun_tests_loaded
    attr_writer :current_test_path

    def initialize
      @global_time_since_beginning = 0
      @prerun_tests_loaded = false
      FileUtils.mkdir_p(tracker_dir_path)
      set_defaults
    end

    def reset!
      set_defaults
      set_default_prerun_tests
    end

    def start_timer
      @start_time ||= now_without_mock_time.to_f
    end

    def reset_timer
      @start_time = now_without_mock_time.to_f
    end

    def stop_timer
      execution_time = @start_time ? now_without_mock_time.to_f - @start_time : 0.0

      if @current_test_path
        update_global_time(execution_time)
        update_test_file_time(execution_time)
        reset_timer
      end

      execution_time
    end

    def current_test_path
      raise("current_test_path needs to be set by Knapsack Pro Adapter's bind method") unless @current_test_path
      KnapsackPro::TestFileCleaner.clean(@current_test_path)
    end

    def set_prerun_tests(test_file_paths)
      test_file_paths.each do |test_file_path|
        # Set a default time for test file
        # in case when the test file will not be run
        # due syntax error or being pending.
        # The time is required by Knapsack Pro API.
        @test_files_with_time[test_file_path] = {
          time_execution: DEFAULT_TEST_FILE_TIME,
          measured_time: false,
        }
      end

      save_prerun_tests_report(@test_files_with_time)

      @prerun_tests_loaded = true
    end

    def to_a
      # When the test files are not loaded in the memory then load them from the disk.
      # Useful for the Regular Mode when the memory is not shared between tracker instances.
      load_prerun_tests unless prerun_tests_loaded

      test_files = []
      @test_files_with_time.each do |path, hash|
        test_files << {
          path: path,
          time_execution: hash[:time_execution]
        }
      end
      test_files
    end

    private

    def set_defaults
      @global_time = 0
      @test_files_with_time = {}
      @current_test_path = nil
    end

    def tracker_dir_path
      "#{KnapsackPro::Config::Env::TMP_DIR}/tracker"
    end

    def prerun_tests_report_path
      report_name = "prerun_tests_node_#{KnapsackPro::Config::Env.ci_node_index}.json"
      File.join(tracker_dir_path, report_name)
    end

    def save_prerun_tests_report(hash)
      report_json = JSON.pretty_generate(hash)

      File.open(prerun_tests_report_path, 'w+') do |f|
        f.write(report_json)
      end
    end

    def set_default_prerun_tests
      save_prerun_tests_report({})
    end

    def read_prerun_tests_report
      JSON.parse(File.read(prerun_tests_report_path))
    end

    def load_prerun_tests
      read_prerun_tests_report.each do |test_file_path, hash|
        # load only test files that were not measured yet
        # track test files assigned to CI node but never executed by test runner (e.g. pending RSpec spec files)
        next if @test_files_with_time.key?(test_file_path)

        @test_files_with_time[test_file_path] = {
          time_execution: hash.fetch('time_execution'),
          measured_time: hash.fetch('measured_time'),
        }
      end
    end

    def update_global_time(execution_time)
      @global_time += execution_time
      @global_time_since_beginning += execution_time
    end

    def update_test_file_time(execution_time)
      @test_files_with_time[current_test_path] ||= {
        time_execution: 0,
        measured_time: false,
      }

      hash = @test_files_with_time[current_test_path]

      if hash[:measured_time]
        hash[:time_execution] += execution_time
      else
        hash[:time_execution] = execution_time
        hash[:measured_time] = true
      end

      @test_files_with_time[current_test_path] = hash
    end

    def now_without_mock_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
