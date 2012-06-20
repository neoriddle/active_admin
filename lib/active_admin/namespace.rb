require 'active_admin/helpers/settings'
require 'active_admin/resource_collection'
require 'active_admin/menu_builder'

module ActiveAdmin

  class ResourceMismatchError < StandardError; end

  # Namespaces are the basic organizing principle for resources within Active Admin
  #
  # Each resource is registered into a namespace which defines:
  #   * the namespaceing for routing
  #   * the module to namespace controllers
  #   * the menu which gets displayed (other resources in the same namespace)
  #
  # For example:
  #   
  #   ActiveAdmin.register Post, :namespace => :admin
  #
  # Will register the Post model into the "admin" namespace. This will namespace the
  # urls for the resource to "/admin/posts" and will set the controller to
  # Admin::PostsController
  #
  # You can also register to the "root" namespace, which is to say no namespace at all.
  #
  #   ActiveAdmin.register Post, :namespace => false
  #
  # This will register the resource to an instantiated namespace called :root. The 
  # resource will be accessible from "/posts" and the controller will be PostsController.
  #
  class Namespace
    include Settings

    RegisterEvent = 'active_admin.namespace.register'.freeze

    attr_reader :application, :resources, :name, :menu

    def initialize(application, name)
      @application = application
      @name = name.to_s.underscore.to_sym
      @resources = ResourceCollection.new
      register_module unless root?
      generate_dashboard_controller
    end

    # Register a resource into this namespace. The preffered method to access this is to 
    # use the global registration ActiveAdmin.register which delegates to the proper 
    # namespace instance.
    def register(resource_class, options = {}, &block)
      config = find_or_build_resource(resource_class, options)

      # Register the resource
      register_resource_controller(config)
      parse_registration_block(config, &block) if block_given?
      reset_menu!

      # Ensure that the dashboard is generated
      generate_dashboard_controller

      # Dispatch a registration event
      ActiveAdmin::Event.dispatch ActiveAdmin::Resource::RegisterEvent, config

      # Return the config
      config
    end

    def register_page(name, options = {}, &block)
      config = build_page(name, options)

      # Register the resource
      register_page_controller(config)
      parse_page_registration_block(config, &block) if block_given?
      reset_menu!

      config
    end

    def root?
      name == :root
    end

    # Returns the name of the module if required. Will be nil if none
    # is required.
    #
    # eg: 
    #   Namespace.new(:admin).module_name # => 'Admin'
    #   Namespace.new(:root).module_name # => nil
    #
    def module_name
      return nil if root?
      @module_name ||= name.to_s.camelize
    end

    # Returns the name of the dashboard controller for this namespace
    def dashboard_controller_name
      [module_name, "DashboardController"].compact.join("::")
    end

    # Unload all the registered resources for this namespace
    def unload!
      unload_resources!
      unload_dashboard!
      reset_menu!
    end

    # Returns the first registered ActiveAdmin::Resource instance for a given class
    def resource_for(klass)
      resources.find_by_resource_class(klass)
    end

    # Override from ActiveAdmin::Settings to inherit default attributes
    # from the application
    def read_default_setting(name)
      application.send(name)
    end

    def menu
      @menu ||= MenuBuilder.build_for_namespace(self)
    end

    def reset_menu!
      @menu = nil
    end

    protected

    # Either returns an existing Resource instance or builds a new
    # one for the resource and options
    def find_or_build_resource(resource_class, options)
      resources.add Resource.new(self, resource_class, options)
    end

    def build_page(name, options)
      resources.add Page.new(self, name, options)
    end

    def register_page_controller(config)
      eval "class ::#{config.controller_name} < ActiveAdmin::PageController; end"
      config.controller.active_admin_config = config
    end

    def unload_resources!
      resources.each do |resource|
        parent = (module_name || 'Object').constantize
        const_name = resource.controller_name.split('::').last
        # Remove the const if its been defined
        parent.send(:remove_const, const_name) if parent.const_defined?(const_name)
      end
      @resources = ResourceCollection.new
    end

    def unload_dashboard!
      # TODO: Only clear out my sections
      Dashboards.clear_all_sections!
    end

    # Creates a ruby module to namespace all the classes in if required
    def register_module
      eval "module ::#{module_name}; end"
    end

    def register_resource_controller(config)
      eval "class ::#{config.controller_name} < ActiveAdmin::ResourceController; end"
      config.controller.active_admin_config = config
    end

    def parse_registration_block(config, &block)
      ResourceDSL.new(config).run_registration_block(&block)
    end

    def parse_page_registration_block(config, &block)
      PageDSL.new(config).run_registration_block(&block)
    end

    # Creates a dashboard controller for this config
    def generate_dashboard_controller
      return unless ActiveAdmin::Dashboards.built?

      eval "class ::#{dashboard_controller_name} < ActiveAdmin::PageController
              include ActiveAdmin::Dashboards::DashboardController
            end"
    end
  end
end
