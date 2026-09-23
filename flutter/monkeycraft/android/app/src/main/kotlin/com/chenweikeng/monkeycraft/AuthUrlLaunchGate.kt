package com.chenweikeng.monkeycraft

internal class AuthUrlLauncher(
    private val currentGeneration: () -> Long,
    private val isDisposed: () -> Boolean,
    private val postToUi: (() -> Unit) -> Unit,
    private val open: (String) -> Unit,
    private val onOpenSuccess: () -> Unit,
    private val onOpenFailure: () -> Unit,
) {
    private var openedUrl: String? = null
    private var openedGeneration = -1L

    fun openAutomatic(url: String, expectedGeneration: Long) {
        if (!allow(url, expectedGeneration, false)) return
        dispatch(url, expectedGeneration)
    }

    fun openExplicit(url: String, expectedGeneration: Long) {
        if (!allow(url, expectedGeneration, true)) return
        dispatch(url, expectedGeneration)
    }

    private fun dispatch(url: String, expectedGeneration: Long) {
        postToUi {
            if (isDisposed() || expectedGeneration != currentGeneration()) return@postToUi
            try {
                open(url)
            } catch (_: Throwable) {
                runCatching(onOpenFailure)
                return@postToUi
            }
            runCatching(onOpenSuccess)
        }
    }

    private fun allow(url: String, expectedGeneration: Long, explicit: Boolean): Boolean {
        if (url.isEmpty() || isDisposed() || expectedGeneration != currentGeneration()) return false
        if (!explicit && openedGeneration == expectedGeneration && openedUrl == url) return false
        openedGeneration = expectedGeneration
        openedUrl = url
        return true
    }
}
