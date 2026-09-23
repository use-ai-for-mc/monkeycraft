package com.chenweikeng.monkeycraft

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ImmediateNotificationQuotaTest {
    private val quota = ImmediateNotificationQuota(2001, 16, 990001)

    @Test
    fun retainsAtMostSixteenImmediateAlertsAndRemovesLegacyOverflow() {
        val active = (2001..2050).map { ImmediateNotificationRecord(it, it.toLong()) }

        val plan = quota.plan(2050, active)

        assertEquals((2001..2035).toList(), plan.cancelIds)
        assertEquals(2003, plan.id)
    }

    @Test
    fun rebuiltPluginUsesAnUnusedBoundedId() {
        val plan = quota.plan(2000, listOf(ImmediateNotificationRecord(2001, 10)))

        assertEquals(emptyList<Int>(), plan.cancelIds)
        assertEquals(2002, plan.id)
    }

    @Test
    fun neverCancelsProtectedIdsWhileRemovingMoreThanFiftyLegacyAlerts() {
        val protected = listOf(
            ImmediateNotificationRecord(1, 1),
            ImmediateNotificationRecord(990001, 2),
            ImmediateNotificationRecord(990002, 3),
        )
        val active = protected + (2001..2050).map { ImmediateNotificationRecord(it, it.toLong() + 10) }

        val plan = quota.plan(2050, active)

        assertEquals(35, plan.cancelIds.size)
        protected.forEach { assertFalse(plan.cancelIds.contains(it.id)) }
    }

    @Test
    fun oneHundredAlertsAcrossPluginRebuildsRemainBoundedAndKeepLatest() {
        var counter = 2000
        var active = listOf(
            ImmediateNotificationRecord(1, 1),
            ImmediateNotificationRecord(990001, 2),
            ImmediateNotificationRecord(990002, 3),
        )

        repeat(100) { index ->
            if (index % 7 == 0) counter = 2000
            val plan = quota.plan(counter, active)
            counter = plan.id
            active = active
                .filterNot { it.id in plan.cancelIds || it.id == plan.id }
                .plus(ImmediateNotificationRecord(plan.id, (index + 1).toLong() + 10))
            val immediate = active.filter { it.id in 2001 until 990001 }
            assertEquals(16.coerceAtMost(index + 1), immediate.size)
        }

        val immediateTimes = active
            .filter { it.id in 2001 until 990001 }
            .map { it.postedAt }
            .sorted()
        assertEquals((95L..110L).toList(), immediateTimes)
    }
}
