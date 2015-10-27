module KnapsackPro
  module Adapters
    class MinitestAdapter < BaseAdapter
      TEST_DIR_PATTERN = 'test/**/*_test.rb'
      @@parent_of_test_dir = nil

      def self.test_path(obj)
        # Pick the first public method in the class itself, that starts with "test_"
        test_method_name = obj.public_methods(false).select{|m| m =~ /^test_/ }.first
        method_object = obj.method(test_method_name)
        full_test_path = method_object.source_location.first
        parent_of_test_dir_regexp = Regexp.new("^#{@@parent_of_test_dir}")
        test_path = full_test_path.gsub(parent_of_test_dir_regexp, '.')
        # test_path will look like ./test/dir/unit_test.rb
        test_path
      end

      # See how to write hooks and plugins
      # https://github.com/seattlerb/minitest/blob/master/lib/minitest/test.rb
      module BindTimeTrackerMinitestPlugin
        def before_setup
          super
          KnapsackPro.tracker.current_test_path = KnapsackPro::Adapters::MinitestAdapter.test_path(self)
          KnapsackPro.tracker.start_timer
        end

        def after_teardown
          KnapsackPro.tracker.stop_timer
          super
        end
      end

      def bind_time_tracker
        ::Minitest::Test.send(:include, BindTimeTrackerMinitestPlugin)

        add_post_run_callback do
          KnapsackPro.logger.info(KnapsackPro::Presenter.global_time)
        end
      end

      def bind_save_report
        add_post_run_callback do
          KnapsackPro::Report.save
        end
      end

      def set_test_helper_path(file_path)
        test_dir_path = File.dirname(file_path)
        @@parent_of_test_dir = File.expand_path('../', test_dir_path)
      end

      private

      def add_post_run_callback(&block)
        if Minitest.respond_to?(:after_run)
          Minitest.after_run { block.call }
        else
          Minitest::Unit.after_tests { block.call }
        end
      end
    end
  end
end
