# frozen_string_literal: true

module Drivers
  module Webserver
    class Nginx < Drivers::Webserver::Base
      adapter :nginx
      allowed_engines :nginx
      output filter: %i[
        build_type client_body_timeout client_header_timeout client_max_body_size dhparams keepalive_timeout
        log_dir log_level proxy_read_timeout proxy_send_timeout send_timeout ssl_for_legacy_browsers
        extra_config extra_config_ssl enable_upgrade_method port ssl_port
      ]
      notifies :deploy, action: :reload, resource: 'service[nginx]', timer: :delayed
      notifies :undeploy, action: :reload, resource: 'service[nginx]', timer: :delayed
      log_paths lambda { |context|
        %w[access.log error.log].map do |log_type|
          File.join(context.raw_out[:log_dir], "#{context.app[:domains].first}.#{log_type}")
        end
      }

      def self.passenger_supported?
        true
      end

      def settings
        output = node['defaults']['webserver'].merge(node['nginx']).merge(
          node['deploy'][app['shortname']]['webserver'] || {}
        ).symbolize_keys
        output[:extra_config_ssl] = output[:extra_config] if output[:extra_config_ssl] == true
        output
      end

      def setup
        unless out[:build_type].to_s == 'phusionpassenger'
          node.default['nginx']['install_method'] = out[:build_type].to_s == 'source' ? 'source' : 'package'
          recipe = out[:build_type].to_s == 'source' ? 'source' : 'default'
          context.include_recipe("chef_nginx::#{recipe}")
        else
          # do not use chef_nginx recipes for installation
          context.execute "apt-get install -y nginx-extras passenger"
          context.replace_or_add "Enable the Passenger Nginx module" do
            path "/etc/nginx/nginx.conf"
            pattern "# include /etc/nginx/passenger.conf;"
            line "include /etc/nginx/passenger.conf;"
            replace_only true
          end
        end
        define_service(:start)
      end

      def configure
        define_service
        add_ssl_directory
        add_ssl_item(:private_key)
        add_ssl_item(:certificate)
        add_ssl_item(:chain)
        add_dhparams

        add_appserver_config
        enable_appserver_config
        super
      end

      def before_deploy
        define_service
      end
      alias before_undeploy before_deploy

      def conf_dir
        File.join('/', 'etc', 'nginx')
      end

      def service_name
        'nginx'
      end

      def appserver_site_config_template(appserver_adapter)
        "appserver.#{adapter}.#{appserver_adapter == 'passenger' ? 'passenger' : 'upstream'}.conf.erb"
      end
      
    end
  end
end
