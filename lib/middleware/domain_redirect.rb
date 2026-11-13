class DomainRedirect
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.host == "account.kiwihacks.com" ||
       request.path.start_with?("/api") ||
       (request.path.start_with?("/oauth") && !request.path.start_with?("/oauth/authorize"))
      return @app.call(env)
    end

    # Redirect to account.kiwihacks.com
    [ 301, { "Location" => "https://account.kiwihacks.com#{request.fullpath}", "Content-Type" => "text/html" }, [] ]
  end
end
