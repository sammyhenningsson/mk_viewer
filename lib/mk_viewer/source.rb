# frozen_string_literal: true

require "digest"
require "fileutils"
require "net/http"
require "openssl"

module MkViewer
  # Reads a keymap or labels file from a local path or an http(s) URL. GitHub
  # "blob" page links are read from raw.githubusercontent.com instead. A fetched
  # file is kept for a few minutes, so a scan and the session it starts share one
  # download, and saved to disk, so it still loads while offline.
  module Source
    CACHE_DIR = File.join(ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache")), "mk_viewer/remote")
    FRESH = 300 # seconds a download is reused before fetching again
    REDIRECTS = 3

    FetchError = Class.new(Error)

    @fetched = {}
    @lock = Mutex.new

    module_function

    def remote?(location) = location.to_s.strip.match?(%r{\Ahttps?://}i)

    # The form to store: URLs as given, paths made absolute.
    def expand(location) = remote?(location) ? location.strip : File.expand_path(location.to_s.strip)

    def read(location)
      remote?(location) ? fetch(location.strip) : File.read(File.expand_path(location))
    end

    # The file's text, or nil if there's no such file or it can't be fetched.
    def read_optional(location)
      read(location)
    rescue SystemCallError, FetchError
      nil
    end

    # https://github.com/OWNER/REPO/blob/REF/PATH → https://raw.githubusercontent.com/OWNER/REPO/REF/PATH
    def raw_url(url)
      match = url.match(%r{\Ahttps?://(?:www\.)?github\.com/([^/]+)/([^/]+)/(?:blob|raw)/(.+?)(?:[?#].*)?\z}i)
      match ? "https://raw.githubusercontent.com/#{match[1]}/#{match[2]}/#{match[3]}" : url
    end

    def fetch(url)
      @lock.synchronize do
        time, body = @fetched[url]
        return body if time && now - time < FRESH
      end
      body = download(raw_url(url))
      @lock.synchronize { @fetched[url] = [now, body] }
      save(url, body)
      body
    rescue FetchError, SystemCallError, IOError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      cached = cache_path(url)
      return File.read(cached) if File.exist?(cached)

      raise e.is_a?(FetchError) ? e : FetchError.new("Couldn't fetch #{url}: #{e.message}")
    end

    def download(url, redirects = REDIRECTS)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
      case response
      when Net::HTTPSuccess then response.body.force_encoding(Encoding::UTF_8)
      when Net::HTTPRedirection
        raise FetchError, "Too many redirects fetching #{url}" if redirects.zero?

        download(URI.join(url, response["location"]).to_s, redirects - 1)
      else raise FetchError, "#{url} returned HTTP #{response.code}"
      end
    end

    def save(url, body)
      FileUtils.mkdir_p(CACHE_DIR)
      temporary = "#{cache_path(url)}.tmp"
      File.write(temporary, body)
      File.rename(temporary, cache_path(url))
    rescue SystemCallError
      nil # still usable, just not offline
    end

    def cache_path(url) = File.join(CACHE_DIR, Digest::SHA256.hexdigest(url))

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # For tests.
    def forget = @lock.synchronize { @fetched.clear }
  end
end
