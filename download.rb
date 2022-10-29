#!/usr/bin/env ruby
require 'rubygems'
require 'nokogiri'
require 'json'
require 'open-uri'
require 'logger'
require 'open3'

VERSION = '0.2.0'

@options = {
  dir: ENV['PWD'],
  log_file: STDOUT,
  log_level: Logger::INFO,
  ffmpeg_log_level: 'panic'
}

# Set up logging
@log = Logger.new(@options[:log_file])
@log.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.strftime("%Y-%m-%dT%H:%M:%S")
  "[#{date_format}] #{severity.rjust(5)}: #{msg}\n"
end
@log.level = @options[:log_level]

def convert(video_file, audio_file, output)
  if File.exist? output
    @log.error("File #{output} already exists!")
    raise 'Conversion error'
  end

  # Debug info for FFmpeg
  args = ['-loglevel', @options[:ffmpeg_log_level], '-i', "#{video_file}", '-i', "#{audio_file}",
    '-c', 'copy', '-map', '0:v:0', '-map', '1:a:0', "#{output}"]
  @log.debug("FFmpeg args: #{args}")

  # A stupid, but necessary way to call FFmpeg: Kernel.system causes FFmpeg to ignore -loglevel and
  # leaks something, breaking the shell - arguments lose first character, breaking EVERYTHING.
  stdout, stderr, status = Open3.capture3('ffmpeg', '-hide_banner', '-loglevel',
    @options[:ffmpeg_log_level], '-i', "#{video_file}", '-i', "#{audio_file}", '-c', 'copy',
    '-map', '0:v:0', '-map', '1:a:0', "#{output}")

  if status.exitstatus > 0
    @log.error('FFmpeg: ' +stderr)
    raise 'Conversion error'
  end
end

def download(url, path, size)
  # Downloads URL to a file defined by path and checks size
  if File.exist? path 
    if File.size(path) == size
      @log.warn("File #{path} already exists and size matches, keeping it.")
      return
    else
      @log.error("File #{path} already exists, but has different size!")
      raise 'Download error'
    end
  end

  URI.open(url) do |data|
    File.open(path, 'wb') do |file|
      file.write(data.read)
      @log.info("Downloaded #{url} to #{path}, size: #{file.size}.")

      unless file.size == size
        @log.error("Size mismatch! #{path} is supposed to be #{size} bytes, but is #{file.size}. Aborting.")
        raise 'Download error'
      end
    end
  end
end

def get_json(url)
  # Get embedded JSON string from a page and parse it
  page = Nokogiri::HTML(URI.open(url))
  json = JSON.parse(page.css('script#coubPageCoubJson').text)
  json
end

def get_audio(json)
  # Takes the Coub JSON and downloads highest quality audio stream
  # and returns file path
  audio = {}
  %w{higher high med}.each do |qual|
    if json["file_versions"]['html5']['audio'].keys.include? qual
      audio = {
        url: json["file_versions"]['html5']['audio'][qual]['url'],
        size: json["file_versions"]['html5']['audio'][qual]['size']
      }
      @log.debug "Audio URL: #{audio['url']} (size: #{audio['size']})"
      break
    end
  end

  audio_file = "#{@work_dir}/audio.#{audio[:url].split('.')[-1]}"
  download(audio[:url], audio_file, audio[:size])
  audio_file
end

def get_video(json)
  # Takes the Coub JSON and downloads highest quality video stream
  # and returns file path
  video = {}
  %w{higher high med}.each do |qual|
    if json["file_versions"]['html5']['video'].keys.include? qual
      video = {
        url: json["file_versions"]['html5']['video'][qual]['url'],
        size: json["file_versions"]['html5']['video'][qual]['size']
      }
      @log.debug "Video URL: #{video['url']} (size: #{video['size']})"
      break
    end
  end

  video_file = "#{@work_dir}/video.#{video[:url].split('.')[-1]}"
  download(video[:url], video_file, video[:size])
  video_file
end

def parse_args(opts)
  # CLI args parser
  opts.each do |opt|
    case opt
      when '-d', '--dir'
        @options[:dir] = opts[opts.index(opt) +1]
      when '-l', '--log'
        @options[:log_file] = opts[opts.index(opt) +1]
        @log = Logger.new(@options[:log_file])
      when '-h', '-?', '--help'
        show_help
      when '-q', '--quiet'
        @options[:log_level] = Logger::WARN
        @options[:ffmpeg_log_level] = 'quiet'
        @log.level = Logger::WARN
      when '-u', '--url'
        @options[:url] = opts[opts.index(opt) +1]
      when '-v', '--verbose'
        @options[:log_level] = Logger::DEBUG
        @options[:ffmpeg_log_level] = 'fatal'
        @log.level = Logger::DEBUG
      when '-V', '--version'
        puts "Coub downloader version #{VERSION}."
        exit(0)
    end
  end

  # Sanity checks
  if @options[:url].nil?
    @log.error('No --url was given!')
    raise 'Argument error'

  elsif not @options[:url].match('^https?://coub.com/view/[A-Za-z0-9]+$')
    @log.error("Bad --url \"#{@options[:url]}\"! Must match https://coub.com/view/[A-Za-z0-9]+")
    raise 'Argument error'
  end
end

def show_help
  # Tool usage
  puts <<HELP
  Usage: #{$PROGRAM_NAME} [-q|-v] [-d dir] -u URL
    -d dir - save everything to this directory.
    -h     - his message.
    -l log - log everything to log file.
    -q     - quiet, sets verbosity to WARN.
    -u URL - Coub URL.
    -v     - verbose, sets verbosity to DEBUG.
    -V     - show version and exit.
HELP

  exit(1)
end

parse_args(ARGV)

# By default download to ./$permalink/
@work_dir = "#{@options[:dir]}/#{@options[:url].split('/')[-1]}"
json_path = "#{@work_dir}/coub.json"

# Reuse previously saved JSON, if it exists
if File.exist? json_path
  @log.info("Loading JSON from local file: #{json_path}")
  File.open(json_path, 'r') do |file|
    @coub = JSON.load file
  end
else
  @log.info("Getting JSON from #{@options[:url]}")
  @coub = get_json(@options[:url])
end

# Fail if coub is hidden/private/banned
unless @coub['code'].nil?
  if @coub['code'] >= 400
    @log.debug(JSON.pretty_generate(@coub))
    raise "Runtime error: #{@coub['error']} (HTTP #{@coub['code']})."
  end
end

unless File.directory? @work_dir
  @log.info("Creating work directory #{@work_dir}.")
  Dir.mkdir(@work_dir)
end

unless File.exist? json_path
  File.open(json_path, 'w') do |file|
    @log.info('Saving JSON...')
    file.write(JSON.pretty_generate(@coub))
  end
end

@log.info('Getting video...')
video = get_video(@coub)

@log.info('Getting audio...')
audio = get_audio(@coub)

convert(video, audio, "#{@work_dir}/coub.mp4")
puts "Downloaded Coub #{@options[:url]} to #{@work_dir}."
