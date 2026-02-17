package com.chenweikeng.monkeycraft.api.v1;

public class ChatMessageContext {
  private String message;
  private final String senderUuid;
  private final String senderName;
  private final boolean outgoing;

  public ChatMessageContext(
      String message, String senderUuid, String senderName, boolean outgoing) {
    this.message = message;
    this.senderUuid = senderUuid;
    this.senderName = senderName;
    this.outgoing = outgoing;
  }

  public String getMessage() {
    return message;
  }

  public void setMessage(String message) {
    this.message = message;
  }

  public String getSenderUuid() {
    return senderUuid;
  }

  public String getSenderName() {
    return senderName;
  }

  public boolean isOutgoing() {
    return outgoing;
  }
}
