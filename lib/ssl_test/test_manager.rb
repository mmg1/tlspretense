module SSLTest
  # Tracks testing state and handles reporting for the TestListener.
  class TestManager
    include PacketThief::Logging

    attr_accessor :current_test
    attr_reader :remaining_tests

    attr_accessor :listener

    def initialize(context, testlist, report, logger=nil)
      @appctx = context
      @testlist = testlist
      @report = report
      @logger = logger
      @remaining_tests = @testlist.dup

      @pause = false

      prepare_next_test(true)
    end

    # grabs the next test. Returns it, or nil if we are out of tests.
    def prepare_next_test(first=false)
      @current_test = @remaining_tests.shift

      if current_test == nil
        stop_testing
      elsif @appctx.config.pause?
        pause
      else
        loginfo "Starting test: #{current_test.id}"
      end

      @start_time = Time.now
    end

    # Called when a test completes or is skipped. It adds an SSLTestResult to
    # the report, and it cleans up after itself.
    #
    # :connected, :rejected, :sentdata
    def test_completed(actual_result)
      logdebug "test_completed", :actual_result => actual_result, :expected_result => self.current_test.expected_result
      return if actual_result == :running

      passed = if @appctx.config.testing_method == 'tlshandshake'
                 case current_test.expected_result.to_s
                 when 'connected', :connected
                   %w{connected sentdata}.include? actual_result.to_s
                 when 'rejected', :rejected
                   actual_result == :rejected
                 else
                   raise "Unknown expected_result: #{current_test.expected_result}"
                 end
               else # senddata, which requires data to be sent for it to pass.
                 case current_test.expected_result
                 when 'connected'
                   actual_result == :sentdata
                 when 'rejected'
                   %w{rejected connected}.include? actual_result.to_s
                 else
                   raise "Unknown expected_result: #{current_test.expected_result}"
                 end
               end

      str = SSLTestResult.new(current_test.id, passed)
      str.description = current_test.description
      str.expected_result = current_test.expected_result
      str.actual_result = actual_result.to_s
      str.start_time = @start_time
      str.stop_time = Time.now

      @report.add_result(str)

      if actual_result == :skipped
        loginfo "#{current_test.id}: Skipping test"
      else
        loginfo "#{current_test.id}: Finished test"
      end

      prepare_next_test
    end

    def stop_testing
      loginfo "Stopping"
      @listener.stop_server if @listener
      EM.stop_event_loop
    end

    def paused?
      @pause
    end

    def pause
      @pause = true
      loginfo "Press Enter to continue."
    end

    def unpause
      if paused?
        loginfo "Starting test: #{current_test.id}"
        @pause = false
      end
    end

  end
end
