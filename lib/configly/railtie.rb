module Configly
    class Railtie < Rails::Railtie
        config.after_initialize do
            if ENV['CONFIGLY_USE_WS']
                Client.init
            end
        end
    end
end