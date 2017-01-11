require 'securerandom'
require 'gemmy'

module TmsuFileDb
  def self.start
    ::TmsuRuby.start
  end
end

class TmsuModel
  Config = { root_path: "." }
  Validations = Hash.new { |h,k| h[k] = [] }
  Callbacks = {}


  def self.query_glob
    "#{root_path}/*"
  end

  def self.root_path
    Config[:root_path] || generate_path(within: "./db")
  end

  def self.generate_path(within: '.')
    loop do
      path = "#{within}/#{SecureRandom.hex}"
      break path unless File.exists?(path)
    end
  end

  def self.configure(root_path:)
    Config[:root_path] = root_path || "./db".tap do |path|
    `mkdir -p #{path}`
    end
  end


  def self.validate(attribute=:generic, &blk)
    if attribute == :generic
      Validations[:generic] << blk
    else
      Validations[attribute] << blk
    end
  end

  def self.add_callback name, &blk
    Callbacks[name] = blk
  end

  def self.opts_to_query opts
    case opts
    when Array
      opts.map { |opt| escape_whitespace opt }.join " "
    when Hash
      opts.map do |k,v|
        "#{escape_whitespace k}=#{escape_whitespace v}"
      end.join(" ")
    end
  end

  def self.create(attrs)
    new(attrs).tap(&:save)
  end

  def self.find_by opts
    where(opts).first
  end

  def self.where opts={}
    query opts_to_query opts
  end

  def self.escape_whitespace(string)
    string.to_s.gsub(/(?<!\\)\s/, '\ ')
  end

  def self.escape_hash_whitespace(hash)
    hash.reduce({}) do |result, (k,v)|
      result[escape_whitespace(k)] = escape_whitespace v
      result
    end
  end

  def self.from_file(path)
    new(escape_hash_whitespace TmsuRuby.file(path).tags) { path }
  end

  def self.all
    Dir.glob(query_glob).map &method(:from_file)
  end

  def self.query string
    TmsuRuby.file(query_glob).paths_query(string).map &method(:from_file)
  end

  def self.update_all opts={}
    Dir.glob(query_glob).each do |path|
      errors = from_file(path).tap { |inst| inst.update(opts) }.errors
      unless errors.empty?
        raise(
          ArgumentError, "couldn't update all. Path #{path} caused errors: #{errors.join(", ")}"
        )
      end
    end
    true
  end

  def self.destroy_all opts={}
    Dir.glob(query_glob).tap { |list| list.each { |path| `rm #{path}` } }
  end

  attr_reader :attributes, :errors, :path

  def initialize(attrs={}, &blk)
    attrs = attrs.with_indifferent_access
    # normally for re-initializing a record from a file, .from_file is used.
    # but there is another way, which is to pass a block to initialize
    # which returns a path string.
    # Example: TmsuModel.new { "file.txt" }.path # => "file.txt"
    @path = blk ? blk.call : build_path
    @attributes = attrs
    @persisted = File.exists? @path
    @errors = []
  end

  def ensure_root_path
    unless @root_dir_created
      `mkdir -p #{self.class.root_path}`
      @root_dir_created = true
    end
  end

  def build_path
    self.class.generate_path(
      within: self.class::Config[:root_path] || "."
    )
  end

  def []=(k,v)
    attributes[k] = v
  end

  def [](k)
    attributes[k]
  end

  # Forwards method missing to getter, if possible
  # To respect indifferent access of attributes,
  # uses has_key? instead of keys.include?
  def method_missing(sym, *arguments, &blk)
    super unless defined?(attributes) && attributes.is_a?(Hash)
    if attributes.has_key? sym
      attributes[sym]
    else
      super
    end
  end

  def write(text, append: false)
    return unless text
    File.open(path, "w#{"a" if append}") { |f| f.write text }
    self
  end

  def append(text)
    write(text, append: true)
    self
  end

  def valid?
    @errors = []
    Validations.each do |type, procs|
      procs.each do |proc|
        some_errors = if type.eql?(:generic)
           proc.call self
        else
          proc.call self[type], self
        end
        raise(
          ArgumentError, "validations must return arrays"
        ) unless some_errors.is_a?(Array)
        @errors.concat some_errors
      end
    end
    @errors.empty?
  end

  def persisted?
    !!@persisted
  end

  def ensure_persisted
    `touch #{path}` unless persisted?
  end

  def save
    ensure_persisted
    ensure_root_path
    original_attributes = tags
    attributes.each do |k,v|
      if !v.nil? && !(original_attributes[k] == v)
        untag "#{k}=#{original_attributes[k]}"
      end
    end
    return false unless valid?
    tag attributes
    @persisted = true
    @attributes = tags.with_indifferent_access
    true
  end

  def update attrs={}
    original_attrs = attributes.clone
    attrs.each_key { |k| self[k] = attrs[k] }
    unless valid?
      # rollback attribute change
      self.attributes.clear
      original_attrs.each { |k,v| self[k] = v }
      return false
    end
    save
    true
  end

  def destroy
    `tmsu-fs-rm #{path}`
    `rm #{path}`
    @persisted = false
    self
  end

  def delete(attr)
    if attributes[attr].nil?
      untag(attr)
    else
      val = attributes[attr]
      untag("#{attr}=#{val}")
    end
    attributes.delete attr
  end

end

# This patch doesn't do anything unless ENV["DEBUG"] is set
module SystemPatch
  refine Object do
    def system string
      if ENV["DEBUG"]
        return `#{string}`.tap &method(:puts)
      else
        return `#{string}`
      end
    end
  end
end

module TmsuRubyInitializer
  using SystemPatch
  def start
    init_tmsu
  end
  def init_tmsu
    puts "initializing tmsu"
    system "tmsu init"
    puts "making vfs_path #{vfs_path}"
    system "mkdir -p #{vfs_path}"
    puts "mounting vfs path"
    system "tmsu mount #{vfs_path}"
  end
  def vfs_path
    "/home/max/tmsu_vfs"
  end
end

module TmsuFileAPI

  using SystemPatch

  def persisted?
    return super if defined?(super)
    File.exists? path
  end

  def tags
    return {} unless persisted?
    delimiter = /(?<!\\)\s/
    cmd_res = system("tmsu tags #{path}")
    cmd_res.chomp.split(delimiter)[1..-1].reduce({}) do |res, tag|
      key, val = tag.split("=").map do |str|
        str
      end
      res.tap { res[key] = val }
    end
  end

  def require_persisted
    unless persisted?
      raise(RuntimeError, "called tags on unsaved record. path: #{path}")
    end
  end

  def paths_query(query)
    query_root = %{#{vfs_path}/queries/"#{query}"}
    system("ls #{query_root}").split("\n").map do |filename|
      system("readlink #{query_root}/#{filename}").chomp
    end
  end

  def untag tag_list
    `touch #{path}`
    system "tmsu untag #{path} #{tag_list}"
    tags
  end

  def tag tag_obj
    `touch #{path}`
    system %{tmsu tag #{path} #{build_tag_arg tag_obj}}
    tags
  end

  def build_tag_arg obj
    case obj
    when String
      %{"#{obj}"}
    when Array
      obj.map { |x| %{"#{x}"} }.join " "
    when Hash
      obj.map do |k,v|
        %{"#{k}=#{v}"}
      end.join " "
    else
      %{"#{obj}"}
    end
  end

  def tag_selector(tag_obj)
    system "tmsu tag --tags '#{build_tag_arg tag_obj}' #{path}"
    files tag_obj
  end

  def untag_selector(tag_obj)
    tag_arg = case tag_obj
    when String
      tag_obj
    when Array
      tag_obj.join(" ")
    end
    system "tmsu untag --tags '#{build_tag_arg tag_obj}' #{path}"
    files tag_obj
  end

  def merge_tag(source, dest)
    source_files = files source
    dest_files = files dest
    raise(ArgumentError, "#{source} tag not found") if source_files.empty?
    raise(ArgumentError, "#{dest} tag not found") if dest_files.empty?
    system("tmsu merge #{source} #{dest}")
    source_files
  end

  def files(tag_obj)
    system("tmsu files #{build_tag_arg tag_obj }").split("\n")
  end

end

class TmsuRuby
  extend TmsuRubyInitializer

  def self.file(path=nil)
    TmsuRuby::TmsuFile.new path, vfs_path
  end

  class TmsuFile
    include TmsuFileAPI
    attr_reader :path, :vfs_path
    def initialize path, vfs_path
      @path = path
      @vfs_path = vfs_path
    end
  end
end

TmsuModel.include TmsuFileAPI
