package com.chenweikeng.monkeycraft.config;

import me.shedaniel.clothconfig2.api.AbstractConfigListEntry;
import me.shedaniel.clothconfig2.api.ConfigBuilder;
import me.shedaniel.clothconfig2.api.ConfigCategory;
import me.shedaniel.clothconfig2.api.ConfigEntryBuilder;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;

public class ConfigScreenFactory {
  public static Screen createConfigScreen(Screen parent) {
    ConfigBuilder builder =
        ConfigBuilder.create()
            .setParentScreen(parent)
            .setTitle(Component.translatable("config.monkeycraft.title"));

    ModConfig config = ModConfig.getInstance();
    ConfigEntryBuilder entryBuilder = builder.entryBuilder();
    ConfigCategory general =
        builder.getOrCreateCategory(Component.translatable("config.monkeycraft.category.general"));

    AbstractConfigListEntry<Boolean> enabledEntry =
        entryBuilder
            .startBooleanToggle(
                Component.translatable("config.monkeycraft.option.enabled"), config.isEnabled())
            .setDefaultValue(true)
            .setTooltip(Component.translatable("config.monkeycraft.option.enabled.tooltip"))
            .setSaveConsumer(config::setEnabled)
            .build();
    general.addEntry(enabledEntry);

    AbstractConfigListEntry<Boolean> autoLaunchEntry =
        entryBuilder
            .startBooleanToggle(
                Component.translatable("config.monkeycraft.option.autoLaunch"),
                config.isAutoLaunch())
            .setDefaultValue(false)
            .setTooltip(Component.translatable("config.monkeycraft.option.autoLaunch.tooltip"))
            .setSaveConsumer(config::setAutoLaunch)
            .build();
    general.addEntry(autoLaunchEntry);

    AbstractConfigListEntry<Integer> portEntry =
        entryBuilder
            .startIntField(
                Component.translatable("config.monkeycraft.option.port"), config.getPort())
            .setDefaultValue(9600)
            .setMin(1)
            .setMax(65535)
            .setTooltip(Component.translatable("config.monkeycraft.option.port.tooltip"))
            .setSaveConsumer(config::setPort)
            .build();
    general.addEntry(portEntry);

    AbstractConfigListEntry<String> passwordEntry =
        entryBuilder
            .startStrField(
                Component.translatable("config.monkeycraft.option.password"), config.getPassword())
            .setDefaultValue("")
            .setTooltip(Component.translatable("config.monkeycraft.option.password.tooltip"))
            .setSaveConsumer(config::setPassword)
            .build();
    general.addEntry(passwordEntry);

    builder.setSavingRunnable(config::save);
    return builder.build();
  }
}
