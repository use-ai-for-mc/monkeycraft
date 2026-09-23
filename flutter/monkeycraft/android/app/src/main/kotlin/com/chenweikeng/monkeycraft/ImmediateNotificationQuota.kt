package com.chenweikeng.monkeycraft

data class ImmediateNotificationRecord(
    val id: Int,
    val postedAt: Long,
)

data class ImmediateNotificationPlan(
    val id: Int,
    val cancelIds: List<Int>,
)

class ImmediateNotificationQuota(
    private val firstId: Int,
    private val maxCount: Int,
    private val legacyIdExclusive: Int,
) {
    fun plan(counter: Int, active: List<ImmediateNotificationRecord>): ImmediateNotificationPlan {
        val ordered = active
            .filter { it.id in firstId until legacyIdExclusive }
            .sortedWith(compareBy<ImmediateNotificationRecord> { it.postedAt }.thenBy { it.id })
        val cancelCount = (ordered.size - (maxCount - 1)).coerceAtLeast(0)
        val cancelIds = ordered.take(cancelCount).map { it.id }
        val retained = ordered.drop(cancelCount)
        val occupied = retained.map { it.id }.toSet()
        val id = candidatesAfter(counter).firstOrNull { it !in occupied }
            ?: retained.first().id
        return ImmediateNotificationPlan(id, cancelIds)
    }

    private fun candidatesAfter(counter: Int): Sequence<Int> = sequence {
        val offset = Math.floorMod(counter - firstId + 1, maxCount)
        repeat(maxCount) { step ->
            yield(firstId + (offset + step) % maxCount)
        }
    }
}
