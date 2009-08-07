require 'pathname'

class ExceptionNotifier < ActionMailer::Base
  @@sender_address = %("#{(defined?(Rails) ? Rails.env : RAILS_ENV).capitalize} Error" <errors@example.com>)
  cattr_accessor :sender_address

  @@exception_recipients = []
  cattr_accessor :exception_recipients

  @@email_prefix = "[#{(defined?(Rails) ? Rails.env : RAILS_ENV).capitalize} ERROR] "
  cattr_accessor :email_prefix

  @@sections = %w(request session environment backtrace)
  cattr_accessor :sections

  @@render_only = false
  cattr_accessor :render_only

  @@skip_local_notification = true
  cattr_accessor :skip_local_notification

  @@view_path = nil
  cattr_accessor :view_path

  #Emailed Error Notification will be sent if the error code matches one of the following error codes
  @@send_email_error_codes = %W( 405 500 503 )
  cattr_accessor :send_email_error_codes

  #Emailed Error Notification will be sent if the error class matches one of the following error error classes
  @@send_email_error_classes = %W( )
  cattr_accessor :send_email_error_classes

  @@git_repo_path = nil
  cattr_accessor :git_repo_path

  self.template_root = "#{File.dirname(__FILE__)}/../views"

  def self.reloadable?() false end

  def self.get_view_path(status_cd)
    if File.exist?("#{RAILS_ROOT}/public/#{status_cd}.html")
      "#{RAILS_ROOT}/public/#{status_cd}.html"
    elsif !view_path.nil? && File.exist?("#{RAILS_ROOT}/#{view_path}/#{status_cd}.html")
      "#{RAILS_ROOT}/#{view_path}/#{status_cd}.html"
    elsif File.exist?("#{RAILS_ROOT}/vendor/plugins/exception_notification/views/exception_notifiable/#{status_cd}.html")
      "#{RAILS_ROOT}/vendor/plugins/exception_notification/views/exception_notifiable/#{status_cd}.html"
    else 
      "#{RAILS_ROOT}/vendor/plugins/exception_notification/views/exception_notifiable/500.html"
    end
  end

  def exception_notification(exception, controller = nil, request = nil, data={}, the_blamed=nil)
    data = error_environment_data_hash(exception, controller, request, data, the_blamed)
    #Prefer to have custom, potentially HTML email templates available
    #content_type  "text/plain"
    recipients    exception_recipients
    from          sender_address

    request.session.inspect # Ensure session data is loaded (Rails 2.3 lazy-loading)
    
    subject       "#{email_prefix}#{data[:location]} (#{exception.class}) #{exception.message.inspect}"
    body          data
  end
  
  def background_exception_notification(exception, data = {}, the_blamed = nil)
    exception_notification(exception, nil, nil, data, the_blamed)
  end

  private

    def error_environment_data_hash(exception, controller = nil, request = nil, data={}, the_blamed=nil)
      data.merge!({
        :exception => exception,
        :backtrace => sanitize_backtrace(exception.backtrace),
        :rails_root => rails_root,
        :data => data,
        :the_blamed => the_blamed
      })

      if controller && request
        data.merge!({
          :location => "#{controller.controller_name}##{controller.action_name}",
          :controller => controller,
          :request => request,
          :host => (request.env['HTTP_X_REAL_IP'] || request.env["HTTP_X_FORWARDED_HOST"] || request.env["HTTP_HOST"]),
          :sections => sections
        })
      else
        # TODO: with refactoring, the environment section could show useful ENV data even without a request
        data.merge!({
          :location => sanitize_backtrace([exception.backtrace.first]).first,
          :sections => sections - %w(request session environment)
        })
      end
      return data
    end

    def sanitize_backtrace(trace)
      re = Regexp.new(/^#{Regexp.escape(rails_root)}/)
      trace.map { |line| Pathname.new(line.gsub(re, "[RAILS_ROOT]")).cleanpath.to_s }
    end

    def rails_root
      @rails_root ||= Pathname.new(RAILS_ROOT).cleanpath.to_s
    end

end
