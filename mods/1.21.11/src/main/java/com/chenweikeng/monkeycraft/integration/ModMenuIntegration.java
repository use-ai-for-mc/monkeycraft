package com.chenweikeng.monkeycraft.integration;

import com.chenweikeng.monkeycraft.config.ConfigScreenFactory;
import com.terraformersmc.modmenu.api.ModMenuApi;

public class ModMenuIntegration implements ModMenuApi {
  @Override
  public com.terraformersmc.modmenu.api.ConfigScreenFactory<?> getModConfigScreenFactory() {
    return ConfigScreenFactory::createConfigScreen;
  }
}
