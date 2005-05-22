require 'action_controller/request'
require 'action_controller/response'
require 'action_controller/routing'
require 'action_controller/url_rewriter'
require 'drb'

module ActionController #:nodoc:
  class ActionControllerError < StandardError #:nodoc:
  end
  class SessionRestoreError < ActionControllerError #:nodoc:
  end
  class MissingTemplate < ActionControllerError #:nodoc:
  end
  class RoutingError < ActionControllerError#:nodoc:
    attr_reader :failures
    def initialize(message, failures=[])
      super(message)
      @failures = failures
    end
  end
  class UnknownController < ActionControllerError #:nodoc:
  end
  class UnknownAction < ActionControllerError #:nodoc:
  end
  class MissingFile < ActionControllerError #:nodoc:
  end
  class DoubleRenderError < ActionControllerError #:nodoc:
  end

  # Action Controllers are made up of one or more actions that performs its purpose and then either renders a template or
  # redirects to another action. An action is defined as a public method on the controller, which will automatically be 
  # made accessible to the web-server through a mod_rewrite mapping. A sample controller could look like this:
  #
  #   class GuestBookController < ActionController::Base
  #     def index
  #       @entries = Entry.find_all
  #     end
  #     
  #     def sign
  #       Entry.create(@params["entry"])
  #       redirect_to :action => "index"
  #     end
  #   end
  #
  #   GuestBookController.template_root = "templates/"
  #   GuestBookController.process_cgi
  #
  # All actions assume that you want to render a template matching the name of the action at the end of the performance
  # unless you tell it otherwise. The index action complies with this assumption, so after populating the @entries instance
  # variable, the GuestBookController will render "templates/guestbook/index.rhtml".
  #
  # Unlike index, the sign action isn't interested in rendering a template. So after performing its main purpose (creating a 
  # new entry in the guest book), it sheds the rendering assumption and initiates a redirect instead. This redirect works by
  # returning an external "302 Moved" HTTP response that takes the user to the index action.
  #
  # The index and sign represent the two basic action archetypes used in Action Controllers. Get-and-show and do-and-redirect.
  # Most actions are variations of these themes.
  #
  # Also note that it's the final call to <tt>process_cgi</tt> that actually initiates the action performance. It will extract
  # request and response objects from the CGI
  #
  # == Requests
  #
  # Requests are processed by the Action Controller framework by extracting the value of the "action" key in the request parameters.
  # This value should hold the name of the action to be performed. Once the action has been identified, the remaining
  # request parameters, the session (if one is available), and the full request with all the http headers are made available to
  # the action through instance variables. Then the action is performed.
  #
  # The full request object is available in @request and is primarily used to query for http headers. These queries are made by
  # accessing the environment hash, like this:
  #
  #   def hello_ip
  #     location = @request.env["REMOTE_IP"]
  #     render_text "Hello stranger from #{location}"
  #   end
  #
  # == Parameters
  #
  # All request parameters whether they come from a GET or POST request, or from the URL, are available through the @params hash.
  # So an action that was performed through /weblog/list?category=All&limit=5 will include { "category" => "All", "limit" => 5 }
  # in @params.
  #
  # It's also possible to construct multi-dimensional parameter hashes by specifying keys using brackets, such as:
  #
  #   <input type="text" name="post[name]" value="david">
  #   <input type="text" name="post[address]" value="hyacintvej">
  #
  # A request stemming from a form holding these inputs will include <tt>{ "post" => { "name" => "david", "address" => "hyacintvej" } }</tt>.
  # If the address input had been named "post[address][street]", the @params would have included 
  # <tt>{ "post" => { "address" => { "street" => "hyacintvej" } } }</tt>. There's no limit to the depth of the nesting.
  #
  # == Sessions
  #
  # Sessions allows you to store objects in memory between requests. This is useful for objects that are not yet ready to be persisted,
  # such as a Signup object constructed in a multi-paged process, or objects that don't change much and are needed all the time, such
  # as a User object for a system that requires login. The session should not be used, however, as a cache for objects where it's likely 
  # they could be changed unknowingly. It's usually too much work to keep it all synchronized -- something databases already excel at.
  #
  # You can place objects in the session by using the <tt>@session</tt> hash:
  #
  #   @session[:person] = Person.authenticate(user_name, password)
  #
  # And retrieved again through the same hash:
  #
  #   Hello #{@session[:person]}
  #
  # Any object can be placed in the session (as long as it can be Marshalled). But remember that 1000 active sessions each storing a
  # 50kb object could lead to a 50MB memory overhead. In other words, think carefully about size and caching before resorting to the use
  # of the session.
  # 
  # If you store a model in the session, you must also include a line like:
  #
  #   model :person
  #
  # For that particular controller. In Rails, you can also just add it in your app/controller/application.rb file (so the model is available
  # for all controllers). This lets Action Pack know to have the model definition loaded before retrieving the object from the session.
  #
  # For removing objects from the session, you can either assign a single key to nil, like <tt>@session[:person] = nil</tt>, or you can
  # remove the entire session with reset_session.
  #
  # == Responses
  #
  # Each action results in a response, which holds the headers and document to be sent to the user's browser. The actual response
  # object is generated automatically through the use of renders and redirects, so it's normally nothing you'll need to be concerned about.
  #
  # == Renders
  #
  # Action Controller sends content to the user by using one of five rendering methods. The most versatile and common is the rendering
  # of a template. Included in the Action Pack is the Action View, which enables rendering of ERb templates. It's automatically configured.
  # The controller passes objects to the view by assigning instance variables:
  #
  #   def show
  #     @post = Post.find(@params["id"])
  #   end
  #
  # Which are then automatically available to the view:
  #
  #   Title: <%= @post.title %>
  #
  # You don't have to rely on the automated rendering. Especially actions that could result in the rendering of different templates will use
  # the manual rendering methods:
  #
  #   def search
  #     @results = Search.find(@params["query"])
  #     case @results
  #       when 0 then render "weblog/no_results"
  #       when 1 then render_action "show"
  #       when 2..10 then render_action "show_many"
  #     end
  #   end
  #
  # Read more about writing ERb and Builder templates in link:classes/ActionView/Base.html.
  #
  # == Redirects
  #
  # Redirecting is what actions that update the model do when they're done. The <tt>save_post</tt> method shouldn't be responsible for also
  # showing the post once it's saved -- that's the job for <tt>show_post</tt>. So once <tt>save_post</tt> has completed its business, it'll
  # redirect to <tt>show_post</tt>. All redirects are external, which means that when the user refreshes his browser, it's not going to save
  # the post again, but rather just show it one more time.
  # 
  # This sounds fairly simple, but the redirection is complicated by the quest for a phenomenon known as "pretty urls". Instead of accepting
  # the dreadful beings that is "weblog_controller?action=show&post_id=5", Action Controller goes out of its way to represent the former as
  # "/weblog/show/5". And this is even the simple case. As an example of a more advanced pretty url consider
  # "/library/books/ISBN/0743536703/show", which can be mapped to books_controller?action=show&type=ISBN&id=0743536703.
  # 
  # Redirects work by rewriting the URL of the current action. So if the show action was called by "/library/books/ISBN/0743536703/show", 
  # we can redirect to an edit action simply by doing <tt>redirect_to(:action => "edit")</tt>, which could throw the user to 
  # "/library/books/ISBN/0743536703/edit". Naturally, you'll need to setup the routes configuration file to point to the proper controller
  # and action in the first place, but once you have, it can be rewritten with ease.
  # 
  # Let's consider a bunch of examples on how to go from "/clients/37signals/basecamp/project/dash" to somewhere else:
  #
  #   redirect_to(:action => "edit") =>
  #     /clients/37signals/basecamp/project/dash
  #   
  #   redirect_to(:client_name => "nextangle", :project_name => "rails") =>
  #     /clients/nextangle/rails/project/dash
  #
  # Those redirects happen under the configuration of:
  #
  #   map.connect 'clients/:client_name/:project_name/:controller/:action'
  #
  # == Calling multiple redirects or renders
  #
  # The rule for handling calls of multiple redirects and renders is that the first call wins. So in the following example:
  #
  #   def do_something
  #     redirect_to :action => "elsewhere"
  #     render_action "overthere"
  #   end
  #
  # Only the redirect happens. The rendering call is simply ignored.
  #
  # == Environments
  #
  # Action Controller works out of the box with CGI, FastCGI, and mod_ruby. CGI and mod_ruby controllers are triggered just the same using:
  #
  #   WeblogController.process_cgi
  #
  # FastCGI controllers are triggered using:
  #
  #   FCGI.each_cgi{ |cgi| WeblogController.process_cgi(cgi) }
  class Base
    include ClassInheritableAttributes
  
    DEFAULT_RENDER_STATUS_CODE = "200 OK"
  
    # Determines whether the view has access to controller internals @request, @response, @session, and @template.
    # By default, it does.
    @@view_controller_internals = true
    cattr_accessor :view_controller_internals

    # Prepends all the URL-generating helpers from AssetHelper. This makes it possible to easily move javascripts, stylesheets, 
    # and images to a dedicated asset server away from the main web server. Example: 
    #   ActionController::Base.asset_host = "http://assets.example.com"
    @@asset_host = ""
    cattr_accessor :asset_host

    # All requests are considered local by default, so everyone will be exposed to detailed debugging screens on errors.
    # When the application is ready to go public, this should be set to false, and the protected method <tt>local_request?</tt>
    # should instead be implemented in the controller to determine when debugging screens should be shown.
    @@consider_all_requests_local = true
    cattr_accessor :consider_all_requests_local
    
    # Enable or disable the collection of failure information for RoutingErrors.
    # This information can be extremely useful when tweaking custom routes, but is
    # pointless once routes have been tested and verified.
    @@debug_routes = true
    cattr_accessor :debug_routes

    # Template root determines the base from which template references will be made. So a call to render("test/template")
    # will be converted to "#{template_root}/test/template.rhtml".
    class_inheritable_accessor :template_root

    # The logger is used for generating information on the action run-time (including benchmarking) if available.
    # Can be set to nil for no logging. Compatible with both Ruby's own Logger and Log4r loggers.
    cattr_accessor :logger
    
    # Determines which template class should be used by ActionController.
    cattr_accessor :template_class

    # Turn on +ignore_missing_templates+ if you want to unit test actions without making the associated templates.
    cattr_accessor :ignore_missing_templates

    # Holds the request object that's primarily used to get environment variables through access like
    # <tt>request.env["REQUEST_URI"]</tt>.
    attr_accessor :request
    
    # Holds a hash of all the GET, POST, and Url parameters passed to the action. Accessed like <tt>@params["post_id"]</tt>
    # to get the post_id. No type casts are made, so all values are returned as strings.
    attr_accessor :params
    
    # Holds the response object that's primarily used to set additional HTTP headers through access like 
    # <tt>response.headers["Cache-Control"] = "no-cache"</tt>. Can also be used to access the final body HTML after a template
    # has been rendered through response.body -- useful for <tt>after_filter</tt>s that wants to manipulate the output,
    # such as a OutputCompressionFilter.
    attr_accessor :response
    
    # Holds a hash of objects in the session. Accessed like <tt>session[:person]</tt> to get the object tied to the "person"
    # key. The session will hold any type of object as values, but the key should be a string.
    attr_accessor :session
    
    # Holds a hash of header names and values. Accessed like <tt>headers["Cache-Control"]</tt> to get the value of the Cache-Control
    # directive. Values should always be specified as strings.
    attr_accessor :headers
    
    # Holds the hash of variables that are passed on to the template class to be made available to the view. This hash
    # is generated by taking a snapshot of all the instance variables in the current scope just before a template is rendered.
    attr_accessor :assigns

    class << self
      # Factory for the standard create, process loop where the controller is discarded after processing.
      def process(request, response) #:nodoc:
        new.process(request, response)
      end
      
      # Converts the class name from something like "OneModule::TwoModule::NeatController" to "NeatController".
      def controller_class_name
        Inflector.demodulize(name)
      end

      # Converts the class name from something like "OneModule::TwoModule::NeatController" to "neat".
      def controller_name
        Inflector.underscore(controller_class_name.sub(/Controller/, ""))
      end
      
      # Convert the class name from something like "OneModule::TwoModule::NeatController" to "one_module/two_module/neat".
      def controller_path
        components = self.name.to_s.split('::').collect { |name| name.underscore }
        components[-1] = $1 if /^(.*)_controller$/ =~ components[-1]
        components.shift if components.first == 'controllers' # Transitional conditional to accomodate root Controllers module
        components.join('/')
      end

      # Return an array containing the names of public methods that have been marked hidden from the action processor.
      # By default, all methods defined in ActionController::Base and included modules are hidden.
      # More methods can be hidden using +hide_actions+.
      def hidden_actions
        write_inheritable_attribute(:hidden_actions, ActionController::Base.public_instance_methods) unless read_inheritable_attribute(:hidden_actions)
        read_inheritable_attribute(:hidden_actions)
      end

      # Hide each of the given methods from being callable as actions.
      def hide_action(*names)
        write_inheritable_attribute(:hidden_actions, hidden_actions | names.collect {|n| n.to_s})
      end

      # Set the template root to be one directory behind the root dir of the controller. Examples:
      #   /code/weblog/components/admin/users_controller.rb with Admin::UsersController 
      #     will use /code/weblog/components as template root 
      #     and find templates in /code/weblog/components/admin/users/
      #
      #   /code/weblog/components/admin/parties/users_controller.rb with Admin::Parties::UsersController 
      #     will also use /code/weblog/components as template root 
      #     and find templates in /code/weblog/components/admin/parties/users/
      def uses_component_template_root
        path_of_calling_controller = File.dirname(caller[0].split(/:\d+:/).first)
        path_of_controller_root    = path_of_calling_controller.sub(/#{controller_path.split("/")[0..-2]}$/, "")
        self.template_root = path_of_controller_root
      end
    end

    public
      # Extracts the action_name from the request parameters and performs that action.
      def process(request, response, method = :perform_action, *arguments) #:nodoc:
        initialize_template_class(response)
        assign_shortcuts(request, response)
        initialize_current_url

        log_processing unless logger.nil?
        send(method, *arguments)
        close_session

        return @response
      end

      # Returns a URL that has been rewritten according to the options hash and the defined Routes. 
      # (For doing a complete redirect, use redirect_to).
      #  
      # <tt>url_for</tt> is used to:
      #  
      # All keys given to url_for are forwarded to the Route module save for the following:
      # * <tt>:anchor</tt> -- specifies the anchor name to be appended to the path. For example, 
      #   <tt>url_for :controller => 'posts', :action => 'show', :id => 10, :anchor => 'comments'</tt> 
      #   will produce "/posts/show/10#comments".
      # * <tt>:only_path</tt> --  if true, returns the absolute URL (omitting the protocol, host name, and port)
      # * <tt>:trailing_slash</tt> --  if true, adds a trailing slash, as in "/archive/2005/". Note that this
      #   is currently not recommended since it breaks caching.
      # * <tt>:host</tt> -- overrides the default (current) host if provided
      # * <tt>:protocol</tt> -- overrides the default (current) protocol if provided
      #
      # The URL is generated from the remaining keys in the hash. A URL contains two key parts: the <base> and a query string.
      # Routes composes a query string as the key/value pairs not included in the <base>.
      #
      # The default Routes setup supports a typical Rails path of "controller/action/id" where action and id are optional, with
      # action defaulting to 'index' when not given. Here are some typical url_for statements and their corresponding URLs:
      #  
      #   url_for :controller => 'posts', :action => 'recent' # => 'proto://host.com/posts/recent'
      #   url_for :controller => 'posts', :action => 'index' # => 'proto://host.com/posts'
      #   url_for :controller => 'posts', :action => 'show', :id => 10 # => 'proto://host.com/posts/show/10'
      #
      # When generating a new URL, missing values may be filled in from the current request's parameters. For example,
      # <tt>url_for :action => 'some_action'</tt> will retain the current controller, as expected. This behavior extends to
      # other parameters, including <tt>:controller</tt>, <tt>:id</tt>, and any other parameters that are placed into a Route's
      # path.
      #  
      # The URL helpers such as <tt>url_for</tt> have a limited form of memory: when generating a new URL, they can look for
      # missing values in the current request's parameters. Routes attempts to guess when a value should and should not be
      # taken from the defaults. There are a few simple rules on how this is performed:
      #
      # * If the controller name begins with a slash, no defaults are used: <tt>url_for :controller => '/home'</tt>
      # * If the controller changes, the action will default to index unless provided
      #
      # The final rule is applied while the URL is being generated and is best illustrated by an example. Let us consider the
      # route given by <tt>map.connect 'people/:last/:first/:action', :action => 'bio', :controller => 'people'</tt>.
      #
      # Suppose that the current URL is "people/hh/david/contacts". Let's consider a few different cases URLs which are generated
      # from this page.
      #
      # * <tt>url_for :action => 'bio'</tt> -- During the generation of this URL, default values will be used for the first and
      # last components, and the action shall change. The generated URL will be, "people/hh/david/bio".
      # * <tt>url_for :first => 'davids-little-brother'</tt> This generates the URL 'people/hh/davids-little-brother' -- note
      #   that this URL leaves out the assumed action of 'bio'.
      #
      # However, you might ask why the action from the current request, 'contacts', isn't carried over into the new URL. The
      # answer has to do with the order in which the parameters appear in the generated path. In a nutshell, since the
      # value that appears in the slot for <tt>:first</tt> is not equal to default value for <tt>:first</tt> we stop using
      # defaults. On it's own, this rule can account for much of the typical Rails URL behavior.
      #  
      # Although a convienence, defaults can occasionaly get in your way. In some cases a default persists longer than desired.
      # The default may be cleared by adding <tt>:name => nil</tt> to <tt>url_for</tt>'s options.
      # This is often required when writing form helpers, since the defaults in play may vary greatly depending upon where the
      # helper is used from. The following line will redirect to PostController's default action, regardless of the page it is
      # displayed on:
      #
      #   url_for :controller => 'posts', :action => nil
      #      
      # Instead of passing an options hash, you can also pass a method reference in the form of a symbol. Consider this example:
      #
      #   class WeblogController < ActionController::Base
      #     def update
      #       # do some update
      #       redirect_to :dashboard_url
      #     end
      #     
      #     protected
      #       def dashboard_url
      #         url_for :controller => (@project.active? ? "project" : "account"), :action => "dashboard"
      #       end
      #   end
      def url_for(options = {}, *parameters_for_method_reference) #:doc:
        case options
          when String then options
          when Symbol then send(options, *parameters_for_method_reference)
          when Hash   then @url.rewrite(rewrite_options(options))
        end
      end

      # Converts the class name from something like "OneModule::TwoModule::NeatController" to "NeatController".
      def controller_class_name
        self.class.controller_class_name
      end

      # Converts the class name from something like "OneModule::TwoModule::NeatController" to "neat".
      def controller_name
        self.class.controller_name
      end

      # Returns the name of the action this controller is processing.
      def action_name
        @params["action"] || "index"
      end

    protected
      # Renders the template specified by <tt>template_name</tt>, which defaults to the name of the current controller and action.
      # So calling +render+ in WeblogController#show will attempt to render "#{template_root}/weblog/show.rhtml" or 
      # "#{template_root}/weblog/show.rxml" (in that order). The template_root is set on the ActionController::Base class and is 
      # shared by all controllers. It's also possible to pass a status code using the second parameter. This defaults to "200 OK", 
      # but can be changed, such as by calling <tt>render("weblog/error", "500 Error")</tt>.

      # A unified replacement for the individual renders (work-in-progress).
      def render(options = {}, deprecated_status = nil)
        # puts "Rendering: #{options.inspect}"
        raise DoubleRenderError, "Can only render or redirect once per action" if performed?

        # Backwards compatibility
        return render({ :template => options || default_template_name, :status => deprecated_status }) if !options.is_a?(Hash)

        add_variables_to_assigns
        options[:status] = (options[:status] || DEFAULT_RENDER_STATUS_CODE).to_s

        if options[:text]
          @response.headers["Status"] = options[:status]
          @response.body = options[:text]
          @performed_render = true
          return options[:text]

        elsif options[:file]
          assert_existance_of_template_file(options[:file]) if options[:use_full_path]
          logger.info("Rendering #{options[:file]} (#{options[:status]})") unless logger.nil?
          render(options.merge({ :text => @template.render_file(options[:file], options[:use_full_path])}))

        elsif options[:template]
          render(options.merge({ :file => options[:template], :use_full_path => true }))

        elsif options[:inline]
          render(options.merge({ :text => @template.render_template(options[:type] || :rhtml, options[:inline]) }))

        elsif options[:action]
          render(options.merge({ :template => default_template_name(options[:action]) }))

        elsif options[:partial] && options[:collection]
          render(options.merge({ 
            :text => (
              @template.render_partial_collection(
                options[:partial], options[:collection], options[:spacer_template], options[:locals]
              ) || ''
            )
          }))

        elsif options[:partial]
          render(options.merge({ :text => @template.render_partial(options[:partial], options[:object], options[:locals]) }))
          
        elsif options[:nothing]
          render(options.merge({ :text => "" }))

        else
          render(options.merge({ :template => default_template_name }))
        end
      end

      # Returns the result of the render as a string.
      def render_to_string(options = {}) #:doc:
        result = render(options)
        erase_render_results
        return result
      end
      
      # Clears the rendered results, allowing for another render or redirect to be performed.
      def erase_render_results #:nodoc:
        @response.body = nil
        @performed_render = false
      end

      def rewrite_options(options)
        if defaults = default_url_options(options)
          defaults.merge(options)
        else
          options
        end
      end
      
      # Overwrite to implement a number of default options that all url_for-based methods will use. The default options should come in
      # the form of a hash, just like the one you would use for url_for directly. Example:
      #
      #   def default_url_options(options)
      #     { :project => @project.active? ? @project.url_name : "unknown" }
      #   end
      #
      # As you can infer from the example, this is mostly useful for situations where you want to centralize dynamic decisions about the
      # urls as they stem from the business domain. Please note that any individual url_for call can always override the defaults set
      # by this method.
      def default_url_options(options) #:doc:
      end
      
      # Redirects the browser to the target specified in +options+. This parameter can take one of three forms:
      #
      # * <tt>Hash</tt>: The URL will be generated by calling url_for with the +options+.
      # * <tt>String starting with protocol:// (like http://)</tt>: Is passed straight through as the target for redirection.
      # * <tt>String not containing a protocol</tt>: The current current protocol and host is prepended to the string.
      # 
      # Examples:
      #   redirect_to :action => "show", :id => 5
      #   redirect_to "http://www.rubyonrails.org"
      #   redirect_to "/images/screenshot.jpg"
      #
      # The redirection happens as a "302 Moved" header.
      def redirect_to(options = {}, *parameters_for_method_reference) #:doc:
        case options
          when %r{^\w+://.*}
            raise DoubleRenderError, "Can only render or redirect once per action" if performed?
            logger.info("Redirected to #{options}") unless logger.nil?
            response.redirect(options)
            response.redirected_to = options
            @performed_redirect = true

          when String
            redirect_to(request.protocol + request.host_with_port + options)

          else
            if parameters_for_method_reference.empty?
              redirect_to(url_for(options))
              response.redirected_to = options
            else
              redirect_to(url_for(options, *parameters_for_method_reference))
              response.redirected_to, response.redirected_to_method_params = options, parameters_for_method_reference
            end
        end
      end

      # Resets the session by clearing out all the objects stored within and initializing a new session object.
      def reset_session #:doc:
        @request.reset_session
        @session = @request.session
        @response.session = @session
      end
    
    private
      def initialize_template_class(response)
        begin
          response.template = template_class.new(template_root, {}, self)
        rescue
          raise "You must assign a template class through ActionController.template_class= before processing a request"
        end
        
        @performed_render = @performed_redirect = false
      end
    
      def assign_shortcuts(request, response)
        @request, @params, @cookies = request, request.parameters, request.cookies

        @response         = response
        @response.session = request.session

        @session  = @response.session
        @template = @response.template
        @assigns  = @response.template.assigns        
        @headers  = @response.headers
      end
      
      def initialize_current_url
        @url = UrlRewriter.new(@request, @params.clone())
      end

      def log_processing
        logger.info "\n\nProcessing #{controller_class_name}\##{action_name} (for #{request_origin})"
        logger.info "  Parameters: #{@params.inspect}"
      end
    
      def perform_action
        if action_methods.include?(action_name) || action_methods.include?('method_missing')
          send(action_name)
          render unless performed?
        elsif template_exists? && template_public?
          render
        else
          raise UnknownAction, "No action responded to #{action_name}", caller
        end
      end
      
      def performed?
        @performed_render || @performed_redirect
      end

      def action_methods
        @action_methods ||= (self.class.public_instance_methods - self.class.hidden_actions)
      end


      def add_variables_to_assigns
        add_instance_variables_to_assigns
        add_class_variables_to_assigns if view_controller_internals
      end

      def add_instance_variables_to_assigns
        protected_variables_cache = protected_instance_variables
        instance_variables.each do |var|
          next if protected_variables_cache.include?(var)
          @assigns[var[1..-1]] = instance_variable_get(var)
        end
      end

      def add_class_variables_to_assigns
        %w( template_root logger template_class ignore_missing_templates ).each do |cvar|
          @assigns[cvar] = self.send(cvar)
        end
      end

      def protected_instance_variables
        if view_controller_internals
          [ "@assigns", "@performed_redirect", "@performed_render" ]
        else
          [ "@assigns", "@performed_redirect", "@performed_render", "@request", "@response", "@session", "@cookies", "@template" ]
        end
      end


      def request_origin
        "#{@request.remote_ip} at #{Time.now.to_s}"
      end
      
      def close_session
        @session.close unless @session.nil? || Hash === @session
      end

      
      def template_exists?(template_name = default_template_name)
        @template.file_exists?(template_name)
      end

      def template_public?(template_name = default_template_name)
        @template.file_public?(template_name)
      end

      def assert_existance_of_template_file(template_name)
        unless template_exists?(template_name) || ignore_missing_templates
          full_template_path = @template.send(:full_template_path, template_name, 'rhtml')
          template_type = (template_name =~ /layouts/i) ? 'layout' : 'template'
          raise(MissingTemplate, "Missing #{template_type} #{full_template_path}")
        end
      end

      def default_template_name(default_action_name = action_name)
        "#{self.class.controller_path}/#{default_action_name}"
      end
  end
end
