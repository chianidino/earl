require "uri"
require "socket"
require "./earl"
require "./socket/ssl_server"
require "./socket/tcp_server"
require "./socket/unix_server"

module Earl
  alias Socket = ::Socket | OpenSSL::SSL::Socket::Server

  abstract class SockServer < Supervisor
    abstract def call(client : Socket)

    def add_tcp_listener(host : String, port : Int32, *, backlog = ::Socket::SOMAXCONN) : Nil
      server = TCPServer.new(host, port, backlog) do |client|
        call(client)
      end
      monitor(server)
    end

    def add_ssl_listener(host : String, port : Int32, ssl_context : OpenSSL::SSL::Context::Server, *, backlog = ::Socket::SOMAXCONN) : Nil
      server = SSLServer.new(host, port, ssl_context, backlog) do |client|
        call(client)
      end
      monitor(server)
    end

    def add_unix_listener(path : String, *, mode = nil, backlog = ::Socket::SOMAXCONN) : Nil
      server = UNIXServer.new(path, mode, backlog) do |client|
        call(client)
      end
      monitor(server)
    end

    def add_listener(uri : String)
      add_listener URI.parse(uri)
    end

    def add_listener(uri : URI)
      params = HTTP::Params.parse(uri.query || "")

      case uri.scheme
      when "tcp"
        host, port = parse_host(uri)
        add_tcp_listener(host, port)
      when "ssl"
        host, port = parse_host(uri)
        add_ssl_listener(host, port, build_ssl_context(params))
      when "unix"
        mode = params["mode"]?.try(&.to_i)
        add_unix_listener(uri.path.not_nil!, mode: mode)
      else
        raise ArgumentError.new("unsupported socket type: #{uri}")
      end
    end

    private def parse_host(uri)
      port = uri.port
      raise ArgumentError.new("please specify a port to listen to") unless port

      host = uri.host
      raise ArgumentError.new("please specify a host or ip to listen to") unless host

      # remove ipv6 brackets
      if host.starts_with?('[') && host.ends_with?(']')
        host = host[1..-2]
      end

      {host, port}
    end

    private def build_ssl_context(params)
      ssl_context = OpenSSL::SSL::Context::Server.new

      if key = params["key"]?
        ssl_context.private_key = key
      else
        raise ArgumentError.new("please specify the SSL key via 'key='")
      end

      if cert = params["cert"]?
        ssl_context.certificate_chain = cert
      else
        raise ArgumentError.new("please specify the SSL certificate via 'cert='")
      end

      case params["verify_mode"]?
      when "peer"
        ssl_context.verify_mode = OpenSSL::SSL::VerifyMode::PEER
      when "force-peer"
        ssl_context.verify_mode = OpenSSL::SSL::VerifyMode::FAIL_IF_NO_PEER_CERT
      when "none"
        ssl_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      end

      if ca = params["ca"]?
        ssl_context.ca_certificates = ca
      elsif ssl_context.verify_mode.peer? || ssl_context.verify_mode.fail_if_no_peer_cert?
        raise ArgumentError.new("please specify the SSL ca via 'ca='")
      end

      ssl_context
    end
  end
end