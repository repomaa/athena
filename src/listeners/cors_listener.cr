@[ADI::Register("@configuration_resolver", tags: ["athena.event_dispatcher.listener"])]
# Handles [Cross-Origin Resource Sharing](https://enable-cors.org) (CORS).
#
# Handles CORS preflight `OPTIONS` requests as well as adding CORS headers to each response.
# See `ART::Config::CORS` for information on configuring the listener.
struct Athena::Routing::Listeners::CORS
  include AED::EventListenerInterface
  include ADI::Service

  # :nodoc:
  ALLOW_SET_ORIGIN = "athena.routing.cors.allow_set_origin"
  private WILDCARD         = "*"
  private SIMPLE_HEADERS   = {
    "accept",
    "accept-language",
    "content-language",
    "content-type",
    "origin",
  }

  def self.subscribed_events : AED::SubscribedEvents
    AED::SubscribedEvents{
      ART::Events::Request  => 250,
      ART::Events::Response => 0,
    }
  end

  def initialize(@configuration_resolver : ACF::ConfigurationResolverInterface); end

  def call(event : ART::Events::Request, dispatcher : AED::EventDispatcherInterface) : Nil
    request = event.request

    # Return early if there is no configuration.
    return unless config = @configuration_resolver.resolve(ART::Config::CORS)

    # Return early if not a CORS request.
    # TODO: optimize this by also checking if origin matches the request's host.
    return unless request.headers.has_key? "origin"

    # If the request is a preflight, return the proper response.
    if request.method == "OPTIONS" && request.headers.has_key? "access-control-request-method"
      set_preflight_response config, event.request, event.response

      return event.finish_request
    end

    return unless check_origin config, event.request

    event.request.attributes[ALLOW_SET_ORIGIN] = true
  end

  def call(event : ART::Events::Response, dispatcher : AED::EventDispatcherInterface) : Nil
    # Return early if the request shouldn't have CORS set.
    return unless event.request.attributes[ALLOW_SET_ORIGIN]?

    # Return early if there is no configuration.
    return unless config = @configuration_resolver.resolve(ART::Config::CORS)

    # TODO: Add a configuration option to allow setting this explicitly
    event.response.headers["access-control-allow-origin"] = event.request.headers["origin"]
    event.response.headers["access-control-allow-credentials"] = "true" if config.allow_credentials
    event.response.headers["access-control-expose-headers"] = config.expose_headers.join(", ") unless config.expose_headers.empty?
  end

  # Configures the given *response* for CORS preflight
  private def set_preflight_response(config : ART::Config::CORS, request : HTTP::Request, response : HTTP::Server::Response) : Nil
    response.headers["vary"] = "origin"

    response.headers["access-control-allow-credentials"] = "true" if config.allow_credentials
    response.headers["access-control-max-age"] = config.max_age.to_s if config.max_age > 0
    response.headers["access-control-allow-methods"] = config.allow_methods.join(", ") unless config.allow_methods.empty?

    unless config.allow_headers.empty?
      headers : Array(String) = config.allow_headers.includes?(WILDCARD) ? request.headers["access-control-request-headers"].split(/,\ ?/) : config.allow_headers

      unless headers.empty?
        response.headers["access-control-allow-headers"] = headers.join(", ")
      end
    end

    unless check_origin config, request
      return request.headers.delete "access-control-allow-origin"
    end

    response.headers["access-control-allow-origin"] = request.headers["origin"]

    unless config.allow_methods.includes? request.headers["access-control-request-method"].upcase
      return response.status = :method_not_allowed
    end

    headers = (rh = request.headers["access-control-request-headers"]?) ? rh.split(/,\ ?/) : [] of String

    if !headers.empty? && !config.allow_headers.includes? WILDCARD
      headers.each do |header|
        next if SIMPLE_HEADERS.includes? header

        raise ART::Exceptions::Forbidden.new "Unauthorized header: '#{header}'" unless config.allow_headers.includes? header
      end
    end
  end

  private def check_origin(config : ART::Config::CORS, request : HTTP::Request) : Bool
    return true if config.allow_origin.includes?(WILDCARD)

    # Use case equality in case an origin is a Regex
    # TODO: Allow Regex when custom YAML tags are allowed
    config.allow_origin.any? &.===(request.headers["origin"])
  end
end
