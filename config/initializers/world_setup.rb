Rails.application.config.after_initialize do
  unless Rails.env.test?
    WorldService.setup_world
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
  # Database not available (e.g., during asset precompilation)
end
