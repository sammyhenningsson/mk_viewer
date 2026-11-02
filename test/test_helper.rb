# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/mk_viewer"

module Fixtures
  KEYMAP = <<~DTS
    #define L_NAV 1
    #define SE_AT RA(N2)
    #define SE_LPAR LS(N8)
    #define MEH LC(LS(LALT))
    #define CAP(k) &NUM LS(k) k
    / {
      behaviors {
        HML: HML { compatible = "zmk,behavior-hold-tap"; #binding-cells = <2>; bindings = <&kp>, <&kp>; };
        LT_TH: LT_TH { compatible = "zmk,behavior-hold-tap"; #binding-cells = <2>; bindings = <&mo>, <&kp>; };
        NUM: NUM { compatible = "zmk,behavior-hold-tap"; #binding-cells = <2>; bindings = <&kp>, <&kp>; };
        AS_E: AS_E {
          compatible = "zmk,behavior-adaptive-key";
          #binding-cells = <0>;
          bindings = <&HML RSHIFT E>;
          as_ue { trigger-keys = <U>; bindings = <&kp O>; };
        };
      };
      keymap {
        compatible = "zmk,keymap";
        default_layer {
          display-name = "Base";
          bindings = <
            // a comment that mentions &kp Q
            &kp A  &HML LSHIFT R  &HML MEH M  &AS_E  &LT_TH L_NAV RET  CAP(J)  &none  &kp N8
          >;
        };
        nav_layer {
          display-name = "Nav";
          bindings = <
            &trans  &kp SE_AT  &kp SE_LPAR  &kp LC(V)  &to 0  &kp K_MUTE  &kp B  &trans
          >;
        };
      };
    };
  DTS

  LABELS = <<~YAML
    parse_config:
      raw_binding_map:
        "&kp SE_AT": "@"
        "&kp SE_LPAR": "("
        "&AS_E": {t: "E!", h: "RSHIFT", s: "U→O"}
  YAML

  def self.map = MkViewer::Keymap::Zmk.new(KEYMAP, labels: LABELS).map
end
