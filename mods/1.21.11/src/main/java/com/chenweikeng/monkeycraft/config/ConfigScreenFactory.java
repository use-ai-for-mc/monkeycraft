package com.chenweikeng.monkeycraft.config;

import com.chenweikeng.monkeycraft.utils.NetworkUtils;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import me.shedaniel.clothconfig2.api.AbstractConfigListEntry;
import me.shedaniel.clothconfig2.api.ConfigBuilder;
import me.shedaniel.clothconfig2.api.ConfigCategory;
import me.shedaniel.clothconfig2.api.ConfigEntryBuilder;
import net.minecraft.ChatFormatting;
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

    AbstractConfigListEntry<Boolean> showQrCodeWhenAutoLaunchEntry =
        entryBuilder
            .startBooleanToggle(
                Component.translatable("config.monkeycraft.option.showQrCodeWhenAutoLaunch"),
                config.isShowQrCodeWhenAutoLaunch())
            .setDefaultValue(false)
            .setTooltip(
                Component.translatable(
                    "config.monkeycraft.option.showQrCodeWhenAutoLaunch.tooltip"))
            .setSaveConsumer(config::setShowQrCodeWhenAutoLaunch)
            .build();
    general.addEntry(showQrCodeWhenAutoLaunchEntry);

    AbstractConfigListEntry<Boolean> startServerAtLaunchEntry =
        entryBuilder
            .startBooleanToggle(
                Component.translatable("config.monkeycraft.option.startServerAtLaunch"),
                config.isStartServerAtLaunch())
            .setDefaultValue(false)
            .setTooltip(
                Component.translatable("config.monkeycraft.option.startServerAtLaunch.tooltip"))
            .setSaveConsumer(config::setStartServerAtLaunch)
            .build();
    general.addEntry(startServerAtLaunchEntry);

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

    Component allowConnectionsFromTooltip =
        Component.translatable("config.monkeycraft.option.allowConnectionsFrom.tooltip");
    Component allowConnectionsFromAnywhereWarning =
        Component.translatable("config.monkeycraft.option.allowConnectionsFrom.anywhere.warning")
            .withStyle(ChatFormatting.RED, ChatFormatting.BOLD);
    AbstractConfigListEntry<AllowConnectionsFrom> allowConnectionsFromEntry =
        entryBuilder
            .startEnumSelector(
                Component.translatable("config.monkeycraft.option.allowConnectionsFrom"),
                AllowConnectionsFrom.class,
                config.getAllowConnectionsFrom())
            .setDefaultValue(AllowConnectionsFrom.ONLY_LOCAL_NETWORK)
            .setTooltipSupplier(
                (AllowConnectionsFrom mode) ->
                    mode == AllowConnectionsFrom.ANYWHERE
                        ? Optional.of(
                            new Component[] {
                              allowConnectionsFromTooltip, allowConnectionsFromAnywhereWarning
                            })
                        : Optional.of(new Component[] {allowConnectionsFromTooltip}))
            .setSaveConsumer(config::setAllowConnectionsFrom)
            .setEnumNameProvider(
                mode ->
                    Component.translatable(
                        "config.monkeycraft.option.allowConnectionsFrom."
                            + mode.name().toLowerCase()))
            .build();
    general.addEntry(allowConnectionsFromEntry);

    AbstractConfigListEntry<?> tailscaleStatusEntry =
        entryBuilder
            .startTextDescription(
                Component.translatable(
                    NetworkUtils.isTailscaleRunning()
                        ? "config.monkeycraft.status.tailscale.detected"
                        : "config.monkeycraft.status.tailscale.not_detected"))
            .build();
    general.addEntry(tailscaleStatusEntry);

    String randomPassword = ModConfig.generateRandomPassword();
    AbstractConfigListEntry<String> passwordEntry =
        entryBuilder
            .startStrField(
                Component.translatable("config.monkeycraft.option.password"), config.getPassword())
            .setDefaultValue(randomPassword)
            .setTooltip(Component.translatable("config.monkeycraft.option.password.tooltip"))
            .setSaveConsumer(config::setPassword)
            .build();
    general.addEntry(passwordEntry);

    AbstractConfigListEntry<List<String>> allowlistEntry =
        entryBuilder
            .startStrList(
                Component.translatable("config.monkeycraft.option.commandAllowlist"),
                config.getCommandAllowlist())
            .setDefaultValue(Arrays.asList("*"))
            .setTooltip(
                Component.translatable("config.monkeycraft.option.commandAllowlist.tooltip"))
            .setSaveConsumer(config::setCommandAllowlist)
            .build();
    general.addEntry(allowlistEntry);

    AbstractConfigListEntry<List<String>> denylistEntry =
        entryBuilder
            .startStrList(
                Component.translatable("config.monkeycraft.option.commandDenylist"),
                config.getCommandDenylist())
            .setDefaultValue(Arrays.asList("op *", "deop *"))
            .setTooltip(Component.translatable("config.monkeycraft.option.commandDenylist.tooltip"))
            .setSaveConsumer(config::setCommandDenylist)
            .build();
    general.addEntry(denylistEntry);

    AbstractConfigListEntry<String> defaultBehaviorEntry =
        entryBuilder
            .startStrField(
                Component.translatable("config.monkeycraft.option.defaultBehavior"),
                config.getDefaultBehavior())
            .setDefaultValue("ALLOW")
            .setTooltip(Component.translatable("config.monkeycraft.option.defaultBehavior.tooltip"))
            .setSaveConsumer(config::setDefaultBehavior)
            .build();
    general.addEntry(defaultBehaviorEntry);

    AbstractConfigListEntry<Boolean> alwaysAutoJumpEntry =
        entryBuilder
            .startBooleanToggle(
                Component.translatable("config.monkeycraft.option.alwaysAutoJump"),
                config.isAlwaysAutoJump())
            .setDefaultValue(true)
            .setTooltip(Component.translatable("config.monkeycraft.option.alwaysAutoJump.tooltip"))
            .setSaveConsumer(config::setAlwaysAutoJump)
            .build();
    general.addEntry(alwaysAutoJumpEntry);

    AbstractConfigListEntry<Boolean> allowRemoteServerJoinEntry =
        entryBuilder
            .startBooleanToggle(
                Component.translatable("config.monkeycraft.option.allowRemoteServerJoin"),
                config.isAllowRemoteServerJoin())
            .setDefaultValue(true)
            .setTooltip(
                Component.translatable("config.monkeycraft.option.allowRemoteServerJoin.tooltip"))
            .setSaveConsumer(config::setAllowRemoteServerJoin)
            .build();
    general.addEntry(allowRemoteServerJoinEntry);

    builder.setSavingRunnable(config::save);
    return builder.build();
  }
}
