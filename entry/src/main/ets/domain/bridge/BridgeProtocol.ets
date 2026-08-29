/**
 * JSBridge 协议领域层（SDD 8.4）。
 * 所有消息包含协议版本与请求 ID：
 *   BridgeEnvelope { version: 1, id, type, payload }
 * 约束（本层落实的可测部分）：
 *  - 未知消息类型记录并忽略，不崩溃；
 *  - 未知/重复回包安全处理；
 *  - 版本不匹配拒绝。
 * payload 使用 ESObject（ArkTS 动态访问），类型化载荷由各调用层自行约束。
 */
export const BRIDGE_PROTOCOL_VERSION: number = 1;

export interface BridgeEnvelope {
  version: number;
  id: string;
  type: string;
  payload: ESObject;
}

export interface ParseOk {
  ok: true;
  envelope: BridgeEnvelope;
}

export type ParseFailReason = 'bad_json' | 'bad_version' | 'missing_id' | 'missing_type';

export interface ParseFail {
  ok: false;
  reason: ParseFailReason;
  message: string;
}

export type BridgeParseResult = ParseOk | ParseFail;

export class BridgeParser {
  static parse(raw: string): BridgeParseResult {
    let obj: ESObject;
    try {
      obj = JSON.parse(raw) as ESObject;
    } catch (e) {
      const fail: ParseFail = { ok: false, reason: 'bad_json', message: String(e) };
      return fail;
    }
    const version = obj.version as number;
    if (typeof version !== 'number' || version !== BRIDGE_PROTOCOL_VERSION) {
      const fail: ParseFail = { ok: false, reason: 'bad_version', message: `unsupported version: ${String(version)}` };
      return fail;
    }
    const id = obj.id as string;
    if (typeof id !== 'string' || id.length === 0) {
      const fail: ParseFail = { ok: false, reason: 'missing_id', message: 'id required' };
      return fail;
    }
    const type = obj.type as string;
    if (typeof type !== 'string' || type.length === 0) {
      const fail: ParseFail = { ok: false, reason: 'missing_type', message: 'type required' };
      return fail;
    }
    const payload: ESObject = obj.payload as ESObject;
    const envelope: BridgeEnvelope = {
      version: version,
      id: id,
      type: type,
      payload: payload,
    };
    const okResult: ParseOk = { ok: true, envelope: envelope };
    return okResult;
  }

  static build(id: string, type: string, payload: ESObject): string {
    const envelope: BridgeEnvelope = {
      version: BRIDGE_PROTOCOL_VERSION,
      id: id,
      type: type,
      payload: payload,
    };
    return JSON.stringify(envelope);
  }
}

/** 请求 ID 生成（递增 + 随机后缀，避免跨会话碰撞） */
export class RequestIdGenerator {
  private static seq: number = 0;

  static next(): string {
    RequestIdGenerator.seq++;
    const rand: number = Math.floor(Math.random() * 0xffff);
    return `${Date.now()}-${RequestIdGenerator.seq}-${rand.toString(16)}`;
  }
}

/**
 * 回包去重：同一请求 ID 的回包只处理一次（重复回包不崩溃、不重复生效）。
 */
export class ResponseTracker {
  private seen: Set<string> = new Set<string>();
  private readonly maxTracked: number;

  constructor(maxTracked: number = 256) {
    this.maxTracked = maxTracked;
  }

  /** 返回 true 表示该 id 首次出现可处理；false 表示重复 */
  isFirst(id: string): boolean {
    if (this.seen.has(id)) {
      return false;
    }
    this.seen.add(id);
    if (this.seen.size > this.maxTracked) {
      this.seen.clear();
      this.seen.add(id);
    }
    return true;
  }
}