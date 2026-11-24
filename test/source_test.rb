# frozen_string_literal: true

require_relative "test_helper"
require "socket"
require "tmpdir"

class SourceTest < Minitest::Test
  Source = MkViewer::Source

  def setup
    @dir = Dir.mktmpdir
    @cache = Source::CACHE_DIR
    Source.send(:remove_const, :CACHE_DIR)
    Source.const_set(:CACHE_DIR, File.join(@dir, "cache"))
    Source.forget
    @requests = []
    @responses = {}
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  def teardown
    @thread.kill
    @server.close
    Source.send(:remove_const, :CACHE_DIR)
    Source.const_set(:CACHE_DIR, @cache)
    Source.forget
    FileUtils.remove_entry(@dir)
  end

  def url(path) = "http://127.0.0.1:#{@server.addr[1]}#{path}"

  def serve(client)
    path = client.gets.split[1]
    nil while client.gets != "\r\n"
    @requests << path
    status, headers, body = @responses.fetch(path, ["404 Not Found", {}, ""])
    client.write("HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n")
    headers.each { |name, value| client.write("#{name}: #{value}\r\n") }
    client.write("\r\n#{body}")
    client.close
  end

  def test_github_blob_links_read_the_raw_file
    assert_equal "https://raw.githubusercontent.com/sammyhenningsson/kibard/main/config/kibard.keymap",
                 Source.raw_url("https://github.com/sammyhenningsson/kibard/blob/main/config/kibard.keymap")
    assert_equal "https://raw.githubusercontent.com/o/r/v1.2/a/b.yaml", Source.raw_url("https://github.com/o/r/raw/v1.2/a/b.yaml?plain=1")
    assert_equal "https://example.com/x.keymap", Source.raw_url("https://example.com/x.keymap")
  end

  def test_expand_keeps_urls_and_expands_paths
    assert_equal "https://example.com/x.keymap", Source.expand(" https://example.com/x.keymap ")
    assert_equal File.expand_path("~/x.keymap"), Source.expand("~/x.keymap")
  end

  def test_loads_a_remote_keymap_with_remote_labels
    @responses["/k.keymap"] = ["200 OK", {}, Fixtures::KEYMAP]
    @responses["/l.yaml"] = ["200 OK", {}, Fixtures::LABELS]
    map = MkViewer::Keymap::Zmk.load(url("/k.keymap"), labels: url("/l.yaml"))
    assert_equal %w[Base Nav], map.layers.map(&:name)
    assert_equal "@", map.layers[1].keys[1].legend
  end

  def test_follows_redirects
    @responses["/old"] = ["301 Moved Permanently", { "Location" => "/new" }, ""]
    @responses["/new"] = ["200 OK", {}, "hello"]
    assert_equal "hello", Source.read(url("/old"))
  end

  def test_reuses_a_recent_download
    @responses["/k"] = ["200 OK", {}, "one"]
    2.times { assert_equal "one", Source.read(url("/k")) }
    assert_equal ["/k"], @requests
  end

  def test_falls_back_to_the_saved_copy
    @responses["/k"] = ["200 OK", {}, "saved"]
    Source.read(url("/k"))
    Source.forget
    @responses["/k"] = ["500 Internal Server Error", {}, ""]
    assert_equal "saved", Source.read(url("/k"))
  end

  def test_missing_remote_file
    error = assert_raises(Source::FetchError) { Source.read(url("/gone")) }
    assert_match "HTTP 404", error.message
    assert_nil Source.read_optional(url("/gone"))
  end

  def test_store_keeps_a_url_as_given
    store = MkViewer::KeyboardStore.new(File.join(@dir, "store.yml"))
    store.assign("Corne", "https://github.com/o/r/blob/main/corne.keymap")
    assert_equal "https://github.com/o/r/blob/main/corne.keymap", store.keymap_for("Corne")
  end

  def test_chosen_remote_keymap_builds_a_profile
    @responses["/corne.keymap"] = ["200 OK", {}, Fixtures::KEYMAP]
    config = MkViewer::Config.new(File.join(MkViewer::ROOT, "config/keyboards.yml"),
                                  store: MkViewer::KeyboardStore.new(File.join(@dir, "store.yml")))
    config.store.assign("Corne", url("/corne.keymap"))
    device = MkViewer::HidDevice.new(path: "/dev/x", name: "Corne", bus: 5, vendor_id: 0x1D50, product_id: 0x615E,
                                     uniq: "", descriptor: "\x05\x01\x09\x06\xA1\x01\x85\x01".b)
    profile = config.profile_for(device)
    assert_equal 8, profile.layout.keys.size
    assert_equal 2, profile.load_keymap(device).layers.size
  end
end
