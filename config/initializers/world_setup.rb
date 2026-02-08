Rails.application.config.after_initialize do
  unless Rails.env.test?
    WorldService.setup_world
  end
end
