package com.chenweikeng.monkeycraft;

import com.chenweikeng.monkeycraft.server.WebSocketServerHandler;
import net.minecraft.client.Minecraft;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec2;

public class CameraController {
  private static final float TURN_SPEED = 5.0f;
  private static final float AUTO_FACE_SMOOTHING = 0.15f;

  public void tick(Minecraft client) {
    if (client.player == null) return;

    WebSocketServerHandler handler = WebSocketServerHandler.getInstance();

    if (handler.isTurningLeft()) client.player.turn(-TURN_SPEED, 0);
    if (handler.isTurningRight()) client.player.turn(TURN_SPEED, 0);
    if (handler.isLookingUp()) client.player.turn(0, -TURN_SPEED);
    if (handler.isLookingDown()) client.player.turn(0, TURN_SPEED);

    if (handler.isAutoFaceMovement()
        && !handler.isTurningLeft()
        && !handler.isTurningRight()
        && !handler.isLookingUp()
        && !handler.isLookingDown()) {
      Vec2 moveVec = client.player.input.getMoveVector();
      if (moveVec.lengthSquared() > 0.01f) {
        float targetYawOffset = (float) (Math.atan2(-moveVec.x, moveVec.y) * (180.0 / Math.PI));
        float targetYaw = client.player.getYRot() + targetYawOffset;
        float yawDiff = Mth.wrapDegrees(targetYaw - client.player.getYRot());
        float turnAmount = yawDiff * AUTO_FACE_SMOOTHING;
        client.player.turn(turnAmount, 0);
      }
    }
  }
}
