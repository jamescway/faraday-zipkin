require 'faraday'
require 'finagle-thrift'
require 'finagle-thrift/trace'
require 'uri'

require 'faraday/zipkin/version'

module Faraday
  module Zipkin
    class TraceHeaders < ::Faraday::Middleware
      B3_HEADERS = {
        :trace_id => "X-B3-TraceId",
        :parent_id => "X-B3-ParentSpanId",
        :span_id => "X-B3-SpanId",
        :sampled => "X-B3-Sampled"
      }.freeze

      def initialize(app, service_name=nil)
        @app = app
        @service_name = service_name
      end

      def call(env)
        trace_id = ::Trace.id

        # handle either a URI object (passed by Faraday v0.8.x in testing), or something string-izable
        url = env[:url].respond_to?(:host) ? env[:url] : URI.parse(env[:url].to_s)
        service_name = @service_name || url.host.split('.').first # default to url-derived service name
        endpoint = ::Trace::Endpoint.new(::Trace::Endpoint.host_to_i32(url.host), url.port, service_name)

        ::Trace.push(trace_id.next_id) do
          ::Trace.record(::Trace::Annotation.new(::Trace::Annotation::CLIENT_SEND, endpoint))
          B3_HEADERS.each do |method, header|
            env[:request_headers][header] = ::Trace.id.send(method).to_s
          end
          result = @app.call(env)
          ::Trace.record(::Trace::Annotation.new(::Trace::Annotation::CLIENT_RECV, endpoint))
          result
        end
      end
    end
  end
end
