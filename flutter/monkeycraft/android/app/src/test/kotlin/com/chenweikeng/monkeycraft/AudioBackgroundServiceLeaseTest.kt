package com.chenweikeng.monkeycraft

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioBackgroundServiceLeaseTest {
    @Test
    fun clearOnlyStopsAServiceThisPluginStarted() {
        val lease = AudioBackgroundServiceLease()

        assertFalse(lease.clear())
        lease.markStarted()
        assertTrue(lease.clear())
        assertFalse(lease.clear())
    }
}
