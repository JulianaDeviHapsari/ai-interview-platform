# frozen_string_literal: true

# These files are named *_websocket_middleware.rb but define classes spelled
# "...WebSocket...". Zeitwerk would expect "...Websocket...", so eager loading
# (CI, production) failed with a NameError and the app could not boot.
# Tell the autoloader the real spelling instead of renaming the classes.
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect(
    'audio_websocket_middleware'    => 'AudioWebSocketMiddleware',
    'coverage_websocket_middleware' => 'CoverageWebSocketMiddleware'
  )
end
