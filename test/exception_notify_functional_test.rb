require File.expand_path(File.dirname(__FILE__) + '/test_helper')
require 'test/unit'

RAILS_DEFAULT_LOGGER = Logger.new(nil)

require File.join(File.dirname(__FILE__), 'mocks/controllers')

ActionController::Routing::Routes.clear!
ActionController::Routing::Routes.draw {|m| m.connect ':controller/:action/:id' }

class ExceptionNotifyFunctionalTest < ActionController::TestCase
  
  def setup
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new    
    ActionController::Base.consider_all_requests_local = false
    @@delivered_mail = []
    ActionMailer::Base.class_eval do
      def deliver!(mail = @mail)
        @@delivered_mail << mail
      end
    end    
  end

  def test_view_path_200; assert_view_path_string("200"); end
  def test_view_path_400; assert_view_path_string("400"); end
  def test_view_path_403; assert_view_path_string("403"); end
  def test_view_path_404; assert_view_path_string("404"); end
  def test_view_path_405; assert_view_path_string("405"); end
  def test_view_path_410; assert_view_path_string("410"); end
  def test_view_path_418; assert_view_path_string("422"); end
  def test_view_path_422; assert_view_path_string("422"); end
  def test_view_path_423; assert_view_path_string("423"); end
  def test_view_path_500; assert_view_path_string("500"); end
  def test_view_path_501; assert_view_path_string("501"); end
  def test_view_path_503; assert_view_path_string("503"); end
  def test_view_path_nil; assert_view_path_string(nil); end
  def test_view_path_empty; assert_view_path_string(""); end
  def test_view_path_nonsense; assert_view_path_string("slartibartfarst"); end

  def test_old_style_where_requests_are_local
    ActionController::Base.consider_all_requests_local = true
    @controller = OldStyle.new
    get "runtime_error"    
    
    assert_nothing_mailed
  end

  def test_new_style_where_requests_are_local
    ActionController::Base.consider_all_requests_local = true
    @controller = NewStyle.new
    get "runtime_error"    
    
    # puts @response.body
    assert_nothing_mailed
  end
  
  def test_old_style_runtime_error_sends_mail
    @controller = OldStyle.new
    get "runtime_error"
    assert_error_mail_contains("This is a runtime error that we should be emailed about")
  end
  
  def test_old_style_record_not_found_does_not_send_mail
    @controller = OldStyle.new
    get "record_not_found"    
    assert_nothing_mailed
  end
  
  def test_new_style_runtime_error_sends_mail
    @controller = NewStyle.new
    get "runtime_error"
    assert_error_mail_contains("This is a runtime error that we should be emailed about")    
  end
  
  def test_new_style_record_not_found_does_not_send_mail
    @controller = NewStyle.new
    get "record_not_found"    
    assert_nothing_mailed
  end
    
  private

  def assert_view_path_string(status)
    assert(ExceptionNotifier.get_view_path(status).is_a?(String), "View Path is not a string for status code '#{status}'")
  end

  def assert_error_mail_contains(text)
    assert(mailed_error.index(text), 
      "Expected mailed error body to contain '#{text}', but not found. \n actual contents: \n#{mailed_error}")    
  end
  
  def assert_nothing_mailed
    assert @@delivered_mail.empty?, "Expected to have NOT mailed out a notification about an error occuring, but mailed: \n#{@@delivered_mail}"
  end
  
  def mailed_error
    assert @@delivered_mail.last, "Expected to have mailed out a notification about an error occuring, but none mailed"
    @@delivered_mail.last.encoded
  end
  
end
