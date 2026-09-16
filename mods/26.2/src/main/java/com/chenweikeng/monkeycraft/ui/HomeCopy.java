package com.chenweikeng.monkeycraft.ui;

final class HomeCopy {
  static final String HOME_HERO_LABEL_ADDRESS = "On your phone, type this address:";
  static final String HOME_WHY_LAN = "Local network only — the phone must be on this Wi-Fi.";
  static final String HOME_CONNECTED_TITLE = "Phone connected — happy mining!";
  static final String HOME_CONNECTED_BODY =
      "This world is being steered from your phone. You can close this screen.";

  static final String QUEST_TITLE = "First phone? A three-step quest:";
  static final String QUEST_NOTE = "A pop-up asks Allow or Deny.";
  static final String QUEST_FOOTNOTE = "After the first pairing, phones hop on with no password.";
  static final String[] QUEST_STEPS_LAN = {
    "1. Open MonkeyCraft on your phone",
    "2. Connect the phone to this Wi-Fi",
    "3. Type the address above"
  };

  static String stoppedLine() {
    return "Paused. Start the server to let phones find this computer.";
  }

  private HomeCopy() {}
}
