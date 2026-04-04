require "spec_helper"

RSpec.describe Manceps::Auth::OAuth do
  let(:token_url) { "https://auth.example.com/token" }
  let(:access_token) { "access-token-123" }
  let(:refresh_token) { "refresh-token-456" }
  let(:client_id) { "client-id-abc" }
  let(:client_secret) { "client-secret-xyz" }

  describe "#apply" do
    it "sets Bearer header with the access token" do
      auth = described_class.new(access_token: access_token)
      headers = {}

      auth.apply(headers)

      expect(headers["authorization"]).to eq("Bearer access-token-123")
    end

    it "refreshes the token when it is expiring soon" do
      auth = described_class.new(
        access_token: "old-token",
        refresh_token: refresh_token,
        token_url: token_url,
        client_id: client_id,
        expires_at: Time.now + 60 # expires in 60s, within the 300s threshold
      )

      stub_request(:post, token_url)
        .with(
          headers: { "Content-Type" => "application/x-www-form-urlencoded" },
          body: URI.encode_www_form({
            "grant_type" => "refresh_token",
            "refresh_token" => refresh_token,
            "client_id" => client_id
          })
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            "access_token" => "new-token",
            "refresh_token" => "new-refresh",
            "expires_in" => 3600
          })
        )

      headers = {}
      auth.apply(headers)

      expect(headers["authorization"]).to eq("Bearer new-token")
      expect(auth.access_token).to eq("new-token")
      expect(auth.refresh_token).to eq("new-refresh")
      expect(auth.expires_at).to be_within(5).of(Time.now + 3600)
    end

    it "does NOT refresh when the token is still valid" do
      auth = described_class.new(
        access_token: access_token,
        refresh_token: refresh_token,
        token_url: token_url,
        client_id: client_id,
        expires_at: Time.now + 600 # 10 minutes out, beyond the 5-minute threshold
      )

      headers = {}
      auth.apply(headers)

      expect(headers["authorization"]).to eq("Bearer access-token-123")
      # No HTTP request should have been made
      expect(WebMock).not_to have_requested(:post, token_url)
    end

    it "does NOT refresh when there is no refresh_token" do
      auth = described_class.new(
        access_token: access_token,
        token_url: token_url,
        client_id: client_id,
        expires_at: Time.now + 60 # expiring soon, but no refresh_token
      )

      headers = {}
      auth.apply(headers)

      expect(headers["authorization"]).to eq("Bearer access-token-123")
      expect(WebMock).not_to have_requested(:post, token_url)
    end

    it "calls on_token_refresh callback after a successful refresh" do
      callback_data = nil
      callback = ->(access_token:, refresh_token:, expires_at:) {
        callback_data = { access_token: access_token, refresh_token: refresh_token, expires_at: expires_at }
      }

      auth = described_class.new(
        access_token: "old-token",
        refresh_token: refresh_token,
        token_url: token_url,
        client_id: client_id,
        expires_at: Time.now + 60,
        on_token_refresh: callback
      )

      stub_request(:post, token_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "access_token" => "refreshed-token",
          "refresh_token" => "refreshed-refresh",
          "expires_in" => 7200
        })
      )

      auth.apply({})

      expect(callback_data).not_to be_nil
      expect(callback_data[:access_token]).to eq("refreshed-token")
      expect(callback_data[:refresh_token]).to eq("refreshed-refresh")
      expect(callback_data[:expires_at]).to be_within(5).of(Time.now + 7200)
    end

    it "includes client_secret in refresh request when provided" do
      auth = described_class.new(
        access_token: "old-token",
        refresh_token: refresh_token,
        token_url: token_url,
        client_id: client_id,
        client_secret: client_secret,
        expires_at: Time.now + 60
      )

      stub = stub_request(:post, token_url)
        .with(
          body: URI.encode_www_form({
            "grant_type" => "refresh_token",
            "refresh_token" => refresh_token,
            "client_id" => client_id,
            "client_secret" => client_secret
          })
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ "access_token" => "new-token", "expires_in" => 3600 })
        )

      auth.apply({})

      expect(stub).to have_been_requested
    end

    it "is thread-safe: two concurrent calls only refresh once" do
      auth = described_class.new(
        access_token: "old-token",
        refresh_token: refresh_token,
        token_url: token_url,
        client_id: client_id,
        expires_at: Time.now + 60
      )

      stub = stub_request(:post, token_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "access_token" => "new-token",
          "expires_in" => 3600
        })
      )

      barrier = Queue.new
      threads = 2.times.map do
        Thread.new do
          barrier.pop # wait for signal
          auth.apply({})
        end
      end

      # Release both threads at once
      2.times { barrier << :go }
      threads.each(&:join)

      expect(stub).to have_been_requested.once
    end
  end

  describe ".generate_pkce" do
    it "returns a hash with verifier and challenge" do
      pkce = described_class.generate_pkce

      expect(pkce).to have_key(:verifier)
      expect(pkce).to have_key(:challenge)
      expect(pkce[:verifier]).to be_a(String)
      expect(pkce[:challenge]).to be_a(String)
    end

    it "produces a challenge that is the SHA-256 of the verifier, base64url-encoded" do
      pkce = described_class.generate_pkce

      expected_challenge = Base64.urlsafe_encode64(
        OpenSSL::Digest::SHA256.digest(pkce[:verifier]), padding: false
      )
      expect(pkce[:challenge]).to eq(expected_challenge)
    end

    it "generates unique values each time" do
      a = described_class.generate_pkce
      b = described_class.generate_pkce

      expect(a[:verifier]).not_to eq(b[:verifier])
    end
  end

  describe ".authorize_url" do
    it "builds a correct URL with all params" do
      url = described_class.authorize_url(
        authorization_url: "https://auth.example.com/authorize",
        client_id: "my-client",
        redirect_uri: "https://app.example.com/callback",
        state: "random-state-123"
      )

      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query).to_h

      expect(uri.scheme).to eq("https")
      expect(uri.host).to eq("auth.example.com")
      expect(uri.path).to eq("/authorize")
      expect(params["response_type"]).to eq("code")
      expect(params["client_id"]).to eq("my-client")
      expect(params["redirect_uri"]).to eq("https://app.example.com/callback")
      expect(params["state"]).to eq("random-state-123")
    end

    it "includes scopes when provided" do
      url = described_class.authorize_url(
        authorization_url: "https://auth.example.com/authorize",
        client_id: "my-client",
        redirect_uri: "https://app.example.com/callback",
        state: "state",
        scopes: ["read", "write"]
      )

      params = URI.decode_www_form(URI.parse(url).query).to_h
      expect(params["scope"]).to eq("read write")
    end

    it "includes PKCE code_challenge when provided" do
      url = described_class.authorize_url(
        authorization_url: "https://auth.example.com/authorize",
        client_id: "my-client",
        redirect_uri: "https://app.example.com/callback",
        state: "state",
        code_challenge: "abc123challenge"
      )

      params = URI.decode_www_form(URI.parse(url).query).to_h
      expect(params["code_challenge"]).to eq("abc123challenge")
      expect(params["code_challenge_method"]).to eq("S256")
    end

    it "omits scope when scopes is nil" do
      url = described_class.authorize_url(
        authorization_url: "https://auth.example.com/authorize",
        client_id: "my-client",
        redirect_uri: "https://app.example.com/callback",
        state: "state"
      )

      params = URI.decode_www_form(URI.parse(url).query).to_h
      expect(params).not_to have_key("scope")
    end
  end

  describe ".exchange_code" do
    let(:exchange_url) { "https://auth.example.com/token" }

    it "POSTs to token_url and returns token data" do
      stub_request(:post, exchange_url)
        .with(
          headers: { "Content-Type" => "application/x-www-form-urlencoded" },
          body: URI.encode_www_form({
            "grant_type" => "authorization_code",
            "code" => "auth-code-xyz",
            "redirect_uri" => "https://app.example.com/callback",
            "client_id" => "my-client"
          })
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            "access_token" => "new-access",
            "refresh_token" => "new-refresh",
            "expires_in" => 3600,
            "token_type" => "Bearer"
          })
        )

      result = described_class.exchange_code(
        token_url: exchange_url,
        client_id: "my-client",
        code: "auth-code-xyz",
        redirect_uri: "https://app.example.com/callback"
      )

      expect(result["access_token"]).to eq("new-access")
      expect(result["refresh_token"]).to eq("new-refresh")
      expect(result["expires_in"]).to eq(3600)
    end

    it "includes client_secret when provided" do
      stub = stub_request(:post, exchange_url)
        .with(body: /client_secret=secret/)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ "access_token" => "tok" })
        )

      described_class.exchange_code(
        token_url: exchange_url,
        client_id: "my-client",
        code: "code",
        redirect_uri: "https://app.example.com/callback",
        client_secret: "secret"
      )

      expect(stub).to have_been_requested
    end

    it "includes code_verifier when provided" do
      stub = stub_request(:post, exchange_url)
        .with(body: /code_verifier=verifier123/)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ "access_token" => "tok" })
        )

      described_class.exchange_code(
        token_url: exchange_url,
        client_id: "my-client",
        code: "code",
        redirect_uri: "https://app.example.com/callback",
        code_verifier: "verifier123"
      )

      expect(stub).to have_been_requested
    end

    it "raises AuthenticationError when token endpoint returns non-JSON response" do
      stub_request(:post, exchange_url).to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: "<html>500 Internal Server Error</html>"
      )

      expect {
        described_class.exchange_code(
          token_url: exchange_url,
          client_id: "my-client",
          code: "auth-code",
          redirect_uri: "https://app.example.com/callback"
        )
      }.to raise_error(Manceps::AuthenticationError, /Invalid response from server \(not JSON\)/)
    end

    it "raises AuthenticationError when no access_token in response" do
      stub_request(:post, exchange_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({ "error" => "invalid_grant", "error_description" => "Code expired" })
      )

      expect {
        described_class.exchange_code(
          token_url: exchange_url,
          client_id: "my-client",
          code: "bad-code",
          redirect_uri: "https://app.example.com/callback"
        )
      }.to raise_error(Manceps::AuthenticationError, /Code expired/)
    end
  end

  describe ".discover" do
    let(:server_url) { "https://mcp.example.com" }
    let(:well_known_url) { "https://mcp.example.com/.well-known/oauth-authorization-server" }

    it "fetches .well-known metadata and registers a client" do
      stub_request(:get, well_known_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token",
          "registration_endpoint" => "https://mcp.example.com/register",
          "scopes_supported" => ["mcp:tools", "mcp:resources"]
        })
      )

      stub_request(:post, "https://mcp.example.com/register")
        .with(
          headers: { "Content-Type" => "application/json" },
          body: hash_including({
            "client_name" => "Manceps",
            "redirect_uris" => ["https://app.example.com/callback"],
            "grant_types" => ["authorization_code", "refresh_token"],
            "response_types" => ["code"],
            "token_endpoint_auth_method" => "client_secret_post"
          })
        )
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            "client_id" => "registered-client-id",
            "client_secret" => "registered-secret"
          })
        )

      discovery = described_class.discover(server_url, redirect_uri: "https://app.example.com/callback")

      expect(discovery).to be_a(Manceps::Auth::OAuth::Discovery)
      expect(discovery.authorization_url).to eq("https://mcp.example.com/authorize")
      expect(discovery.token_url).to eq("https://mcp.example.com/token")
      expect(discovery.client_id).to eq("registered-client-id")
      expect(discovery.client_secret).to eq("registered-secret")
      expect(discovery.scopes).to eq(["mcp:tools", "mcp:resources"])
    end

    it "skips registration when no registration_endpoint" do
      stub_request(:get, well_known_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token"
        })
      )

      discovery = described_class.discover(server_url, redirect_uri: "https://app.example.com/callback")

      expect(discovery.authorization_url).to eq("https://mcp.example.com/authorize")
      expect(discovery.token_url).to eq("https://mcp.example.com/token")
      expect(discovery.client_id).to be_nil
      expect(discovery.client_secret).to be_nil
    end

    it "raises AuthenticationError when discovery endpoint returns an error" do
      stub_request(:get, well_known_url).to_return(status: 404, body: "Not Found")

      expect {
        described_class.discover(server_url, redirect_uri: "https://app.example.com/callback")
      }.to raise_error(Manceps::AuthenticationError, /OAuth discovery failed/)
    end

    it "raises AuthenticationError when registration fails" do
      stub_request(:get, well_known_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token",
          "registration_endpoint" => "https://mcp.example.com/register"
        })
      )

      stub_request(:post, "https://mcp.example.com/register").to_return(
        status: 400,
        body: "Bad Request"
      )

      expect {
        described_class.discover(server_url, redirect_uri: "https://app.example.com/callback")
      }.to raise_error(Manceps::AuthenticationError, /Client registration failed/)
    end

    it "raises AuthenticationError when discovery returns non-JSON response" do
      stub_request(:get, well_known_url).to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: "<html><body>Internal Server Error</body></html>"
      )

      expect {
        described_class.discover(server_url, redirect_uri: "https://app.example.com/callback")
      }.to raise_error(Manceps::AuthenticationError, /Invalid response from server \(not JSON\)/)
    end

    it "raises AuthenticationError when registration returns non-JSON response" do
      stub_request(:get, well_known_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token",
          "registration_endpoint" => "https://mcp.example.com/register"
        })
      )

      stub_request(:post, "https://mcp.example.com/register").to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: "<html>Server Error</html>"
      )

      expect {
        described_class.discover(server_url, redirect_uri: "https://app.example.com/callback")
      }.to raise_error(Manceps::AuthenticationError, /Invalid response from server \(not JSON\)/)
    end

    it "handles non-standard ports in the well-known URL" do
      stub = stub_request(:get, "https://mcp.example.com:8443/.well-known/oauth-authorization-server")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            "authorization_endpoint" => "https://mcp.example.com:8443/authorize",
            "token_endpoint" => "https://mcp.example.com:8443/token"
          })
        )

      described_class.discover("https://mcp.example.com:8443/mcp", redirect_uri: "https://app.example.com/callback")

      expect(stub).to have_been_requested
    end

    it "passes custom client_name to registration" do
      stub_request(:get, well_known_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "authorization_endpoint" => "https://mcp.example.com/authorize",
          "token_endpoint" => "https://mcp.example.com/token",
          "registration_endpoint" => "https://mcp.example.com/register"
        })
      )

      reg_stub = stub_request(:post, "https://mcp.example.com/register")
        .with(body: hash_including({ "client_name" => "MyApp" }))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ "client_id" => "id", "client_secret" => "secret" })
        )

      described_class.discover(server_url, redirect_uri: "https://app.example.com/callback", client_name: "MyApp")

      expect(reg_stub).to have_been_requested
    end
  end
end
