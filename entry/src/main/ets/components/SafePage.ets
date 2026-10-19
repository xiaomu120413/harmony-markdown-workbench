/** Shared window insets for every routed page; popups use their own system safe layout. */
@Component
export struct SafePage {
  @StorageProp('safeTop') top: number = 0;
  @StorageProp('safeBottom') bottom: number = 0;
  @StorageProp('safeLeft') left: number = 0;
  @StorageProp('safeRight') right: number = 0;
  @StorageProp('keyboardVisible') keyboardVisible: boolean = false;
  @Builder emptyContent() {}
  @BuilderParam content: () => void = this.emptyContent;
  build() {
    Column() { this.content() }
      .width('100%').height('100%')
      .padding({ top: this.top, bottom: this.keyboardVisible ? 0 : this.bottom, left: this.left, right: this.right })
  }
}
