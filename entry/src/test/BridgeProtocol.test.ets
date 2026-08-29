import { describe, expect, it } from '@ohos/hypium';
import {
  BridgeParser,
  BRIDGE_PROTOCOL_VERSION,
  ParseFail,
  ParseOk,
  RequestIdGenerator,
  ResponseTracker,
} from '../main/ets/domain/bridge/BridgeProtocol';

function makePayload(text: string): ESObject {
  return { text: text } as ESObject;
}

/**
 * M2-02 领域层先行：Bridge 协议（SDD 8.4）解析/校验/去重单测。
 */
export default function bridgeProtocolTest(): void {
  describe('BridgeParser', () => {
    it('parses_valid_envelope', 0, () => {
      const raw = BridgeParser.build('r1', 'editor.loadDocument', makePayload('hi'));
      const r = BridgeParser.parse(raw);
      expect(r.ok).assertTrue();
      if (r.ok) {
        expect(r.envelope.version).assertEqual(BRIDGE_PROTOCOL_VERSION);
        expect(r.envelope.id).assertEqual('r1');
        expect(r.envelope.type).assertEqual('editor.loadDocument');
        const text: string = r.envelope.payload.text as string;
        expect(text).assertEqual('hi');
      }
    });

    it('bad_json_rejected_gracefully', 0, () => {
      const r = BridgeParser.parse('not json');
      expect(r.ok).assertFalse();
      if (!(r as ParseOk).ok) {
        expect((r as ParseFail).reason).assertEqual('bad_json');
      }
    });

    it('bad_version_rejected', 0, () => {
      const raw = '{"version":2,"id":"x","type":"t","payload":{}}';
      const r = BridgeParser.parse(raw);
      expect(r.ok).assertFalse();
      if (!(r as ParseOk).ok) {
        expect((r as ParseFail).reason).assertEqual('bad_version');
      }
    });

    it('missing_id_rejected', 0, () => {
      const raw = '{"version":1,"type":"t","payload":{}}';
      const r = BridgeParser.parse(raw);
      expect(r.ok).assertFalse();
      if (!(r as ParseOk).ok) {
        expect((r as ParseFail).reason).assertEqual('missing_id');
      }
    });

    it('unknown_type_parsed_safely', 0, () => {
      // 未知消息类型：解析成功（不崩溃），由上层记录并忽略
      const raw = BridgeParser.build('u1', 'some.unknown.event', makePayload('a'));
      const r = BridgeParser.parse(raw);
      expect(r.ok).assertTrue();
      if (r.ok) {
        expect(r.envelope.type).assertEqual('some.unknown.event');
      }
    });

    it('builder_roundtrip_preserves_payload', 0, () => {
      const big = 'x'.repeat(500);
      const raw = BridgeParser.build('r2', 'editor.snapshot', makePayload(big));
      const r = BridgeParser.parse(raw);
      expect(r.ok).assertTrue();
      if (r.ok) {
        const text: string = r.envelope.payload.text as string;
        expect(text.length).assertEqual(500);
      }
    });
  });

  describe('RequestIdGenerator', () => {
    it('generates_unique_ids', 0, () => {
      const a = RequestIdGenerator.next();
      const b = RequestIdGenerator.next();
      expect(a === b).assertFalse();
    });
  });

  describe('ResponseTracker', () => {
    it('first_seen_kept_duplicate_ignored', 0, () => {
      const t = new ResponseTracker();
      expect(t.isFirst('r1')).assertTrue();
      expect(t.isFirst('r1')).assertFalse();
      expect(t.isFirst('r2')).assertTrue();
    });

    it('unknown_message_type_never_throws', 0, () => {
      const raw = BridgeParser.build('zz', 'editor.whatever', makePayload(''));
      const r = BridgeParser.parse(raw);
      expect(r.ok).assertTrue();
    });
  });
}