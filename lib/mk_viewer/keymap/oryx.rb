# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"

module MkViewer
  module Keymap
    # Fetches a layout revision from ZSA's Oryx API. Revisions never change once
    # published, so each one is fetched once and then read from a local cache.
    class Oryx
      API = URI("https://oryx.zsa.io/graphql")
      QUERY = <<~GRAPHQL
        query($hashId: String!, $revisionId: String!) {
          layout(hashId: $hashId, revisionId: $revisionId) {
            revision { hashId title layers { position title keys } }
          }
        }
      GRAPHQL

      CACHE_DIR = File.join(ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache")), "mk_viewer")

      SYMBOLS = {
        "SE_AA" => "Å", "SE_ADIA" => "Ä", "SE_OSLH" => "Ö", "SE_ACUT" => "´", "SE_AMPR" => "&", "SE_APOS" => "'",
        "SE_ASTR" => "*", "SE_AT" => "@", "SE_BSLS" => "\\", "SE_CIRC" => "^", "SE_COLN" => ":", "SE_DLR" => "$",
        "SE_DQUO" => "\"", "SE_EQL" => "=", "SE_EURO" => "€", "SE_GRTR" => ">", "SE_GRV" => "`", "SE_LBRC" => "[",
        "SE_LCBR" => "{", "SE_LESS" => "<", "SE_LPRN" => "(", "SE_MINS" => "-", "SE_MU" => "µ", "SE_PIPE" => "|",
        "SE_PLUS" => "+", "SE_PND" => "£", "SE_QUES" => "?", "SE_RBRC" => "]", "SE_RCBR" => "}", "SE_RPRN" => ")",
        "SE_SCLN" => ";", "SE_SLSH" => "/", "SE_UNDS" => "_", "KC_EXLM" => "!", "KC_HASH" => "#", "KC_PERC" => "%",
        "KC_COMMA" => ",", "KC_DOT" => ".", "KC_SPACE" => "␣", "KC_ENTER" => "⏎", "KC_ESCAPE" => "Esc",
        "KC_BSPC" => "⌫", "KC_TAB" => "⇥", "KC_DELETE" => "Del", "KC_INSERT" => "Ins", "KC_PSCR" => "PrtSc",
        "KC_CAPS" => "Caps", "KC_HOME" => "Home", "KC_END" => "End", "KC_PAGE_UP" => "PgUp", "KC_PGDN" => "PgDn",
        "KC_LEFT" => "←", "KC_RIGHT" => "→", "KC_UP" => "↑", "KC_DOWN" => "↓", "KC_CALCULATOR" => "Calc",
        "KC_AUDIO_MUTE" => "Mute", "KC_AUDIO_VOL_UP" => "Vol+", "KC_AUDIO_VOL_DOWN" => "Vol−",
        "KC_MEDIA_NEXT_TRACK" => "⏭", "KC_MEDIA_PREV_TRACK" => "⏮", "KC_MEDIA_PLAY_PAUSE" => "⏯",
        "KC_MEDIA_STOP" => "⏹", "KC_MS_BTN1" => "LClick", "KC_MS_BTN2" => "RClick", "KC_MS_BTN3" => "MClick",
        "KC_MS_UP" => "Move ↑", "KC_MS_DOWN" => "Move ↓", "KC_MS_LEFT" => "Move ←", "KC_MS_RIGHT" => "Move →",
        "KC_MS_WH_UP" => "Scroll ↑", "KC_MS_WH_DOWN" => "Scroll ↓", "KC_MS_WH_LEFT" => "Scroll ←",
        "KC_MS_WH_RIGHT" => "Scroll →", "KC_LEFT_SHIFT" => "Shift", "KC_LEFT_CTRL" => "Ctrl", "KC_LEFT_ALT" => "Alt",
        "KC_LEFT_GUI" => "Super", "KC_RIGHT_ALT" => "AltGr", "KC_RIGHT_CTRL" => "Ctrl", "KC_RIGHT_SHIFT" => "Shift",
        "MEH_T" => "Meh", "CW_TOGG" => "CapsWord", "QK_BOOT" => "Boot", "QK_LLCK" => "Lock", "RGB_MODE_FORWARD" => "RGB»",
        "RGB" => "RGB"
      }.freeze

      MODIFIERS = {
        "leftCtrl" => "Ctrl", "rightCtrl" => "Ctrl", "leftShift" => "⇧", "rightShift" => "⇧",
        "leftAlt" => "Alt", "rightAlt" => "AltGr", "leftGui" => "Super", "rightGui" => "Super"
      }.freeze

      def self.load(serial, layout)
        layout_id, revision = serial.to_s.split("/", 2)
        raise Error, "USB serial #{serial.inspect} doesn't name an Oryx layout" unless layout_id && revision

        new(fetch(layout_id, revision), layout).map
      end

      def self.fetch(layout_id, revision)
        unless [layout_id, revision].all? { |part| part.match?(/\A[A-Za-z0-9]+\z/) }
          raise Error, "invalid Oryx layout #{layout_id}/#{revision}"
        end

        path = File.join(CACHE_DIR, "oryx-#{layout_id}-#{revision}.json")
        return JSON.parse(File.read(path)) if File.exist?(path)

        response = Net::HTTP.post(API, { query: QUERY, variables: { hashId: layout_id, revisionId: revision } }.to_json,
                                  "Content-Type" => "application/json")
        raise Error, "Oryx returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body).dig("data", "layout", "revision")
        raise Error, "Oryx has no layout #{layout_id}/#{revision}" unless data

        FileUtils.mkdir_p(CACHE_DIR)
        File.write(path, JSON.generate(data))
        data
      end

      def initialize(revision, layout)
        @layers = revision.fetch("layers").sort_by { |l| l["position"] }
        @order = layout.keys.map(&:oryx)
      end

      def map
        Map.new(@layers.map do |layer|
          Layer.new(layer["title"].to_s, @order.map { |index| build(layer["keys"].fetch(index)) })
        end)
      end

      private

      def build(key)
        tap = key["tap"]
        hold = key["hold"]
        custom = key["customLabel"] || key["emoji"]
        return Key.new(legend: custom, hold: hold && action(hold)) if custom

        transparent = (tap.nil? || tap["code"] == "KC_TRANSPARENT") && !tap&.dig("macro") && hold.nil?
        return TRANSPARENT if transparent
        return Key.new(legend: "Macro", hold: hold && action(hold)) if tap&.dig("macro")

        Key.new(legend: tap ? action(tap) : "", hold: hold && action(hold))
      end

      def action(part)
        code = part["code"].to_s
        return "" if %w[KC_NO KC_TRANSPARENT].include?(code)

        name = @layers.find { |l| l["position"] == part["layer"] }&.dig("title") || "Layer #{part['layer']}"
        case code
        when "MO" then return name
        when "TO" then return "→ #{name}"
        when "TG" then return "⇄ #{name}"
        when "OSL" then return "1× #{name}"
        end
        prefix = (part["modifiers"] || {}).select { |_, on| on }.keys.map { |m| "#{MODIFIERS.fetch(m, m)} " }.join
        prefix + SYMBOLS.fetch(code) { code.sub(/\A(KC|SE)_/, "").sub(/\A(\d)\z/, '\1') }
      end
    end
  end
end
