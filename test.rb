require 'byebug'

require './lib/tmsu_file_db.rb'
require './lib/tmsu_ruby.rb'

TmsuRuby.start

class User < TmsuModel
  # configure root_path: "."
end

byebug
false

