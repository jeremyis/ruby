require 'net/http'
require 'faye/websocket'
require 'eventmachine'

CONFIGLY_SERVER = 'api.config.ly'
CONFIGLY_VALUE_URL = '/api/v1/value'

module Configly
    class Client
        @keys = {}
        @caches = {}
        @use_ws = false
        def self.init
            @use_ws = true
            if get_api_key
                load_initial_data
                Thread.new { EM.run { start_web_socket_client }}
            end
        end

        def self.get_api_key
            return ENV['CONFIGLY_API_KEY']
        end

        def self.get_keys_to_preload
            return ENV['CONFIGLY_KEYS_TO_PRELOAD'].split(',')
        end

        def self.generate_qs(keys_to_preload)
            return keys_to_preload.map { |key| "keys[]=#{key}" }.join("&")
        end

        def self.load_initial_data
            @keys = fetch(get_keys_to_preload)
        end

        def self.start_web_socket_client
            ws = Faye::WebSocket::Client.new("ws://configly.herokuapp.com", nil, {:ping => 30})

            ws.on :open do |event|
                Rails.logger.debug :open
                ws.send(JSON.generate({"apiKey" => get_api_key, "type" => "handshake"}))
            end

            ws.on :message do |event|
                Rails.logger.debug :message
                data = JSON.parse(event.data)
                if data["type"] == "configUpdate"
                    payload = data["payload"]["payload"]
                    keyToUpdate = payload['key']
                    value = payload['value']
                    @keys[keyToUpdate] = value
                end

                Rails.logger.debug @keys
            end

            ws.on :close do |event|
                Rails.logger.debug :close
                Rails.logger.debug event.code
                start_web_socket_client
            end
        end

        def self.fetch(keys)
            uri = URI("https://#{CONFIGLY_SERVER}#{CONFIGLY_VALUE_URL}?#{generate_qs(keys)}")
            loaded_keys = {}
            Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
                request = Net::HTTP::Get.new uri
                request.basic_auth get_api_key, ''
                response = http.request request
                data = JSON.parse(response.body)['data']
                data.keys.each do |key|
                    loaded_keys[key] = data[key]['value']
                end
            end
            return loaded_keys
        end

        def self.get(key)
            if @use_ws
                if @keys.has_key? key
                    return @keys[key]
                else
                    raise KeyError.new(key)
                end
            else
                loaded_keys = fetch([key])
                if loaded_keys.has_key? key
                    return loaded_keys[key]
                else
                    raise KeyError.new(key)
                end
            end
        end
    end

    class KeyError < KeyError
        def initialize(key)
            super(key)
        end
    end
end