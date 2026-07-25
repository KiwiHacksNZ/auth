class DomainRedirect
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.host == "auth.kiwihacks.org" ||
       request.path.start_with?("/api") ||
       (request.path.start_with?("/oauth") && !request.path.start_with?("/oauth/authorize"))
      return @app.call(env)
    end

    # Redirect to auth.kiwihacks.org
    [ 301, { "Location" => "https://auth.kiwihacks.org#{request.fullpath}", "Content-Type" => "text/html" }, [] ]
  end
end
