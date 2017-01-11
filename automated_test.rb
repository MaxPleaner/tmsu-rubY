require 'byebug'
require 'tmsu_file_db'

require './automated_test_helper.rb'

`rm -rf db/*`

TmsuFileDb.start

# Model declaration
class User < TmsuModel
  configure root_path: "./db/users"
  validate do |record|
    record[:name].nil? ? ["name can't be blank"] : []
  end
  validate(:email) do |attr, record|
    attr&.include?("@") ? [] : ["email #{attr} isn't valid"]
  end
end

# Case 1 - validation errors on save + update
u = User.new name: "max"

fail_if     { u.valid? }

fail_unless { u.errors == ["email  isn't valid"] }

fail_if     { u.save }

fail_if     { u.update(name: "potato") }

fail_unless { u.name == "max" }

# Case 2 - succesful save + update
u[:email] = "maxpleaner@gmail.com"

fail_if     { u.persisted? }

fail_unless { u.valid? }

fail_unless { u.save }

fail_unless { u.persisted? }

fail_unless { u.update(email: "max.pleaner@gmail.com") }

fail_if     { u.update(email: "") }

# Case 3 - getters + setters
fail_unless { u.name == "max" }

fail_unless { u["name"] == "max" }

fail_unless { u[:name] == "max" }

u[:name] = "max p."

fail_unless { u[:name] == "max p." }

fail_unless { u.attributes[:name] == "max p." }

fail_unless { File.exists? u.path }

fail_unless { File.read(u.path).empty? }

u.save

u.write "hello"

fail_unless { File.read(u.path) == "hello" }

fail_unless { u.tags == { 'email' => "max.pleaner@gmail.com", 'name' => "max\\ p." } }

fail_unless { u.tags == u.attributes }

# Case 4 - destroy attribute, destroy_record
u.delete :name

# tag has been deleted
fail_unless { u.tags == { 'email' => "max.pleaner@gmail.com" } }

# destroy deletes the file from the filesystem
u.destroy

# destroy makes it no longer persisted
fail_if { u.persisted? }

# initialize a record from another's attributes
u = User.create(u.attributes.merge(name: "max p."))

# clone saved succesfully
fail_unless { u.persisted? }

fail_unless { User.where(name: "max\\ p.")[0]&.name == "max\\ p." }

fail_unless { User.find_by(name: "max\\ p.")&.name == "max\\ p." }

fail_unless { User.update_all(name: "max") }

fail_unless { User.all[0].name == "max" }

# Case4 - TmsuRuby.file

file_path = "db/#{SecureRandom.hex}"
`touch #{file_path}`
tmsu_file = TmsuRuby.file file_path

fail_unless { tmsu_file.tags == {} }

tmsu_file.tag "foo"

fail_unless { tmsu_file.tags ==  { 'foo' => nil  } }

tmsu_file.untag "foo"

fail_unless { tmsu_file.tags == { } }

tmsu_file.tag ["foo", "bar"]

fail_unless { tmsu_file.tags == { 'foo' => nil, 'bar' => nil } }

tmsu_file.tag(a: 1, b: 2)

fail_unless { tmsu_file.tags == { 'foo' => nil, 'bar' => nil, 'a' => "1", 'b' => "2" } }

`mkdir db/sample`

filepath = "db/sample/#{SecureRandom.hex}.txt"

`touch #{filepath}`

glob_selector = "./db/sample/*.txt"

tmsu_file = TmsuRuby.file glob_selector

tmsu_file.tag_selector "foo"

tmsu_file.tag_selector ["a", "b"]

tmsu_file.tag_selector c: 1, d: 2

# When working with TmsuRuby.file, the untag operation requires the value to
# be specified as well

# This is because TMSU can have duplicate keys

tmsu_file.untag_selector "c=1"

# check results of glob actions
fail_unless { TmsuRuby.file(filepath).tags == { 'foo' => nil, 'a' => nil, 'b' => nil, 'd' => "2" } }

# scoped search
# not working yet
fail_unless { TmsuRuby.file(glob_selector).paths_query("foo").include? File.expand_path filepath }

# global search
# fail_unless { TmsuRuby.file.files("foo").include? File.expand_path filepath }


at_exit do
  `rm -rf db/sample`
  `rm -rf db/*`
end
