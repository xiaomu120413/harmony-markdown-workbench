/** Each mounted editor owns its bridge queue; Web callbacks only enqueue. */
export class EditorBridgeChannel {
  pending: string[] = [];
  sink: ((message: string) => void) | undefined = undefined;
  send(message: string): void { this.pending.push(message); }
}
