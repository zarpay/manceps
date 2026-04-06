# frozen_string_literal: true

require_relative 'lib/manceps/version'

Gem::Specification.new do |spec|
  spec.name          = 'manceps'
  spec.version       = Manceps::VERSION
  spec.authors       = ['Obie Fernandez']
  spec.email         = ['obie@fernandez.net']

  spec.summary       = 'Ruby client for the Model Context Protocol (MCP)'
  spec.description   = 'A production-grade MCP client with first-class auth support. ' \
                        'Connect to MCP servers over Streamable HTTP or stdio, ' \
                        'discover and invoke tools, read resources, and get prompts.'
  spec.homepage      = 'https://github.com/zarpay/manceps'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.4.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'base64', '~> 0.2'
  spec.add_dependency 'httpx', '~> 1.0'
end
