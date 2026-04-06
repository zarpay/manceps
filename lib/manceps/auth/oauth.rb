# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'securerandom'
require 'uri'
require 'json'

module Manceps
  module Auth
    # OAuth 2.1 authentication with discovery, PKCE, and token refresh.
    class OAuth
      Discovery = Struct.new(
        :authorization_url,
        :token_url,
        :registration_endpoint,
        :client_id,
        :client_secret,
        :scopes,
        keyword_init: true
      )

      attr_reader :access_token, :refresh_token, :expires_at

      def initialize(
        access_token:,
        refresh_token: nil,
        token_url: nil,
        client_id: nil,
        client_secret: nil,
        expires_at: nil,
        on_token_refresh: nil
      )
        @access_token = access_token
        @refresh_token = refresh_token
        @token_url = token_url
        @client_id = client_id
        @client_secret = client_secret
        @expires_at = expires_at
        @on_token_refresh = on_token_refresh
        @mutex = Mutex.new
      end

      def apply(headers)
        refresh_if_needed!
        headers['authorization'] = "Bearer #{@access_token}"
      end

      # Fetch OAuth Authorization Server Metadata (RFC 8414) and optionally
      # perform Dynamic Client Registration (RFC 7591).
      def self.discover(server_url, redirect_uri:, client_name: 'Manceps')
        server_uri = URI.parse(server_url)
        port_suffix = [80, 443].include?(server_uri.port) ? '' : ":#{server_uri.port}"
        well_known = "#{server_uri.scheme}://#{server_uri.host}#{port_suffix}/.well-known/oauth-authorization-server"

        http = HTTPX.with(timeout: { connect_timeout: 10, request_timeout: 30 })
        metadata = fetch_json(http.get(well_known), 'OAuth discovery')

        discovery = Discovery.new(
          authorization_url: metadata['authorization_endpoint'],
          token_url: metadata['token_endpoint'],
          registration_endpoint: metadata['registration_endpoint'],
          scopes: metadata['scopes_supported']
        )

        register_client(http, discovery, redirect_uri, client_name)
        discovery
      end

      def self.register_client(http, discovery, redirect_uri, client_name)
        reg_endpoint = discovery.registration_endpoint
        return if reg_endpoint.nil? || reg_endpoint.empty?

        reg_response = http.post(
          reg_endpoint,
          headers: { 'content-type' => 'application/json' },
          body: JSON.generate({
                                client_name: client_name,
                                redirect_uris: [redirect_uri],
                                grant_types: %w[authorization_code refresh_token],
                                response_types: ['code'],
                                token_endpoint_auth_method: 'client_secret_post'
                              })
        )

        reg_data = fetch_json(reg_response, 'Client registration')
        unless reg_data['client_id']
          raise Manceps::AuthenticationError,
                "Client registration failed: #{reg_data['error']}"
        end

        discovery.client_id = reg_data['client_id']
        discovery.client_secret = reg_data['client_secret']
      end

      def self.fetch_json(response, context)
        if response.status >= 400
          raise Manceps::AuthenticationError,
                "#{context} failed (HTTP #{response.status})"
        end

        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise Manceps::AuthenticationError,
              "#{context}: invalid response (not JSON): #{response.body.to_s[0..200]}"
      end

      # Build authorization URL for user redirect
      def self.authorize_url(authorization_url:, client_id:, redirect_uri:, state:, scopes: nil, code_challenge: nil)
        params = {
          'response_type' => 'code',
          'client_id' => client_id,
          'redirect_uri' => redirect_uri,
          'state' => state
        }
        params['scope'] = Array(scopes).join(' ') if !scopes.nil? && !Array(scopes).empty?
        if code_challenge
          params['code_challenge'] = code_challenge
          params['code_challenge_method'] = 'S256'
        end

        "#{authorization_url}?#{URI.encode_www_form(params)}"
      end

      # Exchange authorization code for tokens
      def self.exchange_code(token_url:, client_id:, code:, redirect_uri:, client_secret: nil, code_verifier: nil)
        body = {
          'grant_type' => 'authorization_code',
          'code' => code,
          'redirect_uri' => redirect_uri,
          'client_id' => client_id
        }
        body['client_secret'] = client_secret if !client_secret.nil? && !client_secret.empty?
        body['code_verifier'] = code_verifier if !code_verifier.nil? && !code_verifier.empty?

        http = HTTPX.with(timeout: { connect_timeout: 10, request_timeout: 30 })
        response = http.post(
          token_url,
          headers: { 'content-type' => 'application/x-www-form-urlencoded' },
          body: URI.encode_www_form(body)
        )

        data = fetch_json(response, 'Token exchange')
        unless data['access_token']
          raise Manceps::AuthenticationError,
                "Token exchange failed: #{data['error_description'] || data['error'] || 'no access_token'}"
        end

        data
      end

      # PKCE helpers (RFC 7636)
      def self.generate_pkce
        verifier = SecureRandom.urlsafe_base64(32)
        challenge = Base64.urlsafe_encode64(
          OpenSSL::Digest::SHA256.digest(verifier), padding: false
        )
        { verifier: verifier, challenge: challenge }
      end

      private

      def refresh_if_needed!
        return unless token_expiring_soon? && @refresh_token && @token_url

        @mutex.synchronize do
          return unless token_expiring_soon?

          perform_token_refresh
        end
      end

      def perform_token_refresh
        body = { 'grant_type' => 'refresh_token', 'refresh_token' => @refresh_token, 'client_id' => @client_id }
        body['client_secret'] = @client_secret if !@client_secret.nil? && !@client_secret.empty?

        http = HTTPX.with(timeout: { connect_timeout: 10, request_timeout: 30 })
        response = http.post(
          @token_url,
          headers: { 'content-type' => 'application/x-www-form-urlencoded' },
          body: URI.encode_www_form(body)
        )

        data = self.class.fetch_json(response, 'Token refresh')
        unless data['access_token']
          raise Manceps::AuthenticationError,
                "Token refresh failed: #{data['error'] || 'no access_token in response'}"
        end

        @access_token = data['access_token']
        @refresh_token = data['refresh_token'] if data['refresh_token']
        @expires_at = data['expires_in'] ? Time.now + data['expires_in'].to_i : nil

        @on_token_refresh&.call(access_token: @access_token, refresh_token: @refresh_token, expires_at: @expires_at)
      end

      def token_expiring_soon?
        @expires_at && @expires_at < Time.now + 300
      end
    end
  end
end
