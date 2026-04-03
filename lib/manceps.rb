require "json"
require "uri"
require "securerandom"

require "httpx"

require_relative "manceps/version"
require_relative "manceps/errors"
require_relative "manceps/json_rpc"
require_relative "manceps/sse_parser"
require_relative "manceps/content"
require_relative "manceps/tool"
require_relative "manceps/tool_result"
require_relative "manceps/prompt"
require_relative "manceps/prompt_result"
require_relative "manceps/resource"
require_relative "manceps/resource_template"
require_relative "manceps/resource_contents"
require_relative "manceps/session"
require_relative "manceps/auth/none"
require_relative "manceps/auth/bearer"
require_relative "manceps/auth/api_key_header"
require_relative "manceps/auth/oauth"
require_relative "manceps/transport/base"
require_relative "manceps/transport/streamable_http"
require_relative "manceps/transport/stdio"
require_relative "manceps/client"

module Manceps
  Configuration = Struct.new(
    :client_name,
    :client_version,
    :protocol_version,
    :request_timeout,
    :connect_timeout,
    keyword_init: true
  ) do
    def initialize(**)
      super
      self.client_name ||= "Manceps"
      self.client_version ||= Manceps::VERSION
      self.protocol_version ||= "2025-03-26"
      self.request_timeout ||= 30
      self.connect_timeout ||= 10
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
