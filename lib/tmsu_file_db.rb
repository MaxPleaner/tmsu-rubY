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
    "#{Config[:root_path] || "."}/*"
  end

  def self.configure(root_path:)
    Config[:root_path] = root_path || "./db".tap do |path|
      `mkdir #{path}`
    end
  end

  def self.validate(attribute=nil, &blk)
    if attribute
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

  def self.query string
    TmsuFile.new(query_glob).paths_query(query)
  end

  def self.update_all opts={}
    Dir.glob(query_glob).each { |path| new(path).update(opts) }
  end

  def self.destroy_all opts={}
    Dir.glob(query_glob).each { |path| `rm #{path}` }
  end

  attr_reader :attributes, :errors, :path

  def initialize(attrs={})
    attrs = attrs.with_indifferent_access
    @path = build_id(attrs.delete :id)
    @attributes = attrs
    @persisted = File.exists? @path
    @errors = []
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

  def method_missing(sym, *arguments, &blk)
    if attributes.keys.include? sym
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
    tag attributes
    self
  end

  def update attrs={}
    attrs.each_key { |k| self[k] = attrs[k] }
    save
    self
  end

  def destroy
    `rm #{path}`
    self
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
    puts system "mkdir #{vfs_path}"
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
    ensure_persisted
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
    attributes.delete
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

  def self.model(path=nil)
    record = TmsuModel.new id: path
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
