import { describe, expect, it } from '@ohos/hypium';
import { HtmlSafety } from '../main/ets/domain/preview/HtmlSafety';

/**
 * M3-01 领域层先行：HTML 安全语料（SDD M3-01 验收项）。
 */
export default function htmlSafetyTest(): void {
  describe('HtmlSafety', () => {
    it('plain_markdown_html_is_safe', 0, () => {
      const r = HtmlSafety.inspect('<p>hello <strong>world</strong></p>');
      expect(r.safe).assertTrue();
    });

    it('script_tag_detected', 0, () => {
      const r = HtmlSafety.inspect('<script>alert(1)</script>');
      expect(r.safe).assertFalse();
      expect(r.issues.some((i) => i.kind === 'dangerous_tag')).assertTrue();
    });

    it('event_attribute_detected', 0, () => {
      const r = HtmlSafety.inspect('<img src="x.png" onerror="alert(1)">');
      expect(r.safe).assertFalse();
      expect(r.issues.some((i) => i.kind === 'event_attribute')).assertTrue();
    });

    it('javascript_url_detected', 0, () => {
      const r = HtmlSafety.inspect('<a href="javascript:alert(1)">x</a>');
      expect(r.safe).assertFalse();
      expect(r.issues.some((i) => i.kind === 'javascript_url')).assertTrue();
    });

    it('dangerous_iframe_with_src_detected', 0, () => {
      const r = HtmlSafety.inspect('<iframe src="https://evil.example"></iframe>');
      expect(r.safe).assertFalse();
      expect(r.issues.some((i) => i.kind === 'dangerous_iframe')).assertTrue();
    });

    it('object_and_embed_detected', 0, () => {
      const r = HtmlSafety.inspect('<object data="x"></object><embed src="y">');
      expect(r.issues.filter((i) => i.kind === 'dangerous_tag').length > 0).assertTrue();
    });

    it('css_expression_detected', 0, () => {
      const r = HtmlSafety.inspect('<div style="width: expression(alert(1))">x</div>');
      expect(r.safe).assertFalse();
    });

    it('multiple_issues_aggregated', 0, () => {
      const r = HtmlSafety.inspect('<script>x</script><a onclick="y">');
      expect(r.safe).assertFalse();
      expect(r.issues.length >= 2).assertTrue();
    });
  });
}