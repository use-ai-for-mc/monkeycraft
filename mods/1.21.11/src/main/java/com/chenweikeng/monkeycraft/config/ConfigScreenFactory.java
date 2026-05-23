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

    Component networkScopeTooltip =
        Component.translatable("config.monkeycraft.option.networkScope.tooltip");
    Component networkScopeAnyoneWarning =
        Component.translatable("config.monkeycraft.option.networkScope.anyone.warning")
            .withStyle(ChatFormatting.RED, ChatFormatting.BOLD);
    AbstractConfigListEntry<NetworkScope> networkScopeEntry =
        entryBuilder
            .startEnumSelector(
                Component.translatable("config.monkeycraft.option.networkScope"),
                NetworkScope.class,
                config.getNetworkScope())
            .setDefaultValue(NetworkScope.LOCAL_NETWORK)
            .setTooltipSupplier(
                (NetworkScope mode) ->
                    mode == NetworkScope.ANYONE
                        ? Optional.of(
                            new Component[] {networkScopeTooltip, networkScopeAnyoneWarning})
                        : Optional.of(new Component[] {networkScopeTooltip}))
            .setSaveConsumer(config::setNetworkScope)
            .setEnumNameProvider(
                mode ->
                    Component.translatable(
                        "config.monkeycraft.option.networkScope." + mode.name().toLowerCase()))
            .build();
    general.addEntry(networkScopeEntry);

    boolean tailscaleDetected = NetworkUtils.isTailscaleRunning();
    Component tailscaleAccessTooltip =
        Component.translatable("config.monkeycraft.option.tailscaleAccess.tooltip");
    Component tailscaleDetectionStatus =
        Component.translatable(
                tailscaleDetected
                    ? "config.monkeycraft.option.tailscaleAccess.status.detected"
                    : "config.monkeycraft.option.tailscaleAccess.status.not_detected")
            .withStyle(tailscaleDetected ? ChatFormatting.GREEN : ChatFormatting.GRAY);
    AbstractConfigListEntry<TailscaleAccess> tailscaleAccessEntry =
        entryBuilder
            .startEnumSelector(
                Component.translatable("config.monkeycraft.option.tailscaleAccess"),
                TailscaleAccess.class,
                config.getTailscaleAccess())
            .setDefaultValue(TailscaleAccess.IF_DETECTED)
            .setTooltipSupplier(
                (TailscaleAccess mode) ->
                    Optional.of(new Component[] {tailscaleAccessTooltip, tailscaleDetectionStatus}))
            .setSaveConsumer(config::setTailscaleAccess)
            .setEnumNameProvider(
                mode ->
                    Component.translatable(
                        "config.monkeycraft.option.tailscaleAccess." + mode.name().toLowerCase()))
            .build();
    general.addEntry(tailscaleAccessEntry);

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
