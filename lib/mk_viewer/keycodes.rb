# frozen_string_literal: true

module MkViewer
  # ZMK key names: HID usages, modifier bits and display labels.
  module Keycodes
    USAGES = {}.tap do |t|
      ("A".."Z").each_with_index { |c, i| t[c] = 4 + i }
      (1..9).each { |n| t["N#{n}"] = 29 + n }
      t["N0"] = 39
      (1..12).each { |n| t["F#{n}"] = 57 + n }
      (13..24).each { |n| t["F#{n}"] = 91 + n }
      {
        40 => %w[RET RETURN ENTER], 41 => %w[ESC ESCAPE], 42 => %w[BSPC BACKSPACE], 43 => %w[TAB],
        44 => %w[SPACE], 45 => %w[MINUS], 46 => %w[EQUAL], 47 => %w[LEFT_BRACKET LBKT],
        48 => %w[RIGHT_BRACKET RBKT], 49 => %w[BACKSLASH BSLH], 50 => %w[NUHS NON_US_HASH],
        51 => %w[SEMI SEMICOLON], 52 => %w[APOS SQT SINGLE_QUOTE], 53 => %w[GRAV GRAVE],
        54 => %w[COMMA], 55 => %w[DOT PERIOD], 56 => %w[FSLH SLASH], 57 => %w[CAPS CAPSLOCK],
        70 => %w[PSCRN PRINTSCREEN], 71 => %w[SLCK SCROLLLOCK], 72 => %w[PAUSE_BREAK],
        73 => %w[INS INSERT], 74 => %w[HOME], 75 => %w[PG_UP PAGE_UP], 76 => %w[DEL DELETE],
        77 => %w[END], 78 => %w[PG_DN PAGE_DOWN], 79 => %w[RIGHT RIGHT_ARROW],
        80 => %w[LEFT LEFT_ARROW], 81 => %w[DOWN DOWN_ARROW], 82 => %w[UP UP_ARROW],
        100 => %w[NUBS NON_US_BACKSLASH]
      }.each { |usage, names| names.each { |n| t[n] = usage } }
    end.freeze

    MOD_BITS = {
      "LCTRL" => 0x01, "LCTL" => 0x01, "LSHIFT" => 0x02, "LSHFT" => 0x02, "LALT" => 0x04, "LGUI" => 0x08,
      "RCTRL" => 0x10, "RCTL" => 0x10, "RSHIFT" => 0x20, "RSHFT" => 0x20, "RALT" => 0x40, "RGUI" => 0x80
    }.freeze

    MOD_WRAPPERS = {
      "LC" => 0x01, "LS" => 0x02, "LA" => 0x04, "LG" => 0x08,
      "RC" => 0x10, "RS" => 0x20, "RA" => 0x40, "RG" => 0x80
    }.freeze

    LABELS = {
      "RET" => "⏎", "RETURN" => "⏎", "ENTER" => "⏎", "ESC" => "Esc", "ESCAPE" => "Esc",
      "BSPC" => "⌫", "BACKSPACE" => "⌫", "TAB" => "⇥", "SPACE" => "␣", "DEL" => "Del", "DELETE" => "Del",
      "INS" => "Ins", "INSERT" => "Ins", "PSCRN" => "PrtSc", "CAPS" => "Caps", "HOME" => "Home",
      "END" => "End", "PG_UP" => "PgUp", "PG_DN" => "PgDn", "LEFT" => "←", "RIGHT" => "→", "UP" => "↑",
      "DOWN" => "↓", "COMMA" => ",", "DOT" => ".", "K_VOL_UP" => "Vol+", "K_VOL_DN" => "Vol−",
      "K_MUTE" => "Mute", "K_PP" => "⏯", "K_NEXT" => "⏭", "K_PREV" => "⏮", "K_STOP2" => "⏹",
      "C_AL_CALC" => "Calc", "LCTRL" => "Ctrl", "RCTRL" => "Ctrl", "LCTL" => "Ctrl", "RCTL" => "Ctrl",
      "LSHIFT" => "Shift", "RSHIFT" => "Shift", "LSHFT" => "Shift", "RSHFT" => "Shift", "LALT" => "Alt",
      "RALT" => "AltGr", "LGUI" => "Super", "RGUI" => "Super", "MEH" => "Meh",
      "SCRL_LEFT" => "Scroll ←", "SCRL_RIGHT" => "Scroll →", "SCRL_UP" => "Scroll ↑", "SCRL_DOWN" => "Scroll ↓",
      "MOVE_LEFT" => "Move ←", "MOVE_RIGHT" => "Move →", "MOVE_UP" => "Move ↑", "MOVE_DOWN" => "Move ↓",
      "MB1" => "LClick", "MB2" => "RClick", "MB3" => "MClick", "BT_CLR" => "BT Clear",
      "BT_CLR_ALL" => "BT Clear all", "BT_DISC" => "BT Disc", "BT_SEL" => "BT"
    }.freeze

    WRAPPER_LABELS = {
      "LC" => "Ctrl ", "RC" => "Ctrl ", "LS" => "⇧", "RS" => "⇧", "LA" => "Alt ", "RA" => "AltGr ",
      "LG" => "Super ", "RG" => "Super "
    }.freeze

    Code = Struct.new(:usage, :mods)

    # Resolves an expression such as `LC(LS(LALT))` or `RA(N2)`. Names with no
    # keyboard usage (media keys, say) give a nil usage: those travel in a
    # different HID report and can't be matched to a key.
    def self.parse(expression)
      mods = 0
      name = expression.to_s.delete(" ")
      while (m = name.match(/\A([A-Z]{2})\((.*)\)\z/)) && MOD_WRAPPERS.key?(m[1])
        mods |= MOD_WRAPPERS[m[1]]
        name = m[2]
      end
      return Code.new(nil, mods | MOD_BITS[name]) if MOD_BITS.key?(name)

      Code.new(USAGES[name], mods)
    end

    def self.label(expression)
      name = expression.to_s.delete(" ")
      if (m = name.match(/\A([A-Z]{2})\((.*)\)\z/)) && WRAPPER_LABELS.key?(m[1])
        return WRAPPER_LABELS[m[1]] + label(m[2])
      end
      return LABELS[name] if LABELS.key?(name)
      return name[1..] if name.match?(/\AN\d\z/)

      name
    end
  end
end
