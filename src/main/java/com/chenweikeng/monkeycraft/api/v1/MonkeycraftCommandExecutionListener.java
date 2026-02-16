package com.chenweikeng.monkeycraft.api.v1;

@FunctionalInterface
public interface MonkeycraftCommandExecutionListener {
  CommandExecutionResult onCommandExecution(String command);
}
