Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "https://stlucyhomecoming.com",
            "https://www.stlucyhomecoming.com",
            %r{\Ahttp://localhost(:\d+)?\z},
            %r{\Ahttp://127\.0\.0\.1(:\d+)?\z}

    resource "/api/*",
             headers: :any,
             methods: %i[get post options]
  end
end
