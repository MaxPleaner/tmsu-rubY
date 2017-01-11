This is an ORM similar to ActiveRecord, but uses the filesystem instead.

It uses TMSU which is a filesystem tagging system.

Usage:

**Install the gem**

```sh
gem install tmsu_file_db
```

**Define a model**

```rb
require 'tmsu_file_db'

class User < TmsuModel

  # this configure block is optional
  # it defaults to a randomly named dir in ./db
  configure root_path: "./db/users"

  # Validations must return an array
  validate do |record|
    record.name.nil? ? ["name can't be blank"] : []
  end

  # Specific attributes can be validated as well
  validate(:email) do |email, record|
    email&.include?("@") ? ["email isn't valid"] : []
  end

end
```

**Create instances**

```rb
# create, update, and delete
u = User.new name: "max"
u.valid? # => false
u.errors # => ["email isn't valid"]
u.save # => false
u.[:email] = "maxpleaner@gmail.com"
u.valid? # => true
u.save # => true
u.update(email: "max.pleaner@gmail.com") # => true
u.update(email: "") # => false

# There are getter methods for convenience
# Setters need to use []=
u.name # => "max"
u["name"] # => "max"
u[:name] # => "max"
u[:name] # => "max p."

# All these getter/setters are working on 'attributes' under the hood.
u.attributes[:name] # => "max p."

# each record is assigned a filesystem path
u.path

# creating a new record will create a new file in the root_path
# but will not add anything to the file unless .write is called
u.write "hello"

# The content of the file is not part of the "attributes" i.e. name and email
# Those are stored using TMSU tags
u.tags # => { email: "max.pleaner@gmail.com", name: "max" }
u.tags == u.attributes # true

# Attributes can be deleted
u.delete :name
u.tags # => { email: "max.pleaner@gmail.com" }

# Records can be deleted (this will destroy the file)
u.destroy

```


**Use class-level query methods**

_Note that this does not use Arel or any of that jazz. So chaining queries or using joins will not work._

_Note also that there is no `id` on models, only `path`, which is an absolute path._

```rb
User.where(name: "max p.")[0].name == "max p." # => true
User.find_by(name: "max p.").name == "max p." # => true
User.update_all(name: "max") # => true

# You can make arbitrary queries using TMSU syntax
# e.g. select all users with email set that are not named melvin
User.query("name != 'melvin' and email")[0].name == "max" # => true
```

Although there's an index method (`all`), there's no typical auto-incrementing ids stored in TMSU. So to load a single, arbitrary record without tags, its file path is used:

```rb
  u.path # => "./db/users/23uj8d9j328dj"
  User.from_file(u.path).name == "max p."
```

**Use TmsuRuby.file**

An alternative to `TmsuModel` is to use `TmsuRuby.file` instead. This does _not_ handle creation / deletion of files. It should only be used with files that already exist.

Note that these methods are technically available on `TmsuModel` instances as well. But this shouldn't be done, because it will cause the in-memory attributes to be out of sync. Also, some operations like `tag` will error if called on unsaved records.

```rb
file_path = './my_pic.jpg' # this should already exist

tmsu_file = TmsuRuby.file file_path
tmsu_file.tags # => {}

tmsu_file.tag "foo" # .tag can be passed a string
tmsu_file.tags # => { foo: nil }

tmsu_file.untag "foo"
tmsu_file.tags # => { }

tmsu_file.tag ["foo", "bar"] # .tag can also be passed an array
tmsu_file.tags # => { foo: nil, bar: nil }

tmsu_file.tag(a: 1, b: 2) # .tag can also be passed a hash
tmsu_file.tags # => { foo: nil, bar: nil, a: 1, b: 2 }

# if a tag has a value, it needs to be specified in #untag
# this is only needed for TmsuRuby.file
# The model passes the value automatically.
tmsu_file.untag("a=1")
```

It's also possible to use `TmsuRuby` to work on multiple files instead of just one:

```rb
glob_selector = "./**/*.jpg"

tmsu_file = TmsuRuby.file glob_selector

# there is a special method used to add tags in this case
tmsu_file.tag_selector "foo"
tmsu_file.tag_selector ["a", "b"]
tmsu_file.tag_selector c: 1, d: 2

# Simiarly to untag
tmsu_file.untag_selector "c=1"

# check that the tags were added to files
TmsuRuby.file("./my_pic.jpg").tags
# => { foo: nil, a: nil, b: nil, d: 2 }
```

Using `TmsuRuby.file` you can search by tag as well. All these methods return
an array of absolute paths

```rb

# To perform a scoped search (the same used by .where, .find_by, and .query):
# This is a simple query, but the whole TMSU syntax is available
TmsuRuby.file('.').files("foo")

# The path defaults to '.', so this is the same:
TmsuRuby.file.files("foo")
```

**Test && Examples**

See [automated_tests.rb](./automated_tests.rb), which can double as usage examples. 
