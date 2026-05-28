package com.chenweikeng.monkeycraft.config;

/**
 * When the MonkeyCraft WebSocket server should start automatically.
 *
 * <p>Replaces the legacy {@code autoLaunch} + {@code startServerAtLaunch} boolean pair. World join
 * always follows the title screen, so {@link #AT_TITLE_SCREEN} subsumes {@link #ON_WORLD_JOIN}
 * timing-wise; the practical distinction is persistence (see {@code
 * WebSocketServerHandler#startServer}'s {@code persistent} parameter).
 */
public enum ServerAutoStart {
  /** Server stays off until {@code /monkey start} is run manually from chat. */
  OFF,

  /**
   * Server starts when MC finishes loading and remains running across world disconnects. Required
   * for the remote-server-picker flow (the app needs to connect from the title screen).
   */
  AT_TITLE_SCREEN,

  /** Server starts each time you join a world and stops on disconnect. */
  ON_WORLD_JOIN
}
