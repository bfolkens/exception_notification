require 'ipaddr'

module ExceptionNotifiable
  include ExceptionHandler

  unless defined?(SILENT_EXCEPTIONS)
    SILENT_EXCEPTIONS = []
    SILENT_EXCEPTIONS << ActiveRecord::RecordNotFound if defined?(ActiveRecord)
    SILENT_EXCEPTIONS << [
      ActionController::UnknownController,
      ActionController::UnknownAction,
      ActionController::RoutingError,
      ActionController::MethodNotAllowed
    ] if defined?(ActionController)
  end

  HTTP_ERROR_CODES = { 
    "400" => "Bad Request",
    "403" => "Forbidden",
    "404" => "Not Found",
    "405" => "Method Not Allowed",
    "410" => "Gone",
    "500" => "Internal Server Error",
    "501" => "Not Implemented",
    "503" => "Service Unavailable"
  } unless defined?(HTTP_ERROR_CODES)
  
  def self.codes_for_rails_error_classes
    classes = {
      NameError => "503",
      TypeError => "503",
      RuntimeError => "500"
    }
    classes.merge!({ ActiveRecord::RecordNotFound => "400" })         if defined?(ActiveRecord)     && ActiveRecord.const_defined?(:RecordNotFound)
    classes.merge!({ ActionController::UnknownController => "404" })  if defined?(ActionController) && ActionController.const_defined?(:UnknownController)
    classes.merge!({ ActionController::MissingTemplate => "404" })    if defined?(ActionController) && ActionController.const_defined?(:MissingTemplate)
    classes.merge!({ ActionController::MethodNotAllowed => "405" })   if defined?(ActionController) && ActionController.const_defined?(:MethodNotAllowed)
    classes.merge!({ ActionController::UnknownAction => "501" })      if defined?(ActionController) && ActionController.const_defined?(:UnknownAction)
    classes.merge!({ ActionController::RoutingError => "404" })       if defined?(ActionController) && ActionController.const_defined?(:RoutingError)
  end
  
  def self.included(base)
    base.extend ClassMethods

    # Adds the following class attributes to the classes that include ExceptionNotifiable
    #  HTTP status codes and what their 'English' status message is
    #  Rails error classes to rescue and how to rescue them
    #  error_layout:
    #     can be defined at controller level to the name of the layout, 
    #     or set to true to render the controller's own default layout, 
    #     or set to false to render errors with no layout
    base.cattr_accessor :http_error_codes
    base.http_error_codes = HTTP_ERROR_CODES
    base.cattr_accessor :error_layout
    base.error_layout = nil
    base.cattr_accessor :rails_error_classes
    base.rails_error_classes = self.codes_for_rails_error_classes
    base.cattr_accessor :exception_notifier_verbose
    base.exception_notifier_verbose = false
    base.cattr_accessor :silent_exceptions
    base.silent_exceptions = SILENT_EXCEPTIONS
    base.class_eval do
      alias_method_chain :rescue_action_in_public, :notification
    end
  end
  
  module ClassMethods
    # specifies ip addresses that should be handled as though local
    def consider_local(*args)
      local_addresses.concat(args.flatten.map { |a| IPAddr.new(a) })
    end

    def local_addresses
      addresses = read_inheritable_attribute(:local_addresses)
      unless addresses
        addresses = [IPAddr.new("127.0.0.1")]
        write_inheritable_attribute(:local_addresses, addresses)
      end
      addresses
    end

    # set the exception_data deliverer OR retrieve the exception_data
    def exception_data(deliverer = nil)
      if deliverer
        write_inheritable_attribute(:exception_data, deliverer)
      else
        read_inheritable_attribute(:exception_data)
      end
    end
  end

  private

    # overrides Rails' local_request? method to also check any ip
    # addresses specified through consider_local.
    def local_request?
      remote = IPAddr.new(request.remote_ip)
      !self.class.local_addresses.detect { |addr| addr.include?(remote) }.nil?
    end

    def rescue_with_handler(exception)
      to_return = super
      if to_return
        send_email = should_notify_on_exception?(exception)
        verbose_output(exception, "N/A", "rescued by handler", send_email, nil) if self.class.exception_notifier_verbose
        perform_exception_notify_mailing(exception) if send_email
      end
      to_return
    end

    def notify_and_render_error_template(status_cd, request, exception, file_path = nil)
      status = self.class.http_error_codes[status_cd] ? status_cd + " " + self.class.http_error_codes[status_cd] : status_cd
      file = file_path ? ExceptionNotifier.get_view_path(file_path) : ExceptionNotifier.get_view_path(status_cd)
      send_email = should_notify_on_exception?(exception, status_cd)

      # Debugging output
      verbose_output(exception, status_cd, file, send_email, request) if self.class.exception_notifier_verbose
      # Send the email before rendering to avert possible errors on render preventing the email from being sent.
      perform_exception_notify_mailing(exception) if send_email
      # Render the error page to the end user
      render_error_template(file, status)
    end

    def render_error_template(file, status)
      respond_to do |type|
        type.html { render :file => file,
                            :layout => self.class.error_layout,
                            :status => status }
        type.all  { render :nothing => true,
                            :status => status}
      end
    end

    def verbose_output(exception, status_cd, file, send_email, request = nil)
      puts "[EXCEPTION] #{exception}"
      puts "[EXCEPTION CLASS] #{exception.class}"
      puts "[EXCEPTION STATUS_CD] #{status_cd}"
      puts "[ERROR LAYOUT] #{self.class.error_layout}" if self.class.error_layout
      puts "[ERROR VIEW PATH] #{ExceptionNotifier.view_path}" if !ExceptionNotifier.nil? && !ExceptionNotifier.view_path.nil?
      puts "[ERROR RENDER] #{file}"
      puts "[ERROR EMAIL] #{send_email ? "YES" : "NO"}"
      req = request ? " for request_uri=#{request.request_uri} and env=#{request.env.inspect}" : ""
      logger.error("render_error(#{status_cd}, #{self.class.http_error_codes[status_cd]}) invoked#{req}") if !logger.nil?
    end

    def perform_exception_notify_mailing(exception)
      deliverer = self.class.exception_data
      data = case deliverer
        when nil then {}
        when Symbol then send(deliverer)
        when Proc then deliverer.call(self)
      end
      the_blamed = lay_blame(exception)

      ExceptionNotifier.deliver_exception_notification(exception, self,
        request, data, the_blamed)
    end

    def should_notify_on_exception?(exception, status_cd = nil)
      #First honor the custom settings from environment
      return false if ExceptionNotifier.render_only
      #don't mail exceptions raised locally
      return false if ExceptionNotifier.skip_local_notification && is_local?
      #don't mail exceptions raised that match ExceptionNotifiable.silent_exceptions
      return false if self.class.silent_exceptions.any? {|klass| klass === exception }
      return true if ExceptionNotifier.send_email_error_classes.include?(exception)
      return true if !status_cd.nil? && ExceptionNotifier.send_email_error_codes.include?(status_cd)
      return ExceptionNotifier.send_email_other_errors
    end

    def is_local?
      (consider_all_requests_local || local_request?)
    end

    def rescue_action_in_public_with_notification(exception)
      # If the error class is NOT listed in the rails_errror_class hash then we get a generic 500 error:
      # OTW if the error class is listed, but has a blank code or the code is == '200' then we get a custom error layout rendered
      # OTW the error class is listed!
      status_code = status_code_for_exception(exception)
      if status_code == '200'
        notify_and_render_error_template(status_code, request, exception, exception_to_filename(exception))
      else
        notify_and_render_error_template(status_code, request, exception)
      end
    end

    def status_code_for_exception(exception)
      self.class.rails_error_classes[exception.class].nil? ? '500' : self.class.rails_error_classes[exception.class].blank? ? '200' : self.class.rails_error_classes[exception.class]
    end

    def exception_to_filename(exception)
      exception.to_s.delete(':').gsub( /([A-Za-z])([A-Z])/, '\1' << '_' << '\2' ).downcase
    end

    def lay_blame(exception)
      error = {}
      unless(ExceptionNotifier.git_repo_path.nil?)
        if(exception.class == ActionView::TemplateError)
            blame = blame_output(exception.line_number, "app/views/#{exception.file_name}")
            error[:author] = blame[/^author\s.+$/].gsub(/author\s/,'')
            error[:line]   = exception.line_number
            error[:file]   = exception.file_name
        else
          exception.backtrace.each do |line|
            file = exception_in_project?(line[/^.+?(?=:)/])
            unless(file.nil?)
              line_number = line[/:\d+:/].gsub(/[^\d]/,'')
              # Use relative path or weird stuff happens
              blame = blame_output(line_number, file.gsub(Regexp.new("#{RAILS_ROOT}/"),''))
              error[:author] = blame[/^author\s.+$/].sub(/author\s/,'')
              error[:line]   = line_number
              error[:file]   = file
              break
            end
          end
        end
      end
      error
    end
  
    def blame_output(line_number, path)
      app_directory = Dir.pwd
      Dir.chdir ExceptionNotifier.git_repo_path
      blame = `git blame -p -L #{line_number},#{line_number} #{path}`
      Dir.chdir app_directory
  
      blame
    end
  
    def exception_in_project?(path) # should be a path like /path/to/broken/thingy.rb
      dir = File.split(path).first rescue ''
      if(File.directory?(dir) and !(path =~ /vendor\/plugins/) and path.include?(RAILS_ROOT))
        path
      else
        nil
      end
    end

end
