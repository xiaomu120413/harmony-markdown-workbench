import {
  BridgeParser,
  BridgeEnvelope,
  ParseOk,
  RequestIdGenerator,
  ResponseTracker,
} from '../domain/bridge/BridgeProtocol';

/**
 * EditorBridge 服务层（M2-02 正式化，SDD 8.4）。
 * 职责：
 *  - 原生→Web 命令的协议封装（版本 + 请求 ID）；
 *  - Web→原生事件的协议解析与重复回包去重；
 *  - 快照/命令请求的 ID 管理。
 * 内容传输策略：快照按请求发生，禁止逐键推送全文（调用方落实）。
 */
export class EditorBridge {
  private readonly tracker: ResponseTracker = new ResponseTracker();

  /** 构造一次原生→Web 命令字符串（协议信封） */
  buildCommand(type: string, payload: object): string {
    const id = RequestIdGenerator.next();
    return BridgeParser.build(id, type, payload);
  }

  /** 解析 Web→原生事件消息；返回 undefined 表示非法消息（记录并忽略，不崩溃） */
  parseEvent(raw: string): BridgeEnvelope | undefined {
    const r = BridgeParser.parse(raw);
    if (!(r as ParseOk).ok) {
      return undefined;
    }
    return (r as ParseOk).envelope;
  }

  /** 重复回包去重：同一请求 ID 只处理首次 */
  isFirstResponse(id: string): boolean {
    return this.tracker.isFirst(id);
  }
}