package com.chenweikeng.monkeycraft

import org.junit.Assert.assertEquals
import org.junit.Test

class AuthUrlLaunchGateTest {
    @Test
    fun automaticOpenIsDeduplicatedWithinGeneration() {
        val fixture = LauncherFixture()
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 4)
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 4)
        fixture.launcher.openAutomatic("https://login.tailscale.com/b", 4)
        fixture.runUi()
        assertEquals(listOf("https://login.tailscale.com/a", "https://login.tailscale.com/b"), fixture.opened)
    }

    @Test
    fun cancelledGenerationRejectsQueuedStartAndLateUiRunnable() {
        val fixture = LauncherFixture()
        fixture.generation = 10
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 10)
        assertEquals(1, fixture.queuedCount())
        fixture.generation = 11
        fixture.runUi()
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 10)
        fixture.runUi()
        assertEquals(emptyList<String>(), fixture.opened)
    }

    @Test
    fun stopOrDisposeBlocksLateUiRunnable() {
        val fixture = LauncherFixture()
        fixture.generation = 7
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 7)
        assertEquals(1, fixture.queuedCount())
        fixture.disposed = true
        fixture.runUi()
        assertEquals(emptyList<String>(), fixture.opened)
    }

    @Test
    fun launchFailureIsCapturedWithoutThrowingOnUiThread() {
        val fixture = LauncherFixture(throwOnOpen = true)
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 4)
        fixture.runUi()
        assertEquals(1, fixture.failures)
    }

    @Test
    fun failureSurvivesDuplicatePollUntilExplicitReopenSucceeds() {
        val fixture = LauncherFixture(throwOnOpen = true)
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 4)
        fixture.runUi()
        assertEquals(1, fixture.failures)
        assertEquals(0, fixture.successes)

        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 4)
        assertEquals(0, fixture.queuedCount())
        fixture.runUi()
        assertEquals(1, fixture.failures)
        assertEquals(0, fixture.successes)

        fixture.throwOnOpen = false
        fixture.launcher.openExplicit("https://login.tailscale.com/a", 4)
        fixture.runUi()
        assertEquals(1, fixture.successes)
        assertEquals(listOf("https://login.tailscale.com/a"), fixture.opened)
    }

    @Test
    fun explicitReopenAllowsSameUrlPerTap() {
        val fixture = LauncherFixture()
        fixture.generation = 7
        fixture.launcher.openAutomatic("https://login.tailscale.com/a", 7)
        fixture.launcher.openExplicit("https://login.tailscale.com/a", 7)
        fixture.launcher.openExplicit("https://login.tailscale.com/a", 7)
        fixture.runUi()
        assertEquals(listOf("https://login.tailscale.com/a", "https://login.tailscale.com/a", "https://login.tailscale.com/a"), fixture.opened)
    }
}

private class LauncherFixture(var throwOnOpen: Boolean = false) {
    var generation = 4L
    var disposed = false
    var failures = 0
    var successes = 0
    val opened = mutableListOf<String>()
    private val queued = mutableListOf<() -> Unit>()
    val launcher = AuthUrlLauncher(
        currentGeneration = { generation },
        isDisposed = { disposed },
        postToUi = { runnable -> queued += runnable },
        open = { url ->
            if (throwOnOpen) error("no handler")
            opened += url
        },
        onOpenSuccess = { successes += 1 },
        onOpenFailure = { failures += 1 },
    )

    fun queuedCount(): Int = queued.size

    fun runUi() {
        val pending = queued.toList()
        queued.clear()
        pending.forEach { it() }
    }
}
