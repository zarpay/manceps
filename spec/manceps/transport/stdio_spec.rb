# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::Transport::Stdio do
  # A simple echo server: reads JSON lines from stdin, responds with a JSON-RPC result
  let(:echo_script) do
    <<~RUBY
      require "json"
      while line = $stdin.gets
        msg = JSON.parse(line)
        response = { "jsonrpc" => "2.0", "id" => msg["id"], "result" => { "echo" => msg["params"] } }
        $stdout.puts JSON.generate(response)
        $stdout.flush
      end
    RUBY
  end

  let(:script_path) do
    path = File.join(Dir.tmpdir, 'manceps_echo_server.rb')
    File.write(path, echo_script)
    path
  end

  after do
    FileUtils.rm_f(script_path)
  end

  describe '#open' do
    it 'spawns the subprocess' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      expect(transport).to be_a(described_class)
    ensure
      transport&.close
    end

    it 'cleans up the first process when called twice' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      first_pid = transport.instance_variable_get(:@wait_thread).pid

      transport.open

      second_pid = transport.instance_variable_get(:@wait_thread).pid

      expect(second_pid).not_to eq(first_pid)

      # The first process should have been terminated
      expect { Process.kill(0, first_pid) }.to raise_error(Errno::ESRCH)
    ensure
      transport&.close
    end
  end

  describe '#request' do
    it 'sends a JSON-RPC request and receives a response' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      body = { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'test', 'params' => { 'key' => 'value' } }
      response = transport.request(body)

      expect(response).to be_a(Hash)
      expect(response['jsonrpc']).to eq('2.0')
      expect(response['id']).to eq(1)
      expect(response['result']['echo']).to eq({ 'key' => 'value' })
    ensure
      transport&.close
    end

    it 'handles multiple sequential requests' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      r1 = transport.request({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'a', 'params' => {} })
      r2 = transport.request({ 'jsonrpc' => '2.0', 'id' => 2, 'method' => 'b', 'params' => {} })

      expect(r1['id']).to eq(1)
      expect(r2['id']).to eq(2)
    ensure
      transport&.close
    end

    it 'raises ConnectionError when process has exited' do
      transport = described_class.new('ruby', args: ['-e', 'exit'])
      transport.open
      sleep 0.1 # let the process exit

      expect do
        transport.request({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'test', 'params' => {} })
      end.to raise_error(Manceps::ConnectionError, /Process exited unexpectedly/)
    ensure
      transport&.close
    end

    it 'raises ConnectionError when transport is not open' do
      transport = described_class.new('ruby', args: [script_path])

      expect do
        transport.request({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'test', 'params' => {} })
      end.to raise_error(Manceps::ConnectionError, /not open/)
    end
  end

  describe '#notify' do
    it 'sends a message without waiting for a response' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      expect do
        transport.notify({ 'jsonrpc' => '2.0', 'method' => 'notifications/initialized' })
      end.not_to raise_error
    ensure
      transport&.close
    end
  end

  describe '#terminate_session' do
    it 'is a no-op' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      expect do
        transport.terminate_session('any-session-id')
      end.not_to raise_error
    ensure
      transport&.close
    end
  end

  describe '#close' do
    it 'terminates the subprocess' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      transport.close

      # Subsequent requests should fail
      expect do
        transport.request({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'test', 'params' => {} })
      end.to raise_error(Manceps::ConnectionError, /not open/)
    end

    it 'is safe to call multiple times' do
      transport = described_class.new('ruby', args: [script_path])
      transport.open

      expect do
        transport.close
        transport.close
      end.not_to raise_error
    end
  end

  describe '#read_response with interleaved notifications' do
    let(:notification_then_response_script) do
      <<~RUBY
        require "json"
        line = $stdin.gets
        msg = JSON.parse(line)
        # Send a notification first
        notification = { "jsonrpc" => "2.0", "method" => "notifications/tools/list_changed", "params" => {} }
        $stdout.puts JSON.generate(notification)
        $stdout.flush
        # Then send the actual response
        response = { "jsonrpc" => "2.0", "id" => msg["id"], "result" => { "echo" => msg["params"] } }
        $stdout.puts JSON.generate(response)
        $stdout.flush
      RUBY
    end

    let(:notification_script_path) do
      path = File.join(Dir.tmpdir, 'manceps_notif_server.rb')
      File.write(path, notification_then_response_script)
      path
    end

    after do
      FileUtils.rm_f(notification_script_path)
    end

    it 'skips notifications and returns the response' do
      transport = described_class.new('ruby', args: [notification_script_path])
      transport.open

      body = { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'test', 'params' => { 'key' => 'value' } }
      response = transport.request(body)

      expect(response['id']).to eq(1)
      expect(response['result']['echo']).to eq({ 'key' => 'value' })
    ensure
      transport&.close
    end

    it 'dispatches notifications to the callback' do
      transport = described_class.new('ruby', args: [notification_script_path])
      transport.open

      received_notifications = []
      transport.on_notification { |n| received_notifications << n }

      body = { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'test', 'params' => {} }
      transport.request(body)

      expect(received_notifications.length).to eq(1)
      expect(received_notifications.first['method']).to eq('notifications/tools/list_changed')
    ensure
      transport&.close
    end
  end

  describe '#listen' do
    let(:notification_stream_script) do
      <<~RUBY
        require "json"
        3.times do |i|
          notification = { "jsonrpc" => "2.0", "method" => "notifications/resources/updated", "params" => { "uri" => "file:///item\#{i}" } }
          $stdout.puts JSON.generate(notification)
          $stdout.flush
        end
      RUBY
    end

    let(:listen_script_path) do
      path = File.join(Dir.tmpdir, 'manceps_listen_server.rb')
      File.write(path, notification_stream_script)
      path
    end

    after do
      FileUtils.rm_f(listen_script_path)
    end

    it 'yields notifications until the process ends' do
      transport = described_class.new('ruby', args: [listen_script_path])
      transport.open

      received = []
      transport.listen { |n| received << n }

      expect(received.length).to eq(3)
      expect(received.map { |n| n['params']['uri'] }).to eq(%w[file:///item0 file:///item1 file:///item2])
    ensure
      transport&.close
    end

    it 'raises ConnectionError when transport is not open' do
      transport = described_class.new('ruby', args: [listen_script_path])

      expect do
        transport.listen { nil }
      end.to raise_error(Manceps::ConnectionError, /not open/)
    end
  end

  describe 'environment variables' do
    it 'passes env to the subprocess' do
      env_script = <<~RUBY
        require "json"
        line = $stdin.gets
        msg = JSON.parse(line)
        response = { "jsonrpc" => "2.0", "id" => msg["id"], "result" => { "val" => ENV["MANCEPS_TEST_VAR"] } }
        $stdout.puts JSON.generate(response)
        $stdout.flush
      RUBY

      path = File.join(Dir.tmpdir, 'manceps_env_test.rb')
      File.write(path, env_script)

      transport = described_class.new('ruby', args: [path], env: { 'MANCEPS_TEST_VAR' => 'hello' })
      transport.open

      response = transport.request({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'test', 'params' => {} })
      expect(response['result']['val']).to eq('hello')
    ensure
      transport&.close
      File.delete(path) if path && File.exist?(path)
    end
  end
end
