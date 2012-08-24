#!/usr/bin/ruby
require "rubygems"
require "bundler/setup"

# require your gems as usual
require "rb-inotify"
require "net/ftp"
require "timeout"

class QueueItem
  TYPE_DIR = 'dir'
  TYPE_FILE = 'file'
  
  def initialize(qtype, name)
    @qtype = qtype
    @name = name
  end

  def name
    @name
  end
end

class Uploader

  def initialize
    @queue = []
    @queue_run = false
    @config = YAML.load_file('sync.yml')
    notifier = INotify::Notifier.new
    notifier.watch(@config['dir'], :moved_to, :create, :modify, :recursive) do |event|
      @queue.push QueueItem.new(QueueItem::TYPE_FILE, event.absolute_name)
      unless @queue_run
        puts 'Filesystem change detected'
        a = Thread.new { run_queue }
      end
    end
    connect_ftp
    notifier.run
  end

  def connect_ftp
    begin
      @ftp = Net::FTP::new(@config['ftp']['host'])
      @ftp.login @config['ftp']['user'], @config['ftp']['pass']
      @ftp.passive = true
      @ftp.chdir @config['ftp']['path']
      puts "Connection established"
      return @ftp
    rescue Net::FTPError
      puts "FTP connection failed due to ftp service stop"
    rescue Timeout::Error
      puts "FTP connection busy error"
    rescue Exception => e
      puts "FTP connection failed"
    end
  end

  def merge_queue
    seen_keys = {}
    @queue.reject! do |item|
      if !item.name.nil? && seen_keys[item.name] 
        true 
      else 
        seen_keys[item.name] = true
        false
      end
    end
  end

  def run_queue
    @queue_run = true
    connect_ftp if @ftp.closed?
    sleep 0.2 # avoid duplicates
    merge_queue
    # upload here!
    @queue.reject! do |item|
      # TODO: directory creation
      filename = item.name.gsub(/^..\//, '')
      @ftp.putbinaryfile item.name, filename
      puts 'uploaded ' + filename
      true
    end
    @queue_run = false
  end

end

u = Uploader.new