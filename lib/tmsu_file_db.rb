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
    Config[:root_path] || "./db/#{SecureRandom.urlsafe_base64}"
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
      opts.join " "
    when Hash
      opts.map { |k,v| "#{k}={v}" }.join(" ")
    end
  end

  def self.find_by opts
    where(opts).first
  end

  def self.where opts={}
    query opts_to_query opts
  end

  def self.from_file(path)
    new(TmsuFile.new(path).tags) { path }
  end

  def self.all
    Dir.glob(query_glob).map &method(:from_path)
  end

  def self.query string
    TmsuFile.new(query_glob).paths_query(query).map &method(:from_path)
  end

  def self.update_all opts={}
    Dir.glob(query_glob).each do |path|
      errors = new(path) { path }.tap { |inst| inst.update(opts) }.errors
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
    @path = blk ? blk.call : build_id(attrs.delete :id)
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

  def build_id(given=nil)
    rand_id = given || SecureRandom.urlsafe_base64
    prefix = "#{self.class::Config[:root_path]}"
    if prefix
      "#{prefix}/#{rand_id}"
    else
      "#{rand_id}"
    end
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
    return false unless valid?
    tag attributes
    @persisted = true
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
    `rm #{path}`
    @persisted = false
    self
  end

  def delete(attr)
    untag(attr)
    attributes.delete attr
    attr
  end

end

module SystemPatch
  refine Object do
    def system string
      `#{string}`.tap &method(:puts)
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
    puts system "tmsu init"
    puts "making vfs_path #{vfs_path}"
    puts system "mkdir -p #{vfs_path}"
    puts "mounting vfs path"
    puts system "tmsu mount #{vfs_path}"
  end
  def vfs_path
    "/home/max/tmsu_vfs"
  end
end

module TmsuFileAPI

  using SystemPatch

  def tags
    system("tmsu tags #{path}").split(" ")[1..-1].reduce({}) do |res, tag|
      key, val = tag.split("=")
      res.tap { res[key] = val }
    end
  end

  def paths_query(query)
    query_root = "#{vfs_path}/queries/#{query}"
    system("ls #{query_root}").split("\n").map do |filename|
      system("readlink #{query_root}/#{filename}").chomp
    end
  end

  def untag tag_list
    `touch #{path}` unless persisted?
    system "tmsu untag #{path} #{tag_list}"
    tags
  end

  def tag tag_obj
    `touch #{path}` unless persisted?
    system "tmsu tag #{path} #{build_tag_arg tag_obj}"
    tags
  end

  def build_tag_arg obj
    case obj
    when String
      obj
    when Array
      obj.join " "
    when Hash
      obj.map {|k,v| "#{k}=#{v}" }.join " "
    else
      obj
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
    system "tmsu tag --tags '#{build_tag_arg tag_obj}' #{path}"
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
